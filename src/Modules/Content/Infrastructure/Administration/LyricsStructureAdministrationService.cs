using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Content.Infrastructure.Administration;

public sealed record LyricsTokenDraft(
    string Surface,
    int StartOffset,
    int EndOffset);

public sealed record LyricsLineDraft(
    string JapaneseText,
    string? SpeakerLabel,
    List<LyricsTokenDraft> Tokens);

public sealed record LyricsSectionDraft(
    string SectionType,
    string? Label,
    List<LyricsLineDraft> Lines);

public sealed record CreateLyricsRevisionInput(
    List<LyricsSectionDraft> Sections);

public sealed record LyricsTokenSnapshot(
    Guid TokenId,
    int TokenNo,
    string Surface,
    string NormalizedSurface,
    int StartOffset,
    int EndOffset);

public sealed record LyricsLineSnapshot(
    Guid LineId,
    int LineNo,
    string JapaneseText,
    string NormalizedText,
    string? SpeakerLabel,
    List<LyricsTokenSnapshot> Tokens);

public sealed record LyricsSectionSnapshot(
    Guid SectionId,
    string SectionType,
    string? Label,
    int DisplayOrder,
    List<LyricsLineSnapshot> Lines);

public sealed record LyricsRevisionSnapshot(
    Guid LyricsRevisionId,
    Guid RecordingId,
    int RevisionNo,
    Guid? ParentRevisionId,
    string StatusCode,
    Guid CreatedBy,
    DateTime CreatedAt,
    string ChecksumSha256,
    long Version,
    List<LyricsSectionSnapshot> Sections);

public sealed class LyricsStructureAdministrationException(
    string code,
    string message)
    : InvalidOperationException(message)
{
    public string Code { get; } = code;
}

public sealed partial class LyricsStructureAdministrationService(
    ILyricsStructureAdministrationTransactionExecutor transactionExecutor)
{
    private const string DraftStatusCode = "DRAFT";
    private const int MaxSections = 200;
    private const int MaxLinesPerSection = 500;
    private const int MaxTokensPerLine = 1000;
    private const int MaxJapaneseLineLength = 8000;
    private const int MaxLabelLength = 256;
    private const int MaxSpeakerLength = 256;

    [GeneratedRegex(
        "^[A-Z0-9][A-Z0-9._-]{0,63}$",
        RegexOptions.CultureInvariant)]
    private static partial Regex CodePattern();

    public Task<LyricsRevisionSnapshot?> ReadLatestAsync(
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
                ReadLatestCoreAsync(
                    connection,
                    transaction,
                    recordingId,
                    token),
            cancellationToken);
    }

    public Task<LyricsRevisionSnapshot> CreateRevisionAsync(
        Guid actorAccountId,
        Guid recordingId,
        CreateLyricsRevisionInput input,
        string ifMatch,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(input);
        ValidateIdentity(
            actorAccountId,
            recordingId,
            correlationId);

        var prepared = Prepare(input);
        var expected = ParseExpectedRevision(ifMatch);

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                CreateRevisionCoreAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    recordingId,
                    prepared,
                    expected,
                    token),
            cancellationToken);
    }

    private static async Task<LyricsRevisionSnapshot> CreateRevisionCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid recordingId,
        PreparedRevision prepared,
        ExpectedRevision expected,
        CancellationToken cancellationToken)
    {
        await AssertRecordingExistsAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        await AcquireRecordingLockAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        var latest = await ReadLatestCoreAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        EnsureExpectedRevision(latest, expected);

        if (latest is not null
            && string.Equals(
                latest.ChecksumSha256,
                prepared.ChecksumSha256,
                StringComparison.OrdinalIgnoreCase))
        {
            return latest;
        }

        var revisionId = Guid.CreateVersion7();
        var revisionNo = (latest?.RevisionNo ?? 0) + 1;
        var createdAt = DateTime.UtcNow;

        const string insertRevision = """
            INSERT INTO content.lyrics_revision (
                lyrics_revision_id,
                recording_id,
                revision_no,
                parent_revision_id,
                status_code,
                created_by,
                created_at,
                checksum,
                version
            )
            VALUES (
                @lyrics_revision_id,
                @recording_id,
                @revision_no,
                @parent_revision_id,
                'DRAFT',
                @created_by,
                @created_at,
                @checksum,
                1
            );
            """;

        await using (var command =
                     new NpgsqlCommand(
                         insertRevision,
                         connection,
                         transaction))
        {
            command.Parameters.AddWithValue(
                "lyrics_revision_id",
                NpgsqlDbType.Uuid,
                revisionId);
            command.Parameters.AddWithValue(
                "recording_id",
                NpgsqlDbType.Uuid,
                recordingId);
            command.Parameters.AddWithValue(
                "revision_no",
                NpgsqlDbType.Integer,
                revisionNo);

            var parent =
                command.Parameters.Add(
                    "parent_revision_id",
                    NpgsqlDbType.Uuid);
            parent.Value =
                latest is null
                    ? DBNull.Value
                    : latest.LyricsRevisionId;

            command.Parameters.AddWithValue(
                "created_by",
                NpgsqlDbType.Uuid,
                actorAccountId);
            command.Parameters.AddWithValue(
                "created_at",
                NpgsqlDbType.TimestampTz,
                createdAt);
            command.Parameters.AddWithValue(
                "checksum",
                NpgsqlDbType.Bytea,
                prepared.Checksum);

            await command.ExecuteNonQueryAsync(
                cancellationToken);
        }

        var sectionSnapshots =
            new List<LyricsSectionSnapshot>(
                prepared.Sections.Count);

        for (var sectionIndex = 0;
             sectionIndex < prepared.Sections.Count;
             sectionIndex++)
        {
            var section = prepared.Sections[sectionIndex];
            var sectionId = Guid.CreateVersion7();

            const string insertSection = """
                INSERT INTO content.lyric_section (
                    section_id,
                    lyrics_revision_id,
                    section_type,
                    label,
                    display_order
                )
                VALUES (
                    @section_id,
                    @lyrics_revision_id,
                    @section_type,
                    @label,
                    @display_order
                );
                """;

            await using (var command =
                         new NpgsqlCommand(
                             insertSection,
                             connection,
                             transaction))
            {
                command.Parameters.AddWithValue(
                    "section_id",
                    NpgsqlDbType.Uuid,
                    sectionId);
                command.Parameters.AddWithValue(
                    "lyrics_revision_id",
                    NpgsqlDbType.Uuid,
                    revisionId);
                command.Parameters.AddWithValue(
                    "section_type",
                    NpgsqlDbType.Varchar,
                    section.SectionType);
                AddNullableText(
                    command,
                    "label",
                    section.Label);
                command.Parameters.AddWithValue(
                    "display_order",
                    NpgsqlDbType.Integer,
                    sectionIndex);

                await command.ExecuteNonQueryAsync(
                    cancellationToken);
            }

            var lineSnapshots =
                new List<LyricsLineSnapshot>(
                    section.Lines.Count);

            for (var lineIndex = 0;
                 lineIndex < section.Lines.Count;
                 lineIndex++)
            {
                var line = section.Lines[lineIndex];
                var lineId = Guid.CreateVersion7();
                var lineNo = lineIndex + 1;

                const string insertLine = """
                    INSERT INTO content.lyric_line (
                        line_id,
                        section_id,
                        line_no,
                        japanese_text,
                        normalized_text,
                        speaker_label
                    )
                    VALUES (
                        @line_id,
                        @section_id,
                        @line_no,
                        @japanese_text,
                        @normalized_text,
                        @speaker_label
                    );
                    """;

                await using (var command =
                             new NpgsqlCommand(
                                 insertLine,
                                 connection,
                                 transaction))
                {
                    command.Parameters.AddWithValue(
                        "line_id",
                        NpgsqlDbType.Uuid,
                        lineId);
                    command.Parameters.AddWithValue(
                        "section_id",
                        NpgsqlDbType.Uuid,
                        sectionId);
                    command.Parameters.AddWithValue(
                        "line_no",
                        NpgsqlDbType.Integer,
                        lineNo);
                    command.Parameters.AddWithValue(
                        "japanese_text",
                        NpgsqlDbType.Text,
                        line.JapaneseText);
                    command.Parameters.AddWithValue(
                        "normalized_text",
                        NpgsqlDbType.Text,
                        line.NormalizedText);
                    AddNullableText(
                        command,
                        "speaker_label",
                        line.SpeakerLabel);

                    await command.ExecuteNonQueryAsync(
                        cancellationToken);
                }

                var tokenSnapshots =
                    new List<LyricsTokenSnapshot>(
                        line.Tokens.Count);

                for (var tokenIndex = 0;
                     tokenIndex < line.Tokens.Count;
                     tokenIndex++)
                {
                    var token = line.Tokens[tokenIndex];
                    var tokenId = Guid.CreateVersion7();
                    var tokenNo = tokenIndex + 1;

                    const string insertToken = """
                        INSERT INTO content.lyric_token (
                            token_id,
                            line_id,
                            token_no,
                            surface,
                            normalized_surface,
                            start_offset,
                            end_offset
                        )
                        VALUES (
                            @token_id,
                            @line_id,
                            @token_no,
                            @surface,
                            @normalized_surface,
                            @start_offset,
                            @end_offset
                        );
                        """;

                    await using var command =
                        new NpgsqlCommand(
                            insertToken,
                            connection,
                            transaction);

                    command.Parameters.AddWithValue(
                        "token_id",
                        NpgsqlDbType.Uuid,
                        tokenId);
                    command.Parameters.AddWithValue(
                        "line_id",
                        NpgsqlDbType.Uuid,
                        lineId);
                    command.Parameters.AddWithValue(
                        "token_no",
                        NpgsqlDbType.Integer,
                        tokenNo);
                    command.Parameters.AddWithValue(
                        "surface",
                        NpgsqlDbType.Text,
                        token.Surface);
                    command.Parameters.AddWithValue(
                        "normalized_surface",
                        NpgsqlDbType.Text,
                        token.NormalizedSurface);
                    command.Parameters.AddWithValue(
                        "start_offset",
                        NpgsqlDbType.Integer,
                        token.StartOffset);
                    command.Parameters.AddWithValue(
                        "end_offset",
                        NpgsqlDbType.Integer,
                        token.EndOffset);

                    await command.ExecuteNonQueryAsync(
                        cancellationToken);

                    tokenSnapshots.Add(
                        new LyricsTokenSnapshot(
                            tokenId,
                            tokenNo,
                            token.Surface,
                            token.NormalizedSurface,
                            token.StartOffset,
                            token.EndOffset));
                }

                lineSnapshots.Add(
                    new LyricsLineSnapshot(
                        lineId,
                        lineNo,
                        line.JapaneseText,
                        line.NormalizedText,
                        line.SpeakerLabel,
                        tokenSnapshots));
            }

            sectionSnapshots.Add(
                new LyricsSectionSnapshot(
                    sectionId,
                    section.SectionType,
                    section.Label,
                    sectionIndex,
                    lineSnapshots));
        }

        return new LyricsRevisionSnapshot(
            revisionId,
            recordingId,
            revisionNo,
            latest?.LyricsRevisionId,
            DraftStatusCode,
            actorAccountId,
            createdAt,
            prepared.ChecksumSha256,
            1,
            sectionSnapshots);
    }

    private static async Task<LyricsRevisionSnapshot?> ReadLatestCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string readRevision = """
            SELECT
                lyrics_revision_id,
                revision_no,
                parent_revision_id,
                status_code,
                created_by,
                created_at,
                encode(checksum, 'hex'),
                version
            FROM content.lyrics_revision
            WHERE recording_id = @recording_id
            ORDER BY
                revision_no DESC,
                lyrics_revision_id DESC
            LIMIT 1;
            """;

        Guid revisionId;
        int revisionNo;
        Guid? parentRevisionId;
        string statusCode;
        Guid createdBy;
        DateTime createdAt;
        string checksum;
        long version;

        await using (var command =
                     new NpgsqlCommand(
                         readRevision,
                         connection,
                         transaction))
        {
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
                return null;
            }

            revisionId = reader.GetGuid(0);
            revisionNo = reader.GetInt32(1);
            parentRevisionId =
                reader.IsDBNull(2)
                    ? null
                    : reader.GetGuid(2);
            statusCode = reader.GetString(3);
            createdBy = reader.GetGuid(4);
            createdAt = reader.GetDateTime(5);
            checksum = reader.GetString(6);
            version = reader.GetInt64(7);
        }

        var sections =
            await ReadSectionsAsync(
                connection,
                transaction,
                revisionId,
                cancellationToken);

        return new LyricsRevisionSnapshot(
            revisionId,
            recordingId,
            revisionNo,
            parentRevisionId,
            statusCode,
            createdBy,
            createdAt,
            checksum,
            version,
            sections);
    }

    private static async Task<List<LyricsSectionSnapshot>> ReadSectionsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid revisionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                section_id,
                section_type,
                label,
                display_order
            FROM content.lyric_section
            WHERE lyrics_revision_id = @lyrics_revision_id
            ORDER BY
                display_order,
                section_id;
            """;

        var rows =
            new List<SectionRow>();

        await using (var command =
                     new NpgsqlCommand(
                         sql,
                         connection,
                         transaction))
        {
            command.Parameters.AddWithValue(
                "lyrics_revision_id",
                NpgsqlDbType.Uuid,
                revisionId);

            await using var reader =
                await command.ExecuteReaderAsync(
                    cancellationToken);

            while (await reader.ReadAsync(
                       cancellationToken))
            {
                rows.Add(
                    new SectionRow(
                        reader.GetGuid(0),
                        reader.GetString(1),
                        reader.IsDBNull(2)
                            ? null
                            : reader.GetString(2),
                        reader.GetInt32(3)));
            }
        }

        var result =
            new List<LyricsSectionSnapshot>(
                rows.Count);

        foreach (var row in rows)
        {
            var lines =
                await ReadLinesAsync(
                    connection,
                    transaction,
                    row.SectionId,
                    cancellationToken);

            result.Add(
                new LyricsSectionSnapshot(
                    row.SectionId,
                    row.SectionType,
                    row.Label,
                    row.DisplayOrder,
                    lines));
        }

        return result;
    }

    private static async Task<List<LyricsLineSnapshot>> ReadLinesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid sectionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                line_id,
                line_no,
                japanese_text,
                normalized_text,
                speaker_label
            FROM content.lyric_line
            WHERE section_id = @section_id
            ORDER BY
                line_no,
                line_id;
            """;

        var rows =
            new List<LineRow>();

        await using (var command =
                     new NpgsqlCommand(
                         sql,
                         connection,
                         transaction))
        {
            command.Parameters.AddWithValue(
                "section_id",
                NpgsqlDbType.Uuid,
                sectionId);

            await using var reader =
                await command.ExecuteReaderAsync(
                    cancellationToken);

            while (await reader.ReadAsync(
                       cancellationToken))
            {
                rows.Add(
                    new LineRow(
                        reader.GetGuid(0),
                        reader.GetInt32(1),
                        reader.GetString(2),
                        reader.GetString(3),
                        reader.IsDBNull(4)
                            ? null
                            : reader.GetString(4)));
            }
        }

        var result =
            new List<LyricsLineSnapshot>(
                rows.Count);

        foreach (var row in rows)
        {
            var tokens =
                await ReadTokensAsync(
                    connection,
                    transaction,
                    row.LineId,
                    cancellationToken);

            result.Add(
                new LyricsLineSnapshot(
                    row.LineId,
                    row.LineNo,
                    row.JapaneseText,
                    row.NormalizedText,
                    row.SpeakerLabel,
                    tokens));
        }

        return result;
    }

    private static async Task<List<LyricsTokenSnapshot>> ReadTokensAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid lineId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                token_id,
                token_no,
                surface,
                normalized_surface,
                start_offset,
                end_offset
            FROM content.lyric_token
            WHERE line_id = @line_id
            ORDER BY
                token_no,
                token_id;
            """;

        var result =
            new List<LyricsTokenSnapshot>();

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
                new LyricsTokenSnapshot(
                    reader.GetGuid(0),
                    reader.GetInt32(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetInt32(4),
                    reader.GetInt32(5)));
        }

        return result;
    }

    private static PreparedRevision Prepare(
        CreateLyricsRevisionInput input)
    {
        if (input.Sections.Count == 0)
        {
            throw new LyricsStructureAdministrationException(
                "content.lyrics.sections.required",
                "La revisión debe contener al menos una sección.");
        }

        if (input.Sections.Count > MaxSections)
        {
            throw new LyricsStructureAdministrationException(
                "content.lyrics.sections.too-many",
                "La revisión supera la cantidad máxima de secciones.");
        }

        var sections =
            new List<PreparedSection>(
                input.Sections.Count);

        foreach (var sourceSection in input.Sections)
        {
            if (sourceSection.Lines.Count == 0)
            {
                throw new LyricsStructureAdministrationException(
                    "content.lyrics.lines.required",
                    "Cada sección debe contener al menos una línea.");
            }

            if (sourceSection.Lines.Count > MaxLinesPerSection)
            {
                throw new LyricsStructureAdministrationException(
                    "content.lyrics.lines.too-many",
                    "Una sección supera la cantidad máxima de líneas.");
            }

            var sectionType =
                sourceSection.SectionType
                    .Trim()
                    .ToUpperInvariant();

            if (!CodePattern().IsMatch(
                    sectionType))
            {
                throw new LyricsStructureAdministrationException(
                    "content.lyrics.section-type.invalid",
                    "El tipo de sección debe utilizar un código editorial válido.");
            }

            var label =
                NormalizeOptional(
                    sourceSection.Label,
                    MaxLabelLength,
                    "content.lyrics.section-label.too-long",
                    "La etiqueta de sección supera el máximo permitido.");

            var lines =
                new List<PreparedLine>(
                    sourceSection.Lines.Count);

            foreach (var sourceLine in sourceSection.Lines)
            {
                ValidateUnknownContentLine(sourceLine);

                if (string.IsNullOrWhiteSpace(
                        sourceLine.JapaneseText))
                {
                    throw new LyricsStructureAdministrationException(
                        "content.lyrics.japanese-text.required",
                        "La superficie japonesa original no puede quedar vacía.");
                }

                if (sourceLine.JapaneseText.Length > MaxJapaneseLineLength)
                {
                    throw new LyricsStructureAdministrationException(
                        "content.lyrics.japanese-text.too-long",
                        "Una línea japonesa supera el máximo permitido.");
                }

                if (sourceLine.Tokens.Count > MaxTokensPerLine)
                {
                    throw new LyricsStructureAdministrationException(
                        "content.lyrics.tokens.too-many",
                        "Una línea supera la cantidad máxima de tokens.");
                }

                var original =
                    sourceLine.JapaneseText;
                var normalized =
                    original.Normalize(
                        NormalizationForm.FormC);

                var speaker =
                    NormalizeOptional(
                        sourceLine.SpeakerLabel,
                        MaxSpeakerLength,
                        "content.lyrics.speaker.too-long",
                        "La etiqueta de voz supera el máximo permitido.");

                var tokens =
                    PrepareTokens(
                        original,
                        sourceLine.Tokens);

                lines.Add(
                    new PreparedLine(
                        original,
                        normalized,
                        speaker,
                        tokens));
            }

            sections.Add(
                new PreparedSection(
                    sectionType,
                    label,
                    lines));
        }

        var checksumSource =
            JsonSerializer.SerializeToUtf8Bytes(
                sections);

        var checksum =
            SHA256.HashData(
                checksumSource);

        return new PreparedRevision(
            sections,
            checksum,
            Convert.ToHexString(
                    checksum)
                .ToLowerInvariant());
    }

    private static List<PreparedToken> PrepareTokens(
        string original,
        List<LyricsTokenDraft> sourceTokens)
    {
        var result =
            new List<PreparedToken>(
                sourceTokens.Count);

        var previousEnd = 0;

        foreach (var sourceToken in sourceTokens)
        {
            if (string.IsNullOrEmpty(
                    sourceToken.Surface))
            {
                throw new LyricsStructureAdministrationException(
                    "content.lyrics.token.surface.required",
                    "Un token no puede tener una superficie vacía.");
            }

            if (sourceToken.StartOffset < 0
                || sourceToken.EndOffset <= sourceToken.StartOffset
                || sourceToken.EndOffset > original.Length)
            {
                throw new LyricsStructureAdministrationException(
                    "content.lyrics.token.offset.invalid",
                    "Los offsets del token no son válidos para la superficie japonesa.");
            }

            if (sourceToken.StartOffset < previousEnd)
            {
                throw new LyricsStructureAdministrationException(
                    "content.lyrics.token.overlap.invalid",
                    "Los tokens editoriales no pueden solaparse dentro de la línea.");
            }

            var slice =
                original.Substring(
                    sourceToken.StartOffset,
                    sourceToken.EndOffset
                    - sourceToken.StartOffset);

            if (!string.Equals(
                    slice,
                    sourceToken.Surface,
                    StringComparison.Ordinal))
            {
                throw new LyricsStructureAdministrationException(
                    "content.lyrics.token.surface-mismatch",
                    "La superficie del token debe coincidir exactamente con el texto original en sus offsets.");
            }

            result.Add(
                new PreparedToken(
                    sourceToken.Surface,
                    sourceToken.Surface.Normalize(
                        NormalizationForm.FormC),
                    sourceToken.StartOffset,
                    sourceToken.EndOffset));

            previousEnd =
                sourceToken.EndOffset;
        }

        return result;
    }

    private static readonly string[] UnknownContentMarkers =
    [
        "[UNKNOWN:INAUDIBLE]",
        "[UNKNOWN:UNKNOWN]",
        "[UNKNOWN:OMITTED]",
        "[UNKNOWN:PENDING_TRANSCRIPTION]"
    ];

    private static ExpectedRevision ParseExpectedRevision(
        string ifMatch)
    {
        if (string.IsNullOrWhiteSpace(ifMatch))
        {
            throw new LyricsStructureAdministrationException(
                "content.lyrics.precondition-required",
                "El guardado requiere la revisión base mediante If-Match.");
        }

        var normalized = ifMatch.Trim();

        if (string.Equals(
                normalized,
                "\"lyrics-none\"",
                StringComparison.Ordinal))
        {
            return new ExpectedRevision(
                ExpectsNone: true,
                RevisionId: null,
                Version: 0);
        }

        const string prefix = "\"lyrics-";
        const string suffix = "\"";
        const string versionSeparator = "-v";

        if (!normalized.StartsWith(prefix, StringComparison.Ordinal)
            || !normalized.EndsWith(suffix, StringComparison.Ordinal))
        {
            throw new LyricsStructureAdministrationException(
                "content.lyrics.etag.invalid",
                "El ETag de letra no tiene un formato válido.");
        }

        var body = normalized[1..^1];
        var separatorIndex = body.LastIndexOf(
            versionSeparator,
            StringComparison.Ordinal);

        if (separatorIndex < "lyrics-".Length)
        {
            throw new LyricsStructureAdministrationException(
                "content.lyrics.etag.invalid",
                "El ETag de letra no tiene un formato válido.");
        }

        var idText = body["lyrics-".Length..separatorIndex];
        var versionText = body[(separatorIndex + versionSeparator.Length)..];

        if (!Guid.TryParseExact(idText, "N", out var revisionId)
            || !long.TryParse(versionText, out var version)
            || version <= 0)
        {
            throw new LyricsStructureAdministrationException(
                "content.lyrics.etag.invalid",
                "El ETag de letra no tiene un formato válido.");
        }

        return new ExpectedRevision(
            ExpectsNone: false,
            RevisionId: revisionId,
            Version: version);
    }

    private static void EnsureExpectedRevision(
        LyricsRevisionSnapshot? latest,
        ExpectedRevision expected)
    {
        if (expected.ExpectsNone)
        {
            if (latest is null)
            {
                return;
            }

            throw Conflict();
        }

        if (latest is null
            || latest.LyricsRevisionId != expected.RevisionId
            || latest.Version != expected.Version)
        {
            throw Conflict();
        }
    }

    private static LyricsStructureAdministrationException Conflict() =>
        new(
            "content.lyrics.conflict",
            "La revisión base cambió antes de guardar. Compara el borrador local con la revisión vigente.");

    private static void ValidateUnknownContentLine(
        LyricsLineDraft line)
    {
        if (!line.JapaneseText.StartsWith(
                "[UNKNOWN:",
                StringComparison.Ordinal))
        {
            return;
        }

        var markerAllowed = Array.Exists(
            UnknownContentMarkers,
            marker => string.Equals(
                marker,
                line.JapaneseText,
                StringComparison.Ordinal));

        if (!markerAllowed)
        {
            throw new LyricsStructureAdministrationException(
                "content.lyrics.unknown-content.invalid",
                "El contenido desconocido debe usar uno de los marcadores editoriales permitidos.");
        }

        if (line.Tokens.Count > 0)
        {
            throw new LyricsStructureAdministrationException(
                "content.lyrics.unknown-content.tokens-invalid",
                "Una línea marcada como contenido desconocido no puede inventar tokens.");
        }
    }

    private static string? NormalizeOptional(
        string? value,
        int maxLength,
        string code,
        string message)
    {
        if (string.IsNullOrWhiteSpace(
                value))
        {
            return null;
        }

        var normalized =
            value.Trim();

        if (normalized.Length > maxLength)
        {
            throw new LyricsStructureAdministrationException(
                code,
                message);
        }

        return normalized;
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
                FROM catalog.recording AS recording
                WHERE recording.recording_id = @recording_id
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
            throw new LyricsStructureAdministrationException(
                "content.lyrics.recording.not-found",
                "La grabación indicada no existe.");
        }
    }

    private static async Task AcquireRecordingLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT pg_advisory_xact_lock(
                hashtextextended(
                    CAST(@recording_id AS text),
                    53
                )
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
            throw new LyricsStructureAdministrationException(
                "content.lyrics.recording.invalid",
                "La grabación solicitada no es válida.");
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(
            correlationId);
    }

    private static void AddNullableText(
        NpgsqlCommand command,
        string name,
        string? value)
    {
        var parameter =
            command.Parameters.Add(
                name,
                NpgsqlDbType.Text);

        parameter.Value =
            value is null
                ? DBNull.Value
                : value;
    }

    private sealed record ExpectedRevision(
        bool ExpectsNone,
        Guid? RevisionId,
        long Version);

    private sealed record PreparedRevision(
        List<PreparedSection> Sections,
        byte[] Checksum,
        string ChecksumSha256);

    private sealed record PreparedSection(
        string SectionType,
        string? Label,
        List<PreparedLine> Lines);

    private sealed record PreparedLine(
        string JapaneseText,
        string NormalizedText,
        string? SpeakerLabel,
        List<PreparedToken> Tokens);

    private sealed record PreparedToken(
        string Surface,
        string NormalizedSurface,
        int StartOffset,
        int EndOffset);

    private sealed record SectionRow(
        Guid SectionId,
        string SectionType,
        string? Label,
        int DisplayOrder);

    private sealed record LineRow(
        Guid LineId,
        int LineNo,
        string JapaneseText,
        string NormalizedText,
        string? SpeakerLabel);
}
