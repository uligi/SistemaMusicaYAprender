using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Content.Infrastructure.Administration;

public sealed record TimingTokenDraft(
    Guid TokenId,
    long StartMs,
    long EndMs);

public sealed record TimingLineDraft(
    Guid LineId,
    long? StartMs,
    long? EndMs,
    List<TimingTokenDraft> Tokens);

public sealed record CreateTimingRevisionInput(
    Guid LyricsRevisionId,
    Guid SourceId,
    long OffsetMs,
    int? ExpectedRevisionNo,
    List<TimingLineDraft> Lines);

public sealed record TimingTokenSnapshot(
    Guid TokenId,
    int TokenNo,
    string Surface,
    long StartMs,
    long EndMs);

public sealed record TimingLineSnapshot(
    Guid LineId,
    int SectionOrder,
    int LineNo,
    string JapaneseText,
    string? SpeakerLabel,
    string PrecisionCode,
    long StartMs,
    long EndMs,
    List<TimingTokenSnapshot> Tokens);

public sealed record TimingRevisionSnapshot(
    Guid TimingRevisionId,
    Guid LyricsRevisionId,
    Guid SourceId,
    int RevisionNo,
    long OffsetMs,
    string StatusCode,
    string ChecksumSha256,
    List<TimingLineSnapshot> Lines);

public sealed record SynchronizationSourceSnapshot(
    Guid SourceId,
    string ProviderCode,
    string ExternalRef,
    long? DurationMs,
    long SourceOffsetMs,
    string StatusCode,
    TimingRevisionSnapshot? TimingRevision);

public sealed record SynchronizationContextSnapshot(
    Guid RecordingId,
    Guid? LyricsRevisionId,
    int? LyricsRevisionNo,
    List<SynchronizationSourceSnapshot> Sources);

public sealed class TimingAdministrationException(
    string code,
    string message)
    : InvalidOperationException(message)
{
    public string Code { get; } = code;
}

public sealed class TimingRevisionAdministrationService(
    ITimingAdministrationTransactionExecutor transactionExecutor)
{
    public Task<SynchronizationContextSnapshot> ReadContextAsync(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentity(
            actorAccountId,
            recordingId,
            correlationId);

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                ReadContextCoreAsync(
                    connection,
                    transaction,
                    recordingId,
                    token),
            cancellationToken);
    }

    public Task<TimingRevisionSnapshot> CreateRevisionAsync(
        Guid actorAccountId,
        Guid recordingId,
        CreateTimingRevisionInput input,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(input);
        ValidateIdentity(
            actorAccountId,
            recordingId,
            correlationId);

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                CreateRevisionCoreAsync(
                    connection,
                    transaction,
                    recordingId,
                    input,
                    token),
            cancellationToken);
    }

    private static async Task<SynchronizationContextSnapshot> ReadContextCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        await AssertRecordingExistsAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        var lyrics =
            await ReadLatestLyricsRevisionAsync(
                connection,
                transaction,
                recordingId,
                cancellationToken);

        var sources =
            await ReadSourcesAsync(
                connection,
                transaction,
                recordingId,
                cancellationToken);

        var snapshots =
            new List<SynchronizationSourceSnapshot>(
                sources.Count);

        foreach (var source in sources)
        {
            TimingRevisionSnapshot? timingRevision = null;

            if (lyrics is not null)
            {
                timingRevision =
                    await ReadLatestTimingRevisionAsync(
                        connection,
                        transaction,
                        lyrics.LyricsRevisionId,
                        source.SourceId,
                        cancellationToken);
            }

            snapshots.Add(
                new SynchronizationSourceSnapshot(
                    source.SourceId,
                    source.ProviderCode,
                    source.ExternalRef,
                    source.DurationMs,
                    source.OffsetMs,
                    source.StatusCode,
                    timingRevision));
        }

        return new SynchronizationContextSnapshot(
            recordingId,
            lyrics?.LyricsRevisionId,
            lyrics?.RevisionNo,
            snapshots);
    }

    private static async Task<TimingRevisionSnapshot> CreateRevisionCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CreateTimingRevisionInput input,
        CancellationToken cancellationToken)
    {
        if (input.LyricsRevisionId == Guid.Empty)
        {
            throw new TimingAdministrationException(
                "content.timing.lyrics-revision.invalid",
                "La revisión de letra no es válida.");
        }

        if (input.SourceId == Guid.Empty)
        {
            throw new TimingAdministrationException(
                "content.timing.source.invalid",
                "La fuente multimedia no es válida.");
        }

        if (input.Lines.Count == 0)
        {
            throw new TimingAdministrationException(
                "content.timing.lines.required",
                "La revisión de sincronización necesita al menos una línea temporizada.");
        }

        var lyrics =
            await ReadLyricsRevisionForRecordingAsync(
                connection,
                transaction,
                recordingId,
                input.LyricsRevisionId,
                cancellationToken);

        var source =
            await ReadSourceForRecordingAsync(
                connection,
                transaction,
                recordingId,
                input.SourceId,
                cancellationToken);

        if (source.DurationMs is null)
        {
            throw new TimingAdministrationException(
                "content.timing.source-duration.required",
                "La duración exacta de la fuente debe estar confirmada antes de validar tiempos.");
        }

        await AcquireTimingLockAsync(
            connection,
            transaction,
            input.LyricsRevisionId,
            input.SourceId,
            cancellationToken);

        var prepared =
            await PrepareAsync(
                connection,
                transaction,
                lyrics,
                source,
                input,
                cancellationToken);

        var latest =
            await ReadLatestTimingRevisionAsync(
                connection,
                transaction,
                input.LyricsRevisionId,
                input.SourceId,
                cancellationToken);

        if (latest is not null
            && string.Equals(
                latest.ChecksumSha256,
                prepared.ChecksumSha256,
                StringComparison.OrdinalIgnoreCase))
        {
            return latest;
        }

        if ((latest?.RevisionNo) != input.ExpectedRevisionNo)
        {
            throw new TimingAdministrationException(
                "content.timing.revision.conflict",
                "La sincronización cambió en el servidor desde que abriste este borrador. Conserva tus cambios y compara antes de volver a guardar.");
        }

        var revisionId = Guid.CreateVersion7();
        var revisionNo = (latest?.RevisionNo ?? 0) + 1;

        const string insertRevision = """
            INSERT INTO content.timing_revision (
                timing_revision_id,
                lyrics_revision_id,
                source_id,
                revision_no,
                offset_ms,
                status_code,
                checksum
            )
            VALUES (
                @timing_revision_id,
                @lyrics_revision_id,
                @source_id,
                @revision_no,
                @offset_ms,
                'DRAFT',
                @checksum
            );
            """;

        await using (var command =
                     new NpgsqlCommand(
                         insertRevision,
                         connection,
                         transaction))
        {
            command.Parameters.AddWithValue(
                "timing_revision_id",
                NpgsqlDbType.Uuid,
                revisionId);
            command.Parameters.AddWithValue(
                "lyrics_revision_id",
                NpgsqlDbType.Uuid,
                input.LyricsRevisionId);
            command.Parameters.AddWithValue(
                "source_id",
                NpgsqlDbType.Uuid,
                input.SourceId);
            command.Parameters.AddWithValue(
                "revision_no",
                NpgsqlDbType.Integer,
                revisionNo);
            command.Parameters.AddWithValue(
                "offset_ms",
                NpgsqlDbType.Bigint,
                input.OffsetMs);
            command.Parameters.AddWithValue(
                "checksum",
                NpgsqlDbType.Bytea,
                prepared.Checksum);

            await command.ExecuteNonQueryAsync(
                cancellationToken);
        }

        var displayOrder = 0;

        foreach (var line in prepared.Lines)
        {
            foreach (var segment in line.Segments)
            {
                const string insertSegment = """
                    INSERT INTO content.timing_segment (
                        segment_id,
                        timing_revision_id,
                        line_id,
                        start_ms,
                        end_ms,
                        display_order
                    )
                    VALUES (
                        @segment_id,
                        @timing_revision_id,
                        @line_id,
                        @start_ms,
                        @end_ms,
                        @display_order
                    );
                    """;

                await using var command =
                    new NpgsqlCommand(
                        insertSegment,
                        connection,
                        transaction);

                command.Parameters.AddWithValue(
                    "segment_id",
                    NpgsqlDbType.Uuid,
                    Guid.CreateVersion7());
                command.Parameters.AddWithValue(
                    "timing_revision_id",
                    NpgsqlDbType.Uuid,
                    revisionId);
                command.Parameters.AddWithValue(
                    "line_id",
                    NpgsqlDbType.Uuid,
                    line.LineId);
                command.Parameters.AddWithValue(
                    "start_ms",
                    NpgsqlDbType.Bigint,
                    segment.StartMs);
                command.Parameters.AddWithValue(
                    "end_ms",
                    NpgsqlDbType.Bigint,
                    segment.EndMs);
                command.Parameters.AddWithValue(
                    "display_order",
                    NpgsqlDbType.Integer,
                    displayOrder);

                await command.ExecuteNonQueryAsync(
                    cancellationToken);

                displayOrder++;
            }
        }

        return await ReadTimingRevisionAsync(
                   connection,
                   transaction,
                   revisionId,
                   cancellationToken)
               ?? throw new InvalidOperationException(
                   "La revisión de sincronización recién creada no pudo releerse.");
    }

    private static async Task<PreparedTimingRevision> PrepareAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        LyricsRevisionRow lyrics,
        SourceRow source,
        CreateTimingRevisionInput input,
        CancellationToken cancellationToken)
    {
        var lineRows =
            await ReadLyricsLinesAsync(
                connection,
                transaction,
                lyrics.LyricsRevisionId,
                cancellationToken);

        var lineMap =
            lineRows.ToDictionary(
                static line => line.LineId);

        var seen =
            new HashSet<Guid>();

        var previousPosition = -1;
        var preparedLines =
            new List<PreparedTimingLine>(
                input.Lines.Count);

        foreach (var requested in input.Lines)
        {
            if (!lineMap.TryGetValue(
                    requested.LineId,
                    out var line))
            {
                throw new TimingAdministrationException(
                    "content.timing.line.not-found",
                    "Una línea temporizada no pertenece a la revisión de letra seleccionada.");
            }

            if (!seen.Add(
                    requested.LineId))
            {
                throw new TimingAdministrationException(
                    "content.timing.line.duplicate",
                    $"La línea {line.LineNo} aparece más de una vez en la revisión temporal.");
            }

            if (line.Position <= previousPosition)
            {
                throw new TimingAdministrationException(
                    "content.timing.line.order-invalid",
                    $"La línea {line.LineNo} no respeta el orden de la revisión de letra.");
            }

            previousPosition =
                line.Position;

            var tokens =
                await ReadLyricsTokensAsync(
                    connection,
                    transaction,
                    line.LineId,
                    cancellationToken);

            var prepared =
                PrepareLine(
                    line,
                    tokens,
                    requested,
                    source.DurationMs!.Value,
                    input.OffsetMs);

            preparedLines.Add(
                prepared);
        }

        ValidateOverlaps(
            preparedLines);

        var checksumSource =
            JsonSerializer.SerializeToUtf8Bytes(
                new
                {
                    input.LyricsRevisionId,
                    input.SourceId,
                    input.OffsetMs,
                    Lines =
                        preparedLines.Select(
                            static line => new
                            {
                                line.LineId,
                                line.PrecisionCode,
                                Segments =
                                    line.Segments.Select(
                                        static segment => new
                                        {
                                            segment.TokenId,
                                            segment.StartMs,
                                            segment.EndMs
                                        })
                            })
                });

        var checksum =
            SHA256.HashData(
                checksumSource);

        return new PreparedTimingRevision(
            preparedLines,
            checksum,
            Convert.ToHexString(
                    checksum)
                .ToLowerInvariant());
    }

    private static PreparedTimingLine PrepareLine(
        LyricsLineRow line,
        List<LyricsTokenRow> tokens,
        TimingLineDraft requested,
        long sourceDurationMs,
        long offsetMs)
    {
        if (requested.Tokens.Count > 0)
        {
            if (requested.StartMs is not null
                || requested.EndMs is not null)
            {
                throw new TimingAdministrationException(
                    "content.timing.precision.mixed",
                    $"La línea {line.LineNo} no puede mezclar intervalo de línea y tiempos por token.");
            }

            if (tokens.Count == 0)
            {
                throw new TimingAdministrationException(
                    "content.timing.tokens.unavailable",
                    $"La línea {line.LineNo} no tiene tokens canónicos para sincronización detallada.");
            }

            if (requested.Tokens.Count != tokens.Count)
            {
                throw new TimingAdministrationException(
                    "content.timing.tokens.coverage-invalid",
                    $"La línea {line.LineNo} debe temporizar todos sus tokens canónicos cuando usa precisión por token.");
            }

            var segments =
                new List<PreparedTimingSegment>(
                    tokens.Count);

            long? previousEnd = null;

            for (var index = 0;
                 index < tokens.Count;
                 index++)
            {
                var expected =
                    tokens[index];
                var supplied =
                    requested.Tokens[index];

                if (supplied.TokenId != expected.TokenId)
                {
                    throw new TimingAdministrationException(
                        "content.timing.token.order-invalid",
                        $"El token {index + 1} de la línea {line.LineNo} no coincide con el orden canónico.");
                }

                ValidateInterval(
                    supplied.StartMs,
                    supplied.EndMs,
                    sourceDurationMs,
                    offsetMs,
                    $"token {index + 1} de la línea {line.LineNo}");

                if (previousEnd is not null
                    && supplied.StartMs < previousEnd.Value)
                {
                    throw new TimingAdministrationException(
                        "content.timing.token.overlap-invalid",
                        $"El token {index + 1} de la línea {line.LineNo} se solapa con el token anterior.");
                }

                previousEnd =
                    supplied.EndMs;

                segments.Add(
                    new PreparedTimingSegment(
                        supplied.TokenId,
                        supplied.StartMs,
                        supplied.EndMs));
            }

            return new PreparedTimingLine(
                line.LineId,
                line.Position,
                line.LineNo,
                line.SpeakerLabel,
                "TOKEN",
                segments);
        }

        if (requested.StartMs is null
            || requested.EndMs is null)
        {
            throw new TimingAdministrationException(
                "content.timing.line.interval-required",
                $"La línea {line.LineNo} necesita inicio y fin, o una temporización completa por token.");
        }

        ValidateInterval(
            requested.StartMs.Value,
            requested.EndMs.Value,
            sourceDurationMs,
            offsetMs,
            $"línea {line.LineNo}");

        return new PreparedTimingLine(
            line.LineId,
            line.Position,
            line.LineNo,
            line.SpeakerLabel,
            "LINE",
            [
                new PreparedTimingSegment(
                    null,
                    requested.StartMs.Value,
                    requested.EndMs.Value)
            ]);
    }

    private static void ValidateInterval(
        long startMs,
        long endMs,
        long sourceDurationMs,
        long offsetMs,
        string label)
    {
        if (startMs < 0)
        {
            throw new TimingAdministrationException(
                "content.timing.segment.negative",
                $"El inicio de {label} no puede ser negativo.");
        }

        if (endMs <= startMs)
        {
            throw new TimingAdministrationException(
                "content.timing.segment.inverted",
                $"El fin de {label} debe ser posterior a su inicio.");
        }

        var effectiveStart =
            checked(startMs + offsetMs);
        var effectiveEnd =
            checked(endMs + offsetMs);

        if (effectiveStart < 0
            || effectiveEnd > sourceDurationMs)
        {
            throw new TimingAdministrationException(
                "content.timing.segment.out-of-range",
                $"{label} queda fuera de la duración confirmada de la fuente.");
        }
    }

    private static void ValidateOverlaps(
        List<PreparedTimingLine> lines)
    {
        for (var currentIndex = 1;
             currentIndex < lines.Count;
             currentIndex++)
        {
            var current =
                lines[currentIndex];

            for (var previousIndex = 0;
                 previousIndex < currentIndex;
                 previousIndex++)
            {
                var previous =
                    lines[previousIndex];

                if (current.StartMs >= previous.EndMs
                    || previous.StartMs >= current.EndMs)
                {
                    continue;
                }

                var justified =
                    !string.IsNullOrWhiteSpace(
                        previous.SpeakerLabel)
                    && !string.IsNullOrWhiteSpace(
                        current.SpeakerLabel)
                    && !string.Equals(
                        previous.SpeakerLabel,
                        current.SpeakerLabel,
                        StringComparison.Ordinal);

                if (!justified)
                {
                    throw new TimingAdministrationException(
                        "content.timing.segment.overlap-unjustified",
                        $"Las líneas {previous.LineNo} y {current.LineNo} se solapan sin voces simultáneas diferenciadas.");
                }
            }
        }
    }

    private static async Task<TimingRevisionSnapshot?> ReadLatestTimingRevisionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid lyricsRevisionId,
        Guid sourceId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT timing_revision_id
            FROM content.timing_revision
            WHERE lyrics_revision_id = @lyrics_revision_id
              AND source_id = @source_id
            ORDER BY revision_no DESC, timing_revision_id DESC
            LIMIT 1;
            """;

        Guid? revisionId = null;

        await using (var command =
                     new NpgsqlCommand(
                         sql,
                         connection,
                         transaction))
        {
            command.Parameters.AddWithValue(
                "lyrics_revision_id",
                NpgsqlDbType.Uuid,
                lyricsRevisionId);
            command.Parameters.AddWithValue(
                "source_id",
                NpgsqlDbType.Uuid,
                sourceId);

            var value =
                await command.ExecuteScalarAsync(
                    cancellationToken);

            if (value is Guid parsed)
            {
                revisionId = parsed;
            }
        }

        return revisionId is null
            ? null
            : await ReadTimingRevisionAsync(
                connection,
                transaction,
                revisionId.Value,
                cancellationToken);
    }

    private static async Task<TimingRevisionSnapshot?> ReadTimingRevisionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid timingRevisionId,
        CancellationToken cancellationToken)
    {
        const string revisionSql = """
            SELECT
                lyrics_revision_id,
                source_id,
                revision_no,
                offset_ms,
                status_code,
                encode(checksum, 'hex')
            FROM content.timing_revision
            WHERE timing_revision_id = @timing_revision_id;
            """;

        Guid lyricsRevisionId;
        Guid sourceId;
        int revisionNo;
        long offsetMs;
        string statusCode;
        string checksum;

        await using (var command =
                     new NpgsqlCommand(
                         revisionSql,
                         connection,
                         transaction))
        {
            command.Parameters.AddWithValue(
                "timing_revision_id",
                NpgsqlDbType.Uuid,
                timingRevisionId);

            await using var reader =
                await command.ExecuteReaderAsync(
                    cancellationToken);

            if (!await reader.ReadAsync(
                    cancellationToken))
            {
                return null;
            }

            lyricsRevisionId = reader.GetGuid(0);
            sourceId = reader.GetGuid(1);
            revisionNo = reader.GetInt32(2);
            offsetMs = reader.GetInt64(3);
            statusCode = reader.GetString(4);
            checksum = reader.GetString(5);
        }

        var lineRows =
            await ReadLyricsLinesAsync(
                connection,
                transaction,
                lyricsRevisionId,
                cancellationToken);

        var segmentRows =
            await ReadTimingSegmentsAsync(
                connection,
                transaction,
                timingRevisionId,
                cancellationToken);

        var lines =
            new List<TimingLineSnapshot>();

        foreach (var line in lineRows)
        {
            var segments =
                segmentRows
                    .Where(
                        segment => segment.LineId == line.LineId)
                    .OrderBy(
                        static segment => segment.DisplayOrder)
                    .ToList();

            if (segments.Count == 0)
            {
                continue;
            }

            var tokens =
                await ReadLyricsTokensAsync(
                    connection,
                    transaction,
                    line.LineId,
                    cancellationToken);

            var isTokenPrecision =
                tokens.Count > 1
                && segments.Count == tokens.Count;

            var tokenSnapshots =
                new List<TimingTokenSnapshot>();

            if (isTokenPrecision)
            {
                for (var index = 0;
                     index < tokens.Count;
                     index++)
                {
                    var token =
                        tokens[index];
                    var segment =
                        segments[index];

                    tokenSnapshots.Add(
                        new TimingTokenSnapshot(
                            token.TokenId,
                            token.TokenNo,
                            token.Surface,
                            segment.StartMs,
                            segment.EndMs));
                }
            }

            lines.Add(
                new TimingLineSnapshot(
                    line.LineId,
                    line.SectionOrder,
                    line.LineNo,
                    line.JapaneseText,
                    line.SpeakerLabel,
                    isTokenPrecision
                        ? "TOKEN"
                        : "LINE",
                    segments.Min(
                        static segment => segment.StartMs),
                    segments.Max(
                        static segment => segment.EndMs),
                    tokenSnapshots));
        }

        return new TimingRevisionSnapshot(
            timingRevisionId,
            lyricsRevisionId,
            sourceId,
            revisionNo,
            offsetMs,
            statusCode,
            checksum,
            lines);
    }

    private static async Task<List<TimingSegmentRow>> ReadTimingSegmentsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid timingRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                line_id,
                start_ms,
                end_ms,
                display_order
            FROM content.timing_segment
            WHERE timing_revision_id = @timing_revision_id
            ORDER BY display_order, segment_id;
            """;

        var result =
            new List<TimingSegmentRow>();

        await using var command =
            new NpgsqlCommand(
                sql,
                connection,
                transaction);

        command.Parameters.AddWithValue(
            "timing_revision_id",
            NpgsqlDbType.Uuid,
            timingRevisionId);

        await using var reader =
            await command.ExecuteReaderAsync(
                cancellationToken);

        while (await reader.ReadAsync(
                   cancellationToken))
        {
            result.Add(
                new TimingSegmentRow(
                    reader.GetGuid(0),
                    reader.GetInt64(1),
                    reader.GetInt64(2),
                    reader.GetInt32(3)));
        }

        return result;
    }

    private static async Task<LyricsRevisionRow?> ReadLatestLyricsRevisionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                lyrics_revision_id,
                revision_no
            FROM content.lyrics_revision
            WHERE recording_id = @recording_id
            ORDER BY revision_no DESC, lyrics_revision_id DESC
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(
                sql,
                connection,
                transaction);

        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(
                cancellationToken);

        return await reader.ReadAsync(
            cancellationToken)
            ? new LyricsRevisionRow(
                reader.GetGuid(0),
                reader.GetInt32(1))
            : null;
    }

    private static async Task<LyricsRevisionRow> ReadLyricsRevisionForRecordingAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid lyricsRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT revision_no
            FROM content.lyrics_revision
            WHERE lyrics_revision_id = @lyrics_revision_id
              AND recording_id = @recording_id;
            """;

        await using var command =
            new NpgsqlCommand(
                sql,
                connection,
                transaction);

        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        var value =
            await command.ExecuteScalarAsync(
                cancellationToken);

        if (value is not int revisionNo)
        {
            throw new TimingAdministrationException(
                "content.timing.lyrics-revision.not-found",
                "La revisión de letra no pertenece a la grabación seleccionada.");
        }

        return new LyricsRevisionRow(
            lyricsRevisionId,
            revisionNo);
    }

    private static async Task<List<SourceRow>> ReadSourcesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                source_id,
                provider_code,
                external_ref,
                duration_ms,
                offset_ms,
                status_code
            FROM catalog.recording_source
            WHERE recording_id = @recording_id
            ORDER BY provider_code, external_ref, source_id;
            """;

        var result =
            new List<SourceRow>();

        await using var command =
            new NpgsqlCommand(
                sql,
                connection,
                transaction);

        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(
                cancellationToken);

        while (await reader.ReadAsync(
                   cancellationToken))
        {
            result.Add(
                new SourceRow(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.IsDBNull(3)
                        ? null
                        : reader.GetInt64(3),
                    reader.GetInt64(4),
                    reader.GetString(5)));
        }

        return result;
    }

    private static async Task<SourceRow> ReadSourceForRecordingAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid sourceId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                provider_code,
                external_ref,
                duration_ms,
                offset_ms,
                status_code
            FROM catalog.recording_source
            WHERE source_id = @source_id
              AND recording_id = @recording_id;
            """;

        await using var command =
            new NpgsqlCommand(
                sql,
                connection,
                transaction);

        command.Parameters.AddWithValue(
            "source_id",
            NpgsqlDbType.Uuid,
            sourceId);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(
                cancellationToken);

        if (!await reader.ReadAsync(
                cancellationToken))
        {
            throw new TimingAdministrationException(
                "content.timing.source.not-found",
                "La fuente no pertenece a la grabación seleccionada.");
        }

        return new SourceRow(
            sourceId,
            reader.GetString(0),
            reader.GetString(1),
            reader.IsDBNull(2)
                ? null
                : reader.GetInt64(2),
            reader.GetInt64(3),
            reader.GetString(4));
    }

    private static async Task<List<LyricsLineRow>> ReadLyricsLinesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid lyricsRevisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                line.line_id,
                section.display_order,
                line.line_no,
                line.japanese_text,
                line.speaker_label
            FROM content.lyric_section AS section
            INNER JOIN content.lyric_line AS line
                ON line.section_id = section.section_id
            WHERE section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY
                section.display_order,
                line.line_no,
                line.line_id;
            """;

        var result =
            new List<LyricsLineRow>();
        var position = 0;

        await using var command =
            new NpgsqlCommand(
                sql,
                connection,
                transaction);

        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);

        await using var reader =
            await command.ExecuteReaderAsync(
                cancellationToken);

        while (await reader.ReadAsync(
                   cancellationToken))
        {
            result.Add(
                new LyricsLineRow(
                    reader.GetGuid(0),
                    reader.GetInt32(1),
                    reader.GetInt32(2),
                    reader.GetString(3),
                    reader.IsDBNull(4)
                        ? null
                        : reader.GetString(4),
                    position));

            position++;
        }

        return result;
    }

    private static async Task<List<LyricsTokenRow>> ReadLyricsTokensAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid lineId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                token_id,
                token_no,
                surface
            FROM content.lyric_token
            WHERE line_id = @line_id
            ORDER BY token_no, token_id;
            """;

        var result =
            new List<LyricsTokenRow>();

        await using var command =
            new NpgsqlCommand(
                sql,
                connection,
                transaction);

        command.Parameters.AddWithValue(
            "line_id",
            NpgsqlDbType.Uuid,
            lineId);

        await using var reader =
            await command.ExecuteReaderAsync(
                cancellationToken);

        while (await reader.ReadAsync(
                   cancellationToken))
        {
            result.Add(
                new LyricsTokenRow(
                    reader.GetGuid(0),
                    reader.GetInt32(1),
                    reader.GetString(2)));
        }

        return result;
    }

    private static async Task AssertRecordingExistsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM catalog.recording
                WHERE recording_id = @recording_id
            );
            """;

        await using var command =
            new NpgsqlCommand(
                sql,
                connection,
                transaction);

        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        var exists =
            await command.ExecuteScalarAsync(
                cancellationToken);

        if (exists is not true)
        {
            throw new TimingAdministrationException(
                "content.timing.recording.not-found",
                "La grabación indicada no existe.");
        }
    }

    private static async Task AcquireTimingLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid lyricsRevisionId,
        Guid sourceId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT pg_advisory_xact_lock(
                hashtextextended(
                    CAST(@lyrics_revision_id AS text)
                    || ':'
                    || CAST(@source_id AS text),
                    56
                )
            );
            """;

        await using var command =
            new NpgsqlCommand(
                sql,
                connection,
                transaction);

        command.Parameters.AddWithValue(
            "lyrics_revision_id",
            NpgsqlDbType.Uuid,
            lyricsRevisionId);
        command.Parameters.AddWithValue(
            "source_id",
            NpgsqlDbType.Uuid,
            sourceId);

        await command.ExecuteNonQueryAsync(
            cancellationToken);
    }

    private static void ValidateIdentity(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId)
    {
        if (actorAccountId == Guid.Empty)
        {
            throw new ArgumentException(
                "ActorAccountId no puede ser Guid.Empty.",
                nameof(actorAccountId));
        }

        if (recordingId == Guid.Empty)
        {
            throw new TimingAdministrationException(
                "content.timing.recording.invalid",
                "La grabación solicitada no es válida.");
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(
            correlationId);
    }

    private sealed record LyricsRevisionRow(
        Guid LyricsRevisionId,
        int RevisionNo);

    private sealed record SourceRow(
        Guid SourceId,
        string ProviderCode,
        string ExternalRef,
        long? DurationMs,
        long OffsetMs,
        string StatusCode);

    private sealed record LyricsLineRow(
        Guid LineId,
        int SectionOrder,
        int LineNo,
        string JapaneseText,
        string? SpeakerLabel,
        int Position);

    private sealed record LyricsTokenRow(
        Guid TokenId,
        int TokenNo,
        string Surface);

    private sealed record TimingSegmentRow(
        Guid LineId,
        long StartMs,
        long EndMs,
        int DisplayOrder);

    private sealed record PreparedTimingRevision(
        List<PreparedTimingLine> Lines,
        byte[] Checksum,
        string ChecksumSha256);

    private sealed record PreparedTimingLine(
        Guid LineId,
        int Position,
        int LineNo,
        string? SpeakerLabel,
        string PrecisionCode,
        List<PreparedTimingSegment> Segments)
    {
        public long StartMs =>
            Segments.Min(
                static segment => segment.StartMs);

        public long EndMs =>
            Segments.Max(
                static segment => segment.EndMs);
    }

    private sealed record PreparedTimingSegment(
        Guid? TokenId,
        long StartMs,
        long EndMs);
}
