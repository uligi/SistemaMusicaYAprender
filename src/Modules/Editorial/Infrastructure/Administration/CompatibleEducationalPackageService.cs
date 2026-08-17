using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Editorial.Infrastructure.Administration;

public interface ICompatibleEducationalPackageTransactionExecutor
{
    Task<TResult> ExecuteAsync<TResult>(
        Guid actorAccountId,
        string correlationId,
        Func<NpgsqlConnection, NpgsqlTransaction, CancellationToken, Task<TResult>> operation,
        CancellationToken cancellationToken = default);
}

public sealed record CompatiblePackageSelectionInput(
    Guid LyricsRevisionId,
    Guid TimingRevisionId,
    Guid TranslationRevisionId,
    Guid AnalysisRevisionId,
    IReadOnlyList<Guid> ExerciseRevisionIds,
    string Reason);

public sealed record CompatiblePackageSelection(
    Guid? LyricsRevisionId,
    Guid? TimingRevisionId,
    Guid? TranslationRevisionId,
    Guid? AnalysisRevisionId,
    IReadOnlyList<Guid> ExerciseRevisionIds);

public sealed record CompatiblePackageCandidate(
    string ComponentKind,
    Guid RevisionId,
    int RevisionNo,
    string StatusCode,
    string ChecksumSha256,
    Guid SourceLyricsRevisionId,
    string Label,
    string? Preview,
    bool Eligible,
    IReadOnlyList<string> Issues);

public sealed record CompatiblePackageChecklist(
    bool HasLyrics,
    bool HasTiming,
    bool HasTranslation,
    bool HasAnalysis,
    bool HasExercise,
    bool SourcesCompatible,
    bool ExercisesEligible,
    bool HasActiveRights,
    bool HasBrokenLinks,
    bool PackageChecksumCurrent,
    bool ReadyForFreeze,
    IReadOnlyList<string> Issues);

public sealed record CompatiblePackageSnapshot(
    Guid RecordingId,
    long CatalogVersion,
    Guid? PackageId,
    int? PackageNo,
    string StatusCode,
    long Version,
    string? ChecksumSha256,
    string ETag,
    CompatiblePackageSelection Selection,
    IReadOnlyList<CompatiblePackageCandidate> Candidates,
    CompatiblePackageChecklist Checklist,
    string Message);

public sealed class CompatibleEducationalPackageException(
    string code,
    string message) : InvalidOperationException(message)
{
    public string Code { get; } = code;
}

public sealed class CompatibleEducationalPackageService(
    ICompatibleEducationalPackageTransactionExecutor transactions)
{
    private static readonly HashSet<string> TerminalRevisionStatuses =
        new(StringComparer.Ordinal)
        {
            "REJECTED",
            "WITHDRAWN",
            "SUPERSEDED"
        };

    public Task<CompatiblePackageSnapshot> ReadAsync(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentity(actorAccountId, recordingId, correlationId);

        return transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                ReadCoreAsync(connection, transaction, recordingId, token),
            cancellationToken);
    }

    public Task<CompatiblePackageSnapshot> SaveAsync(
        Guid actorAccountId,
        Guid recordingId,
        CompatiblePackageSelectionInput input,
        string ifMatch,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(input);
        ValidateIdentity(actorAccountId, recordingId, correlationId);

        if (string.IsNullOrWhiteSpace(ifMatch))
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.precondition-required",
                "Recarga el paquete antes de guardar una selección.");
        }

        return transactions.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                await AcquireRecordingLockAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);

                var catalogVersion = await ReadRecordingVersionAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);

                var current = await ReadDraftHeaderAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);

                var expectedEtag = ETagFor(recordingId, current);
                if (!string.Equals(
                        expectedEtag,
                        ifMatch.Trim(),
                        StringComparison.Ordinal))
                {
                    throw new CompatibleEducationalPackageException(
                        "editorial.package.source-changed",
                        "El paquete DRAFT cambió. Conserva tu selección visible y recarga antes de guardar.");
                }

                var reason = NormalizeReason(input.Reason);
                var prepared = await PrepareSelectionAsync(
                    connection,
                    transaction,
                    recordingId,
                    input,
                    token);

                if (!prepared.HasActiveRights)
                {
                    throw new CompatibleEducationalPackageException(
                        "editorial.package.rights.required",
                        "El expediente necesita al menos una autorización vigente antes de quedar listo para revisión.");
                }

                var checksum = BuildPackageChecksum(
                    recordingId,
                    catalogVersion,
                    prepared.Components);

                PackageHeader header;
                if (current is null)
                {
                    header = await InsertPackageAsync(
                        connection,
                        transaction,
                        actorAccountId,
                        recordingId,
                        checksum,
                        token);
                }
                else
                {
                    EnsureMutable(current);

                    if (current.Checksum.AsSpan().SequenceEqual(checksum)
                        && await ComponentsMatchAsync(
                            connection,
                            transaction,
                            current.PackageId,
                            prepared.Components,
                            token))
                    {
                        return await ReadCoreAsync(
                            connection,
                            transaction,
                            recordingId,
                            token);
                    }

                    header = current;
                }

                var beforeDigest = header.Checksum;

                await ReplaceComponentsAsync(
                    connection,
                    transaction,
                    header.PackageId,
                    prepared.Components,
                    token);

                await UpdatePackageChecksumAsync(
                    connection,
                    transaction,
                    header.PackageId,
                    checksum,
                    token);

                var updated = await ReadDraftHeaderAsync(
                    connection,
                    transaction,
                    recordingId,
                    token)
                    ?? throw new InvalidOperationException(
                        "El paquete guardado no pudo releerse.");

                await WriteAuditAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    updated.PackageId,
                    beforeDigest,
                    updated.Checksum,
                    reason,
                    correlationId,
                    token);

                return await ReadCoreAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);
            },
            cancellationToken);
    }

    public static string ETagFor(
        Guid recordingId,
        Guid? packageId,
        long version,
        string? checksumSha256)
    {
        if (packageId is null)
        {
            return $"\"package-{recordingId:N}-none\"";
        }

        return $"\"package-{packageId.Value:N}-v{version}-{checksumSha256 ?? "none"}\"";
    }

    private static string ETagFor(Guid recordingId, PackageHeader? header) =>
        header is null
            ? ETagFor(recordingId, null, 0, null)
            : ETagFor(
                recordingId,
                header.PackageId,
                header.Version,
                Convert.ToHexString(header.Checksum).ToLowerInvariant());

    private static async Task<CompatiblePackageSnapshot> ReadCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        var catalogVersion = await ReadRecordingVersionAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        var header = await ReadDraftHeaderAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        var candidates = await ReadCandidatesAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        var selected = header is null
            ? []
            : await ReadSelectedComponentsAsync(
                connection,
                transaction,
                header.PackageId,
                cancellationToken);

        var selection = ToSelection(selected);
        var hasRights = await HasActiveRightsAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        var packageChecksumCurrent =
            header is null
            || PackageChecksumMatchesCurrentSources(
                recordingId,
                catalogVersion,
                header.Checksum,
                selected,
                candidates);

        var checklist = BuildChecklist(
            selection,
            candidates,
            hasRights,
            packageChecksumCurrent);

        return new CompatiblePackageSnapshot(
            recordingId,
            catalogVersion,
            header?.PackageId,
            header?.PackageNo,
            header?.StatusCode ?? "NOT_CREATED",
            header?.Version ?? 0,
            header is null
                ? null
                : Convert.ToHexString(header.Checksum).ToLowerInvariant(),
            ETagFor(recordingId, header),
            selection,
            candidates,
            checklist,
            header is null
                ? "Selecciona revisiones exactas. Nada se publica al guardar este DRAFT."
                : checklist.ReadyForFreeze
                    ? "Paquete compatible guardado. BL-MVP-048 será quien lo congele y someta a revisión."
                    : "Paquete DRAFT guardado con pendientes. Corrige los enlaces antes de congelar.");
    }

    private static CompatiblePackageSelection ToSelection(
        IReadOnlyList<ComponentReference> components)
    {
        Guid? Find(string kind) =>
            components
                .Where(component => component.ComponentKind == kind)
                .Select(component => (Guid?)component.RevisionId)
                .SingleOrDefault();

        return new CompatiblePackageSelection(
            Find("LYRICS"),
            Find("TIMING"),
            Find("TRANSLATION"),
            Find("ANALYSIS"),
            components
                .Where(component => component.ComponentKind == "EXERCISE")
                .OrderBy(component => component.RevisionId)
                .Select(component => component.RevisionId)
                .ToArray());
    }

    private static CompatiblePackageChecklist BuildChecklist(
        CompatiblePackageSelection selection,
        IReadOnlyList<CompatiblePackageCandidate> candidates,
        bool hasActiveRights,
        bool packageChecksumCurrent)
    {
        var issues = new List<string>();

        var hasLyrics = selection.LyricsRevisionId.HasValue;
        var hasTiming = selection.TimingRevisionId.HasValue;
        var hasTranslation = selection.TranslationRevisionId.HasValue;
        var hasAnalysis = selection.AnalysisRevisionId.HasValue;
        var hasExercise = selection.ExerciseRevisionIds.Count > 0;

        if (!hasLyrics) issues.Add("Selecciona una revisión exacta de letra.");
        if (!hasTiming) issues.Add("Selecciona una revisión exacta de sincronización.");
        if (!hasTranslation) issues.Add("Selecciona una revisión exacta de traducción.");
        if (!hasAnalysis) issues.Add("Selecciona una revisión exacta de análisis.");
        if (!hasExercise) issues.Add("Selecciona al menos un ejercicio validable.");

        var selectedIds = new HashSet<Guid>(
            selection.ExerciseRevisionIds);

        foreach (var id in new[]
                 {
                     selection.LyricsRevisionId,
                     selection.TimingRevisionId,
                     selection.TranslationRevisionId,
                     selection.AnalysisRevisionId
                 }.Where(id => id.HasValue).Select(id => id!.Value))
        {
            selectedIds.Add(id);
        }

        var chosen = candidates
            .Where(candidate => selectedIds.Contains(candidate.RevisionId))
            .ToArray();

        var broken = chosen
            .Where(candidate => !candidate.Eligible)
            .SelectMany(candidate => candidate.Issues)
            .Distinct(StringComparer.Ordinal)
            .ToList();

        issues.AddRange(broken);

        var sourceLyricsId = selection.LyricsRevisionId;
        var sourceCompatible =
            sourceLyricsId.HasValue
            && chosen
                .Where(candidate => candidate.ComponentKind != "LYRICS")
                .All(candidate => candidate.SourceLyricsRevisionId == sourceLyricsId.Value);

        if (hasLyrics && !sourceCompatible)
        {
            issues.Add(
                "Hay componentes que no pertenecen a la revisión de letra seleccionada.");
        }

        var exercisesEligible =
            selection.ExerciseRevisionIds.Count > 0
            && selection.ExerciseRevisionIds.All(id =>
                candidates.Any(candidate =>
                    candidate.ComponentKind == "EXERCISE"
                    && candidate.RevisionId == id
                    && candidate.Eligible
                    && (!sourceLyricsId.HasValue
                        || candidate.SourceLyricsRevisionId == sourceLyricsId.Value)));

        if (hasExercise && !exercisesEligible)
        {
            issues.Add(
                "Uno o más ejercicios tienen enlaces rotos, ambigüedad o una fuente incompatible.");
        }

        if (!hasActiveRights)
        {
            issues.Add(
                "Falta una autorización vigente en el expediente editorial.");
        }

        if (!packageChecksumCurrent)
        {
            issues.Add(
                "El catálogo o un componente cambió después del último guardado; vuelve a validar el paquete.");
        }

        var hasBrokenLinks =
            broken.Count > 0
            || (hasLyrics && !sourceCompatible)
            || !packageChecksumCurrent;

        var ready =
            hasLyrics
            && hasTiming
            && hasTranslation
            && hasAnalysis
            && hasExercise
            && sourceCompatible
            && exercisesEligible
            && hasActiveRights
            && packageChecksumCurrent
            && !hasBrokenLinks;

        return new CompatiblePackageChecklist(
            hasLyrics,
            hasTiming,
            hasTranslation,
            hasAnalysis,
            hasExercise,
            sourceCompatible,
            exercisesEligible,
            hasActiveRights,
            hasBrokenLinks,
            packageChecksumCurrent,
            ready,
            issues.Distinct(StringComparer.Ordinal).ToArray());
    }

    private static async Task<PreparedSelection> PrepareSelectionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CompatiblePackageSelectionInput input,
        CancellationToken cancellationToken)
    {
        if (input.LyricsRevisionId == Guid.Empty
            || input.TimingRevisionId == Guid.Empty
            || input.TranslationRevisionId == Guid.Empty
            || input.AnalysisRevisionId == Guid.Empty)
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.components.required",
                "Letra, sincronización, traducción y análisis requieren una revisión exacta.");
        }

        var exerciseIds = input.ExerciseRevisionIds?
            .Where(id => id != Guid.Empty)
            .Distinct()
            .OrderBy(id => id)
            .ToArray() ?? [];

        if (exerciseIds.Length == 0)
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.exercise.required",
                "Selecciona al menos un ejercicio para validar dentro del paquete.");
        }

        if (exerciseIds.Length > 100)
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.exercise.too-many",
                "Un paquete DRAFT no puede seleccionar más de 100 ejercicios.");
        }

        var components = new List<ComponentReference>
        {
            await ResolveLyricsAsync(
                connection,
                transaction,
                recordingId,
                input.LyricsRevisionId,
                cancellationToken),
            await ResolveTimingAsync(
                connection,
                transaction,
                recordingId,
                input.TimingRevisionId,
                cancellationToken),
            await ResolveTranslationAsync(
                connection,
                transaction,
                recordingId,
                input.TranslationRevisionId,
                cancellationToken),
            await ResolveAnalysisAsync(
                connection,
                transaction,
                recordingId,
                input.AnalysisRevisionId,
                cancellationToken)
        };

        foreach (var exerciseId in exerciseIds)
        {
            components.Add(
                await ResolveExerciseAsync(
                    connection,
                    transaction,
                    recordingId,
                    exerciseId,
                    cancellationToken));
        }

        var lyrics = components.Single(component =>
            component.ComponentKind == "LYRICS");

        foreach (var component in components.Where(component =>
                     component.ComponentKind != "LYRICS"))
        {
            if (component.SourceLyricsRevisionId != lyrics.RevisionId)
            {
                throw new CompatibleEducationalPackageException(
                    "editorial.package.source-incompatible",
                    $"{component.ComponentKind} no pertenece a la revisión de letra exacta seleccionada.");
            }
        }

        return new PreparedSelection(
            components,
            await HasActiveRightsAsync(
                connection,
                transaction,
                recordingId,
                cancellationToken));
    }

    private static async Task<ComponentReference> ResolveLyricsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid revisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT revision_no, status_code, checksum
            FROM content.lyrics_revision
            WHERE lyrics_revision_id = @revision_id
              AND recording_id = @recording_id;
            """;

        var row = await ReadBasicRevisionAsync(
            connection,
            transaction,
            sql,
            recordingId,
            revisionId,
            cancellationToken);

        EnsureRevisionEligible("LYRICS", row.StatusCode);

        return new ComponentReference(
            "LYRICS",
            revisionId,
            revisionId,
            row.Checksum);
    }

    private static async Task<ComponentReference> ResolveTimingAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid revisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT t.revision_no, t.status_code, t.checksum, t.lyrics_revision_id
            FROM content.timing_revision t
            JOIN content.lyrics_revision l
              ON l.lyrics_revision_id = t.lyrics_revision_id
            JOIN catalog.recording_source s
              ON s.source_id = t.source_id
            WHERE t.timing_revision_id = @revision_id
              AND l.recording_id = @recording_id
              AND s.recording_id = @recording_id;
            """;

        var row = await ReadSourcedRevisionAsync(
            connection,
            transaction,
            sql,
            recordingId,
            revisionId,
            cancellationToken);

        EnsureRevisionEligible("TIMING", row.StatusCode);

        return new ComponentReference(
            "TIMING",
            revisionId,
            row.SourceLyricsRevisionId,
            row.Checksum);
    }

    private static async Task<ComponentReference> ResolveTranslationAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid revisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT t.revision_no, t.status_code, t.checksum, t.lyrics_revision_id
            FROM content.translation_revision t
            JOIN content.lyrics_revision l
              ON l.lyrics_revision_id = t.lyrics_revision_id
            WHERE t.translation_revision_id = @revision_id
              AND l.recording_id = @recording_id;
            """;

        var row = await ReadSourcedRevisionAsync(
            connection,
            transaction,
            sql,
            recordingId,
            revisionId,
            cancellationToken);

        EnsureRevisionEligible("TRANSLATION", row.StatusCode);

        return new ComponentReference(
            "TRANSLATION",
            revisionId,
            row.SourceLyricsRevisionId,
            row.Checksum);
    }

    private static async Task<ComponentReference> ResolveAnalysisAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid revisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT a.revision_no, a.status_code, a.checksum, a.lyrics_revision_id
            FROM content.linguistic_analysis_revision a
            JOIN content.lyrics_revision l
              ON l.lyrics_revision_id = a.lyrics_revision_id
            WHERE a.analysis_revision_id = @revision_id
              AND l.recording_id = @recording_id;
            """;

        var row = await ReadSourcedRevisionAsync(
            connection,
            transaction,
            sql,
            recordingId,
            revisionId,
            cancellationToken);

        EnsureRevisionEligible("ANALYSIS", row.StatusCode);

        return new ComponentReference(
            "ANALYSIS",
            revisionId,
            row.SourceLyricsRevisionId,
            row.Checksum);
    }

    private static async Task<ComponentReference> ResolveExerciseAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid revisionId,
        CancellationToken cancellationToken)
    {
        var candidate = await ReadExerciseCandidateAsync(
            connection,
            transaction,
            recordingId,
            revisionId,
            cancellationToken);

        if (!candidate.Eligible)
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.exercise.invalid",
                candidate.Issues.Count > 0
                ? candidate.Issues[0]
                : "El ejercicio no supera la validación editorial del paquete.");
        }

        return new ComponentReference(
            "EXERCISE",
            revisionId,
            candidate.SourceLyricsRevisionId,
            Convert.FromHexString(candidate.ChecksumSha256));
    }

    private static void EnsureRevisionEligible(
        string kind,
        string statusCode)
    {
        if (TerminalRevisionStatuses.Contains(statusCode))
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.component.terminal",
                $"{kind} está en estado {statusCode} y no puede entrar al paquete.");
        }
    }

    private static async Task<IReadOnlyList<CompatiblePackageCandidate>> ReadCandidatesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        var results = new List<CompatiblePackageCandidate>();

        await ReadSimpleCandidatesAsync(
            connection,
            transaction,
            results,
            "LYRICS",
            """
            SELECT
                l.lyrics_revision_id,
                l.revision_no,
                l.status_code,
                encode(l.checksum, 'hex'),
                l.lyrics_revision_id,
                'Letra · revisión ' || l.revision_no
            FROM content.lyrics_revision l
            WHERE l.recording_id = @recording_id
            ORDER BY l.revision_no DESC, l.lyrics_revision_id DESC;
            """,
            recordingId,
            cancellationToken);

        await ReadSimpleCandidatesAsync(
            connection,
            transaction,
            results,
            "TIMING",
            """
            SELECT
                t.timing_revision_id,
                t.revision_no,
                t.status_code,
                encode(t.checksum, 'hex'),
                t.lyrics_revision_id,
                'Sincronización · revisión ' || t.revision_no
            FROM content.timing_revision t
            JOIN content.lyrics_revision l
              ON l.lyrics_revision_id = t.lyrics_revision_id
            JOIN catalog.recording_source s
              ON s.source_id = t.source_id
            WHERE l.recording_id = @recording_id
              AND s.recording_id = @recording_id
            ORDER BY t.revision_no DESC, t.timing_revision_id DESC;
            """,
            recordingId,
            cancellationToken);

        await ReadSimpleCandidatesAsync(
            connection,
            transaction,
            results,
            "TRANSLATION",
            """
            SELECT
                t.translation_revision_id,
                t.revision_no,
                t.status_code,
                encode(t.checksum, 'hex'),
                t.lyrics_revision_id,
                'Traducción ' || t.target_language || ' · revisión ' || t.revision_no
            FROM content.translation_revision t
            JOIN content.lyrics_revision l
              ON l.lyrics_revision_id = t.lyrics_revision_id
            WHERE l.recording_id = @recording_id
            ORDER BY t.revision_no DESC, t.translation_revision_id DESC;
            """,
            recordingId,
            cancellationToken);

        await ReadSimpleCandidatesAsync(
            connection,
            transaction,
            results,
            "ANALYSIS",
            """
            SELECT
                a.analysis_revision_id,
                a.revision_no,
                a.status_code,
                encode(a.checksum, 'hex'),
                a.lyrics_revision_id,
                'Análisis · revisión ' || a.revision_no
            FROM content.linguistic_analysis_revision a
            JOIN content.lyrics_revision l
              ON l.lyrics_revision_id = a.lyrics_revision_id
            WHERE l.recording_id = @recording_id
            ORDER BY a.revision_no DESC, a.analysis_revision_id DESC;
            """,
            recordingId,
            cancellationToken);

        const string exerciseIdsSql = """
            SELECT r.exercise_revision_id
            FROM learning.exercise_revision r
            JOIN learning.exercise_definition d
              ON d.exercise_id = r.exercise_id
            WHERE d.recording_id = @recording_id
            ORDER BY r.revision_no DESC, r.exercise_revision_id DESC;
            """;

        var exerciseIds = new List<Guid>();
        await using (var command = new NpgsqlCommand(
                         exerciseIdsSql,
                         connection,
                         transaction))
        {
            command.Parameters.AddWithValue(
                "recording_id",
                NpgsqlDbType.Uuid,
                recordingId);

            await using var reader =
                await command.ExecuteReaderAsync(cancellationToken);

            while (await reader.ReadAsync(cancellationToken))
            {
                exerciseIds.Add(reader.GetGuid(0));
            }
        }

        foreach (var exerciseId in exerciseIds)
        {
            results.Add(
                await ReadExerciseCandidateAsync(
                    connection,
                    transaction,
                    recordingId,
                    exerciseId,
                    cancellationToken));
        }

        return results;
    }

    private static async Task ReadSimpleCandidatesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        List<CompatiblePackageCandidate> results,
        string kind,
        string sql,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            var status = reader.GetString(2);
            var issues = TerminalRevisionStatuses.Contains(status)
                ? new[] { $"{kind} está en estado terminal {status}." }
                : [];

            results.Add(
                new CompatiblePackageCandidate(
                    kind,
                    reader.GetGuid(0),
                    reader.GetInt32(1),
                    status,
                    reader.GetString(3),
                    reader.GetGuid(4),
                    reader.GetString(5),
                    null,
                    issues.Length == 0,
                    issues));
        }
    }

    private static async Task<CompatiblePackageCandidate> ReadExerciseCandidateAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid exerciseRevisionId,
        CancellationToken cancellationToken)
    {
        const string headerSql = """
            SELECT
                r.exercise_revision_id,
                r.revision_no,
                r.status_code,
                encode(r.checksum, 'hex'),
                r.prompt,
                r.solution_spec::text,
                d.exercise_type,
                d.line_id,
                s.lyrics_revision_id,
                l.line_no,
                l.japanese_text
            FROM learning.exercise_revision r
            JOIN learning.exercise_definition d
              ON d.exercise_id = r.exercise_id
            LEFT JOIN content.lyric_line l
              ON l.line_id = d.line_id
            LEFT JOIN content.lyric_section s
              ON s.section_id = l.section_id
            WHERE r.exercise_revision_id = @revision_id
              AND d.recording_id = @recording_id;
            """;

        ExerciseHeader? header = null;

        await using (var command = new NpgsqlCommand(
                         headerSql,
                         connection,
                         transaction))
        {
            command.Parameters.AddWithValue(
                "revision_id",
                NpgsqlDbType.Uuid,
                exerciseRevisionId);
            command.Parameters.AddWithValue(
                "recording_id",
                NpgsqlDbType.Uuid,
                recordingId);

            await using var reader =
                await command.ExecuteReaderAsync(cancellationToken);

            if (await reader.ReadAsync(cancellationToken))
            {
                header = new ExerciseHeader(
                    reader.GetGuid(0),
                    reader.GetInt32(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.GetString(5),
                    reader.GetString(6),
                    reader.IsDBNull(7) ? null : reader.GetGuid(7),
                    reader.IsDBNull(8) ? null : reader.GetGuid(8),
                    reader.IsDBNull(9) ? null : reader.GetInt32(9),
                    reader.IsDBNull(10) ? null : reader.GetString(10));
            }
        }

        if (header is null)
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.exercise.not-found",
                "La revisión de ejercicio solicitada no pertenece a esta grabación.");
        }

        var issues = new List<string>();

        if (TerminalRevisionStatuses.Contains(header.StatusCode))
        {
            issues.Add(
                $"El ejercicio está en estado terminal {header.StatusCode}.");
        }

        if (!string.Equals(
                header.ExerciseType,
                "FILL_BLANK_OPTIONS",
                StringComparison.Ordinal))
        {
            issues.Add(
                "Solo FILL_BLANK_OPTIONS pertenece al alcance P0.");
        }

        if (header.LineId is null || header.SourceLyricsRevisionId is null)
        {
            issues.Add(
                "El ejercicio no conserva una línea dentro de una revisión de letra.");
        }

        ValidateSolutionSpec(header.SolutionSpecJson, issues);

        var items = await ReadExerciseItemsAsync(
            connection,
            transaction,
            exerciseRevisionId,
            cancellationToken);

        var optionItems = items
            .Where(item => item.ItemType == "OPTION")
            .OrderBy(item => item.ItemOrder)
            .ToArray();

        if (optionItems.Length is < 3 or > 5)
        {
            issues.Add(
                "Completar espacios requiere entre 3 y 5 opciones publicables.");
        }

        var normalizedOptions = optionItems
            .Select(item => NormalizeOption(item.Value))
            .ToArray();

        if (normalizedOptions.Any(string.IsNullOrWhiteSpace)
            || normalizedOptions.Distinct(StringComparer.Ordinal).Count()
                != normalizedOptions.Length)
        {
            issues.Add(
                "Las opciones publicables deben ser no vacías y distinguibles.");
        }

        var correct = optionItems
            .Where(item =>
                string.Equals(
                    item.Role,
                    "CORRECT",
                    StringComparison.Ordinal))
            .ToArray();

        if (correct.Length != 1)
        {
            issues.Add(
                "La revisión necesita exactamente una opción CORRECT para el modelo P0.");
        }

        if (correct.Length == 1)
        {
            if (correct[0].SourceTokenId is not { } tokenId
                || header.LineId is not { } lineId
                || !await TokenBelongsToLineAsync(
                    connection,
                    transaction,
                    tokenId,
                    lineId,
                    cancellationToken))
            {
                issues.Add(
                    "La opción correcta no conserva un token fuente válido de la línea exacta.");
            }
        }

        if (!await HasExerciseProvenanceAsync(
                connection,
                transaction,
                exerciseRevisionId,
                cancellationToken))
        {
            issues.Add(
                "La revisión de ejercicio no conserva procedencia editorial.");
        }

        return new CompatiblePackageCandidate(
            "EXERCISE",
            header.ExerciseRevisionId,
            header.RevisionNo,
            header.StatusCode,
            header.ChecksumSha256,
            header.SourceLyricsRevisionId ?? Guid.Empty,
            $"Ejercicio · revisión {header.RevisionNo}",
            header.JapaneseText is null
                ? header.Prompt
                : $"{header.JapaneseText} — {header.Prompt}",
            issues.Count == 0,
            issues.Distinct(StringComparer.Ordinal).ToArray());
    }

    private static void ValidateSolutionSpec(
        string solutionSpecJson,
        List<string> issues)
    {
        try
        {
            using var document = JsonDocument.Parse(solutionSpecJson);
            var root = document.RootElement;

            if (!root.TryGetProperty("schemaVersion", out var schemaVersion)
                || schemaVersion.ValueKind != JsonValueKind.Number
                || schemaVersion.GetInt32() != 1)
            {
                issues.Add(
                    "El esquema de solución no es la versión P0 reconocida.");
            }

            if (!root.TryGetProperty("answerModel", out var answerModel)
                || !string.Equals(
                    answerModel.GetString(),
                    "SINGLE_CHOICE",
                    StringComparison.Ordinal))
            {
                issues.Add(
                    "El ejercicio no usa el modelo SINGLE_CHOICE reproducible.");
            }

            if (!root.TryGetProperty(
                    "acceptedItemOrders",
                    out var acceptedOrders)
                || acceptedOrders.ValueKind != JsonValueKind.Array
                || acceptedOrders.GetArrayLength() == 0)
            {
                issues.Add(
                    "La solución no declara alternativas aceptadas explícitas.");
            }

            if (!root.TryGetProperty("explanation", out var explanation)
                || string.IsNullOrWhiteSpace(explanation.GetString()))
            {
                issues.Add(
                    "Falta explicación educativa.");
            }

            if (!root.TryGetProperty("feedback", out var feedback)
                || !feedback.TryGetProperty("correct", out var correctFeedback)
                || string.IsNullOrWhiteSpace(correctFeedback.GetString())
                || !feedback.TryGetProperty("incorrect", out var incorrectFeedback)
                || string.IsNullOrWhiteSpace(incorrectFeedback.GetString()))
            {
                issues.Add(
                    "Falta retroalimentación textual para acierto y error.");
            }

            if (!root.TryGetProperty("difficulty", out var difficulty)
                || !difficulty.TryGetProperty("code", out var difficultyCode)
                || string.IsNullOrWhiteSpace(difficultyCode.GetString())
                || !difficulty.TryGetProperty(
                    "justification",
                    out var justification)
                || string.IsNullOrWhiteSpace(justification.GetString()))
            {
                issues.Add(
                    "Falta dificultad P0 con justificación.");
            }

            var forbidden = new[]
            {
                "minigame",
                "lives",
                "combo",
                "score",
                "timer"
            };

            foreach (var property in forbidden)
            {
                if (root.TryGetProperty(property, out _))
                {
                    issues.Add(
                        $"La función P2 '{property}' no puede entrar al paquete P0.");
                }
            }
        }
        catch (JsonException)
        {
            issues.Add(
                "La solución del ejercicio no tiene JSON versionado válido.");
        }
    }

    private static async Task<IReadOnlyList<ExerciseItemRow>> ReadExerciseItemsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid exerciseRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                item_type,
                item_order,
                prompt_fragment,
                expected_value::text,
                metadata::text
            FROM learning.exercise_item
            WHERE exercise_revision_id = @revision_id
            ORDER BY item_order, exercise_item_id;
            """;

        var results = new List<ExerciseItemRow>();

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "revision_id",
            NpgsqlDbType.Uuid,
            exerciseRevisionId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            var metadataJson = reader.GetString(4);
            string? role = null;
            Guid? sourceTokenId = null;

            try
            {
                using var document = JsonDocument.Parse(metadataJson);
                var root = document.RootElement;

                if (root.TryGetProperty("role", out var roleElement))
                {
                    role = roleElement.GetString();
                }

                if (root.TryGetProperty(
                        "sourceTokenId",
                        out var tokenElement)
                    && Guid.TryParse(
                        tokenElement.GetString(),
                        out var parsedToken)
                    && parsedToken != Guid.Empty)
                {
                    sourceTokenId = parsedToken;
                }
            }
            catch (JsonException)
            {
                // Se conserva como inválido y la validación siguiente lo detecta.
            }

            var expectedValue = reader.IsDBNull(3)
                ? null
                : JsonStringValue(reader.GetString(3));

            results.Add(
                new ExerciseItemRow(
                    reader.GetString(0),
                    reader.GetInt32(1),
                    expectedValue
                        ?? (reader.IsDBNull(2) ? string.Empty : reader.GetString(2)),
                    role,
                    sourceTokenId));
        }

        return results;
    }

    private static async Task<bool> TokenBelongsToLineAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid tokenId,
        Guid lineId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM content.lyric_token
                WHERE token_id = @token_id
                  AND line_id = @line_id
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "token_id",
            NpgsqlDbType.Uuid,
            tokenId);
        command.Parameters.AddWithValue(
            "line_id",
            NpgsqlDbType.Uuid,
            lineId);

        return (bool)(await command.ExecuteScalarAsync(cancellationToken)
            ?? false);
    }

    private static async Task<bool> HasExerciseProvenanceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid exerciseRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM editorial.provenance_record
                WHERE object_type = 'EXERCISE_REVISION'
                  AND object_id = @revision_id
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "revision_id",
            NpgsqlDbType.Uuid,
            exerciseRevisionId);

        return (bool)(await command.ExecuteScalarAsync(cancellationToken)
            ?? false);
    }

    private static async Task<BasicRevision> ReadBasicRevisionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string sql,
        Guid recordingId,
        Guid revisionId,
        CancellationToken cancellationToken)
    {
        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);
        command.Parameters.AddWithValue(
            "revision_id",
            NpgsqlDbType.Uuid,
            revisionId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.component.not-found",
                "La revisión solicitada no pertenece a esta grabación.");
        }

        return new BasicRevision(
            reader.GetInt32(0),
            reader.GetString(1),
            (byte[])reader.GetValue(2));
    }

    private static async Task<SourcedRevision> ReadSourcedRevisionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string sql,
        Guid recordingId,
        Guid revisionId,
        CancellationToken cancellationToken)
    {
        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);
        command.Parameters.AddWithValue(
            "revision_id",
            NpgsqlDbType.Uuid,
            revisionId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.component.not-found",
                "La revisión solicitada no pertenece a esta grabación.");
        }

        return new SourcedRevision(
            reader.GetInt32(0),
            reader.GetString(1),
            (byte[])reader.GetValue(2),
            reader.GetGuid(3));
    }

    private static async Task<PackageHeader?> ReadDraftHeaderAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                package_id,
                package_no,
                status_code,
                frozen_at,
                checksum,
                version
            FROM editorial.editorial_package
            WHERE recording_id = @recording_id
              AND status_code = 'DRAFT'
              AND frozen_at IS NULL
            ORDER BY package_no DESC, package_id DESC;
            """;

        var rows = new List<PackageHeader>();

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(
                new PackageHeader(
                    reader.GetGuid(0),
                    reader.GetInt32(1),
                    reader.GetString(2),
                    reader.IsDBNull(3)
                        ? null
                        : reader.GetDateTime(3),
                    (byte[])reader.GetValue(4),
                    reader.GetInt64(5)));
        }

        if (rows.Count > 1)
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.multiple-drafts",
                "Existe más de un paquete DRAFT abierto para esta grabación; resuelve el conflicto antes de continuar.");
        }

        return rows.SingleOrDefault();
    }

    private static async Task<IReadOnlyList<ComponentReference>> ReadSelectedComponentsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid packageId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                component_kind,
                COALESCE(
                    lyrics_revision_id,
                    timing_revision_id,
                    translation_revision_id,
                    analysis_revision_id,
                    exercise_revision_id
                ),
                CASE component_kind
                    WHEN 'LYRICS' THEN lyrics_revision_id
                    WHEN 'TIMING' THEN (
                        SELECT lyrics_revision_id
                        FROM content.timing_revision
                        WHERE timing_revision_id = pc.timing_revision_id
                    )
                    WHEN 'TRANSLATION' THEN (
                        SELECT lyrics_revision_id
                        FROM content.translation_revision
                        WHERE translation_revision_id = pc.translation_revision_id
                    )
                    WHEN 'ANALYSIS' THEN (
                        SELECT lyrics_revision_id
                        FROM content.linguistic_analysis_revision
                        WHERE analysis_revision_id = pc.analysis_revision_id
                    )
                    WHEN 'EXERCISE' THEN (
                        SELECT s.lyrics_revision_id
                        FROM learning.exercise_revision er
                        JOIN learning.exercise_definition ed
                          ON ed.exercise_id = er.exercise_id
                        JOIN content.lyric_line l
                          ON l.line_id = ed.line_id
                        JOIN content.lyric_section s
                          ON s.section_id = l.section_id
                        WHERE er.exercise_revision_id = pc.exercise_revision_id
                    )
                END,
                checksum
            FROM editorial.package_component pc
            WHERE package_id = @package_id
            ORDER BY component_kind, package_component_id;
            """;

        var results = new List<ComponentReference>();

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "package_id",
            NpgsqlDbType.Uuid,
            packageId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            if (reader.IsDBNull(1) || reader.IsDBNull(2))
            {
                throw new CompatibleEducationalPackageException(
                    "editorial.package.broken-link",
                    "El paquete conserva una referencia rota.");
            }

            results.Add(
                new ComponentReference(
                    reader.GetString(0),
                    reader.GetGuid(1),
                    reader.GetGuid(2),
                    (byte[])reader.GetValue(3)));
        }

        return results;
    }

    private static async Task<PackageHeader> InsertPackageAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid recordingId,
        byte[] checksum,
        CancellationToken cancellationToken)
    {
        const string nextNoSql = """
            SELECT COALESCE(MAX(package_no), 0) + 1
            FROM editorial.editorial_package
            WHERE recording_id = @recording_id;
            """;

        int packageNo;
        await using (var command =
                     new NpgsqlCommand(
                         nextNoSql,
                         connection,
                         transaction))
        {
            command.Parameters.AddWithValue(
                "recording_id",
                NpgsqlDbType.Uuid,
                recordingId);
            packageNo = Convert.ToInt32(
                await command.ExecuteScalarAsync(cancellationToken)
                ?? 1,
                System.Globalization.CultureInfo.InvariantCulture);
        }

        const string insertSql = """
            INSERT INTO editorial.editorial_package (
                recording_id,
                package_no,
                status_code,
                created_by,
                frozen_at,
                checksum,
                version
            )
            VALUES (
                @recording_id,
                @package_no,
                'DRAFT',
                @actor_id,
                NULL,
                @checksum,
                1
            )
            RETURNING
                package_id,
                package_no,
                status_code,
                frozen_at,
                checksum,
                version;
            """;

        await using var insert =
            new NpgsqlCommand(insertSql, connection, transaction);
        insert.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);
        insert.Parameters.AddWithValue(
            "package_no",
            NpgsqlDbType.Integer,
            packageNo);
        insert.Parameters.AddWithValue(
            "actor_id",
            NpgsqlDbType.Uuid,
            actorAccountId);
        insert.Parameters.AddWithValue(
            "checksum",
            NpgsqlDbType.Bytea,
            checksum);

        await using var reader =
            await insert.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "No se pudo crear el paquete DRAFT.");
        }

        return new PackageHeader(
            reader.GetGuid(0),
            reader.GetInt32(1),
            reader.GetString(2),
            reader.IsDBNull(3) ? null : reader.GetDateTime(3),
            (byte[])reader.GetValue(4),
            reader.GetInt64(5));
    }

    private static async Task ReplaceComponentsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid packageId,
        IReadOnlyList<ComponentReference> components,
        CancellationToken cancellationToken)
    {
        const string deleteSql = """
            DELETE FROM editorial.package_component
            WHERE package_id = @package_id;
            """;

        await using (var delete =
                     new NpgsqlCommand(
                         deleteSql,
                         connection,
                         transaction))
        {
            delete.Parameters.AddWithValue(
                "package_id",
                NpgsqlDbType.Uuid,
                packageId);
            await delete.ExecuteNonQueryAsync(cancellationToken);
        }

        foreach (var component in components
                     .OrderBy(component => component.ComponentKind, StringComparer.Ordinal)
                     .ThenBy(component => component.RevisionId))
        {
            const string insertSql = """
                INSERT INTO editorial.package_component (
                    package_id,
                    component_kind,
                    lyrics_revision_id,
                    timing_revision_id,
                    translation_revision_id,
                    analysis_revision_id,
                    exercise_revision_id,
                    checksum
                )
                VALUES (
                    @package_id,
                    @component_kind,
                    @lyrics_revision_id,
                    @timing_revision_id,
                    @translation_revision_id,
                    @analysis_revision_id,
                    @exercise_revision_id,
                    @checksum
                );
                """;

            await using var insert =
                new NpgsqlCommand(
                    insertSql,
                    connection,
                    transaction);

            insert.Parameters.AddWithValue(
                "package_id",
                NpgsqlDbType.Uuid,
                packageId);
            insert.Parameters.AddWithValue(
                "component_kind",
                component.ComponentKind);
            AddNullableGuid(
                insert,
                "lyrics_revision_id",
                component.ComponentKind == "LYRICS"
                    ? component.RevisionId
                    : null);
            AddNullableGuid(
                insert,
                "timing_revision_id",
                component.ComponentKind == "TIMING"
                    ? component.RevisionId
                    : null);
            AddNullableGuid(
                insert,
                "translation_revision_id",
                component.ComponentKind == "TRANSLATION"
                    ? component.RevisionId
                    : null);
            AddNullableGuid(
                insert,
                "analysis_revision_id",
                component.ComponentKind == "ANALYSIS"
                    ? component.RevisionId
                    : null);
            AddNullableGuid(
                insert,
                "exercise_revision_id",
                component.ComponentKind == "EXERCISE"
                    ? component.RevisionId
                    : null);
            insert.Parameters.AddWithValue(
                "checksum",
                NpgsqlDbType.Bytea,
                component.Checksum);

            await insert.ExecuteNonQueryAsync(cancellationToken);
        }
    }

    private static async Task UpdatePackageChecksumAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid packageId,
        byte[] checksum,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE editorial.editorial_package
            SET checksum = @checksum
            WHERE package_id = @package_id
              AND status_code = 'DRAFT'
              AND frozen_at IS NULL;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "checksum",
            NpgsqlDbType.Bytea,
            checksum);
        command.Parameters.AddWithValue(
            "package_id",
            NpgsqlDbType.Uuid,
            packageId);

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.not-mutable",
                "El paquete dejó de ser DRAFT y no puede modificarse.");
        }
    }

    private static async Task<bool> ComponentsMatchAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid packageId,
        IReadOnlyList<ComponentReference> expected,
        CancellationToken cancellationToken)
    {
        var actual = await ReadSelectedComponentsAsync(
            connection,
            transaction,
            packageId,
            cancellationToken);

        static string Key(ComponentReference component) =>
            $"{component.ComponentKind}|{component.RevisionId:N}|{Convert.ToHexString(component.Checksum)}";

        return actual.Select(Key)
            .OrderBy(value => value, StringComparer.Ordinal)
            .SequenceEqual(
                expected.Select(Key)
                    .OrderBy(value => value, StringComparer.Ordinal),
                StringComparer.Ordinal);
    }

    private static bool PackageChecksumMatchesCurrentSources(
        Guid recordingId,
        long catalogVersion,
        byte[] storedPackageChecksum,
        IReadOnlyList<ComponentReference> selected,
        IReadOnlyList<CompatiblePackageCandidate> candidates)
    {
        if (selected.Count == 0)
        {
            return false;
        }

        var current = new List<ComponentReference>(selected.Count);

        foreach (var component in selected)
        {
            var candidate = candidates.SingleOrDefault(candidate =>
                candidate.ComponentKind == component.ComponentKind
                && candidate.RevisionId == component.RevisionId);

            if (candidate is null)
            {
                return false;
            }

            byte[] checksum;
            try
            {
                checksum = Convert.FromHexString(candidate.ChecksumSha256);
            }
            catch (FormatException)
            {
                return false;
            }

            current.Add(
                component with
                {
                    Checksum = checksum,
                    SourceLyricsRevisionId = candidate.SourceLyricsRevisionId
                });
        }

        var currentPackageChecksum = BuildPackageChecksum(
            recordingId,
            catalogVersion,
            current);

        return storedPackageChecksum.AsSpan()
            .SequenceEqual(currentPackageChecksum);
    }

    private static byte[] BuildPackageChecksum(
        Guid recordingId,
        long catalogVersion,
        IReadOnlyList<ComponentReference> components)
    {
        var material = new StringBuilder();
        material.Append(recordingId.ToString("N"));
        material.Append("|catalog-v");
        material.Append(
            catalogVersion.ToString(
                System.Globalization.CultureInfo.InvariantCulture));

        foreach (var component in components
                     .OrderBy(component => component.ComponentKind, StringComparer.Ordinal)
                     .ThenBy(component => component.RevisionId))
        {
            material.Append('\n');
            material.Append(component.ComponentKind);
            material.Append('|');
            material.Append(component.RevisionId.ToString("N"));
            material.Append('|');
            material.Append(
                Convert.ToHexString(component.Checksum).ToLowerInvariant());
        }

        return SHA256.HashData(
            Encoding.UTF8.GetBytes(material.ToString()));
    }

    private static async Task<bool> HasActiveRightsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM editorial.rights_record r
                WHERE r.object_type = 'RECORDING'
                  AND r.object_id = @recording_id
                  AND r.status_code = 'ACTIVE'
                  AND (r.valid_from IS NULL OR r.valid_from <= CURRENT_TIMESTAMP)
                  AND (r.valid_to IS NULL OR r.valid_to > CURRENT_TIMESTAMP)
                  AND EXISTS (
                      SELECT 1
                      FROM editorial.rights_scope s
                      WHERE s.rights_record_id = r.rights_record_id
                  )
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        return (bool)(await command.ExecuteScalarAsync(cancellationToken)
            ?? false);
    }

    private static async Task<long> ReadRecordingVersionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT version
            FROM catalog.recording
            WHERE recording_id = @recording_id;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        var value = await command.ExecuteScalarAsync(cancellationToken);

        if (value is not long version || version <= 0)
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.recording.not-found",
                "La canción editorial solicitada no existe.");
        }

        return version;
    }

    private static async Task AcquireRecordingLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql =
            "SELECT pg_advisory_xact_lock(hashtextextended(@key, 0));";

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "key",
            $"EDITORIAL-PACKAGE:{recordingId:D}");

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static void EnsureMutable(PackageHeader header)
    {
        if (!string.Equals(
                header.StatusCode,
                "DRAFT",
                StringComparison.Ordinal)
            || header.FrozenAt is not null)
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.not-mutable",
                "El paquete ya no es DRAFT; BL-MVP-048/049 controlan su estado posterior.");
        }
    }

    private static async Task WriteAuditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid packageId,
        byte[] beforeDigest,
        byte[] afterDigest,
        string reason,
        string correlationId,
        CancellationToken cancellationToken)
    {
        var roleCode = await ReadAuditRoleCodeAsync(
            connection,
            transaction,
            actorAccountId,
            cancellationToken);

        const string sql = """
            INSERT INTO security.audit_event (
                actor_id,
                role_code,
                object_type,
                object_id,
                action_code,
                before_digest,
                after_digest,
                reason,
                occurred_at,
                correlation_id
            )
            VALUES (
                @actor_id,
                @role_code,
                'EDITORIAL_PACKAGE',
                @package_id,
                'EDITORIAL.PACKAGE.ASSEMBLE',
                @before_digest,
                @after_digest,
                @reason,
                CURRENT_TIMESTAMP,
                @correlation_id
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "actor_id",
            NpgsqlDbType.Uuid,
            actorAccountId);
        command.Parameters.AddWithValue(
            "role_code",
            roleCode);
        command.Parameters.AddWithValue(
            "package_id",
            NpgsqlDbType.Uuid,
            packageId);
        command.Parameters.AddWithValue(
            "before_digest",
            NpgsqlDbType.Bytea,
            beforeDigest);
        command.Parameters.AddWithValue(
            "after_digest",
            NpgsqlDbType.Bytea,
            afterDigest);
        command.Parameters.AddWithValue(
            "reason",
            reason);
        command.Parameters.AddWithValue(
            "correlation_id",
            NpgsqlDbType.Uuid,
            CorrelationGuid(correlationId));

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<string> ReadAuditRoleCodeAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT r.role_code
            FROM security.role_assignment a
            JOIN security.role r
              ON r.role_id = a.role_id
            JOIN security.role_permission rp
              ON rp.role_id = r.role_id
            JOIN security.permission p
              ON p.permission_id = rp.permission_id
            WHERE a.account_id = @actor_id
              AND p.permission_code IN ('EDITORIAL.SUBMIT', 'EDITORIAL.REVIEW')
              AND r.status_code = 'ACTIVE'
              AND a.valid_from <= CURRENT_TIMESTAMP
              AND (a.valid_to IS NULL OR a.valid_to > CURRENT_TIMESTAMP)
              AND rp.valid_from <= CURRENT_TIMESTAMP
              AND (rp.valid_to IS NULL OR rp.valid_to > CURRENT_TIMESTAMP)
            ORDER BY CASE p.permission_code
                WHEN 'EDITORIAL.SUBMIT' THEN 0
                ELSE 1
            END, r.role_code
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "actor_id",
            NpgsqlDbType.Uuid,
            actorAccountId);

        var value =
            await command.ExecuteScalarAsync(cancellationToken);

        if (value is not string roleCode
            || string.IsNullOrWhiteSpace(roleCode))
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.audit-role.missing",
                "No se pudo resolver un rol vigente de sometimiento o revisión.");
        }

        return roleCode;
    }

    private static Guid CorrelationGuid(string correlationId)
    {
        if (Guid.TryParse(correlationId, out var parsed)
            && parsed != Guid.Empty)
        {
            return parsed;
        }

        var digest = SHA256.HashData(
            Encoding.UTF8.GetBytes(correlationId));

        Span<byte> bytes = stackalloc byte[16];
        digest.AsSpan(0, 16).CopyTo(bytes);
        return new Guid(bytes);
    }

    private static void AddNullableGuid(
        NpgsqlCommand command,
        string name,
        Guid? value)
    {
        command.Parameters.Add(
            new NpgsqlParameter(name, NpgsqlDbType.Uuid)
            {
                Value = value.HasValue
                    ? (object)value.Value
                    : DBNull.Value
            });
    }

    private static string NormalizeReason(string? value)
    {
        var normalized = value?.Trim();

        if (string.IsNullOrWhiteSpace(normalized))
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.reason.required",
                "Indica por qué estas revisiones forman el paquete.");
        }

        if (normalized.Length > 1000)
        {
            throw new CompatibleEducationalPackageException(
                "editorial.package.reason.too-long",
                "El motivo no puede superar 1000 caracteres.");
        }

        return normalized;
    }

    private static string? JsonStringValue(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            return document.RootElement.ValueKind == JsonValueKind.String
                ? document.RootElement.GetString()
                : document.RootElement.GetRawText();
        }
        catch (JsonException)
        {
            return json;
        }
    }

    private static string NormalizeOption(string value) =>
        string.Join(
            " ",
            value.Normalize(NormalizationForm.FormKC)
                .Trim()
                .ToLowerInvariant()
                .Split(
                    (char[]?)null,
                    StringSplitOptions.RemoveEmptyEntries));

    private static void ValidateIdentity(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId)
    {
        if (actorAccountId == Guid.Empty)
        {
            throw new ArgumentException(
                "El actor es obligatorio.",
                nameof(actorAccountId));
        }

        if (recordingId == Guid.Empty)
        {
            throw new ArgumentException(
                "La grabación es obligatoria.",
                nameof(recordingId));
        }

        if (string.IsNullOrWhiteSpace(correlationId))
        {
            throw new ArgumentException(
                "La correlación es obligatoria.",
                nameof(correlationId));
        }
    }

    private sealed record PackageHeader(
        Guid PackageId,
        int PackageNo,
        string StatusCode,
        DateTime? FrozenAt,
        byte[] Checksum,
        long Version);

    private sealed record ComponentReference(
        string ComponentKind,
        Guid RevisionId,
        Guid SourceLyricsRevisionId,
        byte[] Checksum);

    private sealed record BasicRevision(
        int RevisionNo,
        string StatusCode,
        byte[] Checksum);

    private sealed record SourcedRevision(
        int RevisionNo,
        string StatusCode,
        byte[] Checksum,
        Guid SourceLyricsRevisionId);

    private sealed record PreparedSelection(
        IReadOnlyList<ComponentReference> Components,
        bool HasActiveRights);

    private sealed record ExerciseHeader(
        Guid ExerciseRevisionId,
        int RevisionNo,
        string StatusCode,
        string ChecksumSha256,
        string Prompt,
        string SolutionSpecJson,
        string ExerciseType,
        Guid? LineId,
        Guid? SourceLyricsRevisionId,
        int? LineNo,
        string? JapaneseText);

    private sealed record ExerciseItemRow(
        string ItemType,
        int ItemOrder,
        string Value,
        string? Role,
        Guid? SourceTokenId);
}
