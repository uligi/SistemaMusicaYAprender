using System.Text.RegularExpressions;
using Npgsql;

namespace MusicaAprender.Modules.Content.Infrastructure.Administration;

public sealed record TranslationSourceLineSnapshot(
    Guid LineId,
    int LineNo,
    string JapaneseText);

public sealed record TranslationAlignmentSnapshot(
    Guid AlignmentId,
    Guid TokenId,
    Guid SourceLineId,
    int SourceLineNo,
    string Surface,
    int? TargetStart,
    int? TargetEnd,
    string AlignmentType);

public sealed record TranslationLineSnapshot(
    Guid TranslationLineId,
    Guid AnchorLineId,
    int AnchorLineNo,
    string JapaneseText,
    string VariantCode,
    string TranslatedText,
    int DisplayOrder,
    List<TranslationAlignmentSnapshot> Alignments);

public sealed record TranslationNoteSnapshot(
    Guid NoteId,
    Guid? LineId,
    Guid? TokenId,
    string NoteType,
    string NoteText,
    Guid? SourceReferenceId,
    string? SourceType,
    string? Citation,
    string? Locator);

public sealed record TranslationProvenanceSnapshot(
    Guid SourceReferenceId,
    string SourceType,
    string Citation,
    string? Locator,
    string ContributionType,
    Guid RecordedBy,
    DateTimeOffset RecordedAt);

public sealed record TranslationRevisionSnapshot(
    Guid TranslationRevisionId,
    Guid LyricsRevisionId,
    int LyricsRevisionNo,
    string TargetLanguage,
    string TranslationType,
    int RevisionNo,
    Guid? ParentRevisionId,
    string StatusCode,
    string ChecksumSha256,
    int SourceLineCount,
    int LiteralCoveredLines,
    int NaturalCoveredLines,
    bool CompleteForReview,
    List<int> MissingLiteralLineNos,
    List<int> MissingNaturalLineNos,
    bool HasManyToManyAlignment,
    List<TranslationLineSnapshot> Lines,
    List<TranslationNoteSnapshot> Notes,
    List<TranslationProvenanceSnapshot> Provenance);

public sealed record TranslationContextSnapshot(
    Guid RecordingId,
    Guid? LyricsRevisionId,
    int? LyricsRevisionNo,
    string TargetLanguage,
    string TranslationType,
    bool HasStaleRevision,
    List<TranslationSourceLineSnapshot> SourceLines,
    TranslationRevisionSnapshot? Revision);

public sealed class TranslationAdministrationException(
    string code,
    string message)
    : InvalidOperationException(message)
{
    public string Code { get; } = code;
}

public sealed partial class TranslationRevisionAdministrationService(
    ITranslationAdministrationTransactionExecutor transactionExecutor)
{
    public Task<TranslationContextSnapshot> ReadContextAsync(
        Guid actorAccountId,
        Guid recordingId,
        string targetLanguage,
        string translationType,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentity(actorAccountId, recordingId, correlationId);
        var language = NormalizeLanguage(targetLanguage);
        var type = NormalizeCode(translationType, "content.translation.type.invalid");

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                ReadContextCoreAsync(
                    connection,
                    transaction,
                    recordingId,
                    language,
                    type,
                    token),
            cancellationToken);
    }

    private static async Task<TranslationContextSnapshot> ReadContextCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        string targetLanguage,
        string translationType,
        CancellationToken cancellationToken)
    {
        await AssertRecordingExistsAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        var lyrics = await ReadLatestLyricsRevisionAsync(
            connection,
            transaction,
            recordingId,
            cancellationToken);

        if (lyrics is null)
        {
            return new TranslationContextSnapshot(
                recordingId,
                null,
                null,
                targetLanguage,
                translationType,
                false,
                [],
                null);
        }

        var sourceLines = await ReadSourceLinesAsync(
            connection,
            transaction,
            lyrics.LyricsRevisionId,
            cancellationToken);

        var hasStaleRevision = await HasStaleRevisionAsync(
            connection,
            transaction,
            recordingId,
            lyrics.LyricsRevisionId,
            targetLanguage,
            translationType,
            cancellationToken);

        var revisionHead = await ReadLatestCompatibleRevisionAsync(
            connection,
            transaction,
            lyrics.LyricsRevisionId,
            targetLanguage,
            translationType,
            cancellationToken);

        TranslationRevisionSnapshot? revision = null;
        if (revisionHead is not null)
        {
            revision = await ReadRevisionSnapshotAsync(
                connection,
                transaction,
                revisionHead,
                lyrics.RevisionNo,
                sourceLines,
                cancellationToken);
        }

        return new TranslationContextSnapshot(
            recordingId,
            lyrics.LyricsRevisionId,
            lyrics.RevisionNo,
            targetLanguage,
            translationType,
            hasStaleRevision,
            sourceLines,
            revision);
    }

    private static async Task AssertRecordingExistsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            """
            SELECT EXISTS (
                SELECT 1
                FROM catalog.recording
                WHERE recording_id = @recording_id
            );
            """;
        command.Parameters.AddWithValue("recording_id", recordingId);

        var exists = (bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false);
        if (!exists)
        {
            throw new TranslationAdministrationException(
                "content.translation.recording.not-found",
                "La grabación editorial no existe.");
        }
    }

    private static async Task<LyricsRevisionHead?> ReadLatestLyricsRevisionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            """
            SELECT lyrics_revision_id, revision_no
            FROM content.lyrics_revision
            WHERE recording_id = @recording_id
            ORDER BY revision_no DESC
            LIMIT 1;
            """;
        command.Parameters.AddWithValue("recording_id", recordingId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new LyricsRevisionHead(reader.GetGuid(0), reader.GetInt32(1));
    }

    private static async Task<List<TranslationSourceLineSnapshot>> ReadSourceLinesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid lyricsRevisionId,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            """
            SELECT line.line_id, line.line_no, line.japanese_text
            FROM content.lyric_line AS line
            JOIN content.lyric_section AS section
              ON section.section_id = line.section_id
            WHERE section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY section.display_order, line.line_no;
            """;
        command.Parameters.AddWithValue("lyrics_revision_id", lyricsRevisionId);

        var lines = new List<TranslationSourceLineSnapshot>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            lines.Add(
                new TranslationSourceLineSnapshot(
                    reader.GetGuid(0),
                    reader.GetInt32(1),
                    reader.GetString(2)));
        }

        return lines;
    }

    private static async Task<bool> HasStaleRevisionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid currentLyricsRevisionId,
        string targetLanguage,
        string translationType,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            """
            SELECT EXISTS (
                SELECT 1
                FROM content.translation_revision AS translation
                JOIN content.lyrics_revision AS lyrics
                  ON lyrics.lyrics_revision_id = translation.lyrics_revision_id
                WHERE lyrics.recording_id = @recording_id
                  AND translation.lyrics_revision_id <> @current_lyrics_revision_id
                  AND lower(translation.target_language) = lower(@target_language)
                  AND translation.translation_type = @translation_type
            );
            """;
        command.Parameters.AddWithValue("recording_id", recordingId);
        command.Parameters.AddWithValue("current_lyrics_revision_id", currentLyricsRevisionId);
        command.Parameters.AddWithValue("target_language", targetLanguage);
        command.Parameters.AddWithValue("translation_type", translationType);

        return (bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false);
    }

    private static async Task<TranslationRevisionHead?> ReadLatestCompatibleRevisionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid lyricsRevisionId,
        string targetLanguage,
        string translationType,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            """
            SELECT
                translation_revision_id,
                lyrics_revision_id,
                target_language,
                translation_type,
                revision_no,
                parent_revision_id,
                status_code,
                encode(checksum, 'hex')
            FROM content.translation_revision
            WHERE lyrics_revision_id = @lyrics_revision_id
              AND lower(target_language) = lower(@target_language)
              AND translation_type = @translation_type
            ORDER BY revision_no DESC
            LIMIT 1;
            """;
        command.Parameters.AddWithValue("lyrics_revision_id", lyricsRevisionId);
        command.Parameters.AddWithValue("target_language", targetLanguage);
        command.Parameters.AddWithValue("translation_type", translationType);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new TranslationRevisionHead(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetInt32(4),
            reader.IsDBNull(5) ? null : reader.GetGuid(5),
            reader.GetString(6),
            reader.GetString(7));
    }

    private static async Task<TranslationRevisionSnapshot> ReadRevisionSnapshotAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        TranslationRevisionHead revision,
        int lyricsRevisionNo,
        List<TranslationSourceLineSnapshot> sourceLines,
        CancellationToken cancellationToken)
    {
        var lines = await ReadTranslationLinesAsync(
            connection,
            transaction,
            revision.TranslationRevisionId,
            revision.LyricsRevisionId,
            cancellationToken);

        var alignments = await ReadAlignmentsAsync(
            connection,
            transaction,
            revision.TranslationRevisionId,
            revision.LyricsRevisionId,
            cancellationToken);

        var alignmentsByTranslationLine = alignments
            .GroupBy(alignment => alignment.TranslationLineId)
            .ToDictionary(
                group => group.Key,
                group => group
                    .Select(alignment => alignment.Snapshot)
                    .OrderBy(alignment => alignment.SourceLineNo)
                    .ThenBy(alignment => alignment.TargetStart ?? int.MaxValue)
                    .ToList());

        var lineSnapshots = lines
            .Select(
                line => new TranslationLineSnapshot(
                    line.TranslationLineId,
                    line.AnchorLineId,
                    line.AnchorLineNo,
                    line.JapaneseText,
                    line.VariantCode,
                    line.TranslatedText,
                    line.DisplayOrder,
                    alignmentsByTranslationLine.GetValueOrDefault(
                        line.TranslationLineId,
                        [])))
            .ToList();

        var notes = await ReadNotesAsync(
            connection,
            transaction,
            revision.TranslationRevisionId,
            revision.LyricsRevisionId,
            cancellationToken);

        var provenance = await ReadProvenanceAsync(
            connection,
            transaction,
            revision.TranslationRevisionId,
            cancellationToken);

        var sourceLineIds = sourceLines.Select(line => line.LineId).ToHashSet();
        var literalIds = lines
            .Where(line => line.VariantCode == "LITERAL")
            .Select(line => line.AnchorLineId)
            .ToHashSet();
        var naturalIds = lines
            .Where(line => line.VariantCode == "NATURAL")
            .Select(line => line.AnchorLineId)
            .ToHashSet();

        var missingLiteral = sourceLines
            .Where(line => !literalIds.Contains(line.LineId))
            .Select(line => line.LineNo)
            .ToList();
        var missingNatural = sourceLines
            .Where(line => !naturalIds.Contains(line.LineId))
            .Select(line => line.LineNo)
            .ToList();

        var translationsWithManySources = alignments
            .GroupBy(alignment => alignment.TranslationLineId)
            .Any(group => group.Select(alignment => alignment.Snapshot.TokenId).Distinct().Count() > 1);

        var sourcesWithManyTranslations = alignments
            .GroupBy(alignment => alignment.Snapshot.TokenId)
            .Any(group => group.Select(alignment => alignment.TranslationLineId).Distinct().Count() > 1);

        var allAlignedTokensBelongToCurrentLyrics = alignments
            .All(alignment => sourceLineIds.Contains(alignment.Snapshot.SourceLineId));

        return new TranslationRevisionSnapshot(
            revision.TranslationRevisionId,
            revision.LyricsRevisionId,
            lyricsRevisionNo,
            revision.TargetLanguage,
            revision.TranslationType,
            revision.RevisionNo,
            revision.ParentRevisionId,
            revision.StatusCode,
            revision.ChecksumSha256,
            sourceLines.Count,
            literalIds.Count,
            naturalIds.Count,
            sourceLines.Count > 0
                && missingLiteral.Count == 0
                && missingNatural.Count == 0
                && allAlignedTokensBelongToCurrentLyrics,
            missingLiteral,
            missingNatural,
            translationsWithManySources && sourcesWithManyTranslations,
            lineSnapshots,
            notes,
            provenance);
    }

    private static async Task<List<TranslationLineRow>> ReadTranslationLinesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid translationRevisionId,
        Guid lyricsRevisionId,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            """
            SELECT
                translated.translation_line_id,
                translated.line_id,
                source.line_no,
                source.japanese_text,
                translated.variant_code,
                translated.translated_text,
                translated.display_order
            FROM content.translation_line AS translated
            JOIN content.lyric_line AS source
              ON source.line_id = translated.line_id
            JOIN content.lyric_section AS section
              ON section.section_id = source.section_id
            WHERE translated.translation_revision_id = @translation_revision_id
              AND section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY translated.display_order, section.display_order, source.line_no, translated.variant_code;
            """;
        command.Parameters.AddWithValue("translation_revision_id", translationRevisionId);
        command.Parameters.AddWithValue("lyrics_revision_id", lyricsRevisionId);

        var rows = new List<TranslationLineRow>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(
                new TranslationLineRow(
                    reader.GetGuid(0),
                    reader.GetGuid(1),
                    reader.GetInt32(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.GetString(5),
                    reader.GetInt32(6)));
        }

        return rows;
    }

    private static async Task<List<TranslationAlignmentRow>> ReadAlignmentsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid translationRevisionId,
        Guid lyricsRevisionId,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            """
            SELECT
                alignment.translation_line_id,
                alignment.alignment_id,
                alignment.token_id,
                token.line_id,
                source.line_no,
                token.surface,
                alignment.target_start,
                alignment.target_end,
                alignment.alignment_type
            FROM content.token_alignment AS alignment
            JOIN content.translation_line AS translated
              ON translated.translation_line_id = alignment.translation_line_id
            JOIN content.lyric_line AS anchor
              ON anchor.line_id = translated.line_id
            JOIN content.lyric_section AS anchor_section
              ON anchor_section.section_id = anchor.section_id
            JOIN content.lyric_token AS token
              ON token.token_id = alignment.token_id
            JOIN content.lyric_line AS source
              ON source.line_id = token.line_id
            JOIN content.lyric_section AS token_section
              ON token_section.section_id = source.section_id
            WHERE translated.translation_revision_id = @translation_revision_id
              AND anchor_section.lyrics_revision_id = @lyrics_revision_id
              AND token_section.lyrics_revision_id = @lyrics_revision_id
            ORDER BY translated.display_order, token_section.display_order, source.line_no, token.token_no;
            """;
        command.Parameters.AddWithValue("translation_revision_id", translationRevisionId);
        command.Parameters.AddWithValue("lyrics_revision_id", lyricsRevisionId);

        var rows = new List<TranslationAlignmentRow>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(
                new TranslationAlignmentRow(
                    reader.GetGuid(0),
                    new TranslationAlignmentSnapshot(
                        reader.GetGuid(1),
                        reader.GetGuid(2),
                        reader.GetGuid(3),
                        reader.GetInt32(4),
                        reader.GetString(5),
                        reader.IsDBNull(6) ? null : reader.GetInt32(6),
                        reader.IsDBNull(7) ? null : reader.GetInt32(7),
                        reader.GetString(8))));
        }

        return rows;
    }

    private static async Task<List<TranslationNoteSnapshot>> ReadNotesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid translationRevisionId,
        Guid lyricsRevisionId,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            """
            SELECT
                note.note_id,
                note.line_id,
                note.token_id,
                note.note_type,
                note.note_text,
                note.source_reference_id,
                source.source_type,
                source.citation,
                source.locator
            FROM content.translation_note AS note
            LEFT JOIN content.lyric_line AS note_line
              ON note_line.line_id = note.line_id
            LEFT JOIN content.lyric_section AS note_line_section
              ON note_line_section.section_id = note_line.section_id
            LEFT JOIN content.lyric_token AS note_token
              ON note_token.token_id = note.token_id
            LEFT JOIN content.lyric_line AS note_token_line
              ON note_token_line.line_id = note_token.line_id
            LEFT JOIN content.lyric_section AS note_token_section
              ON note_token_section.section_id = note_token_line.section_id
            LEFT JOIN catalog.source_reference AS source
              ON source.source_reference_id = note.source_reference_id
            WHERE note.translation_revision_id = @translation_revision_id
              AND (
                  note.line_id IS NULL
                  OR note_line_section.lyrics_revision_id = @lyrics_revision_id
              )
              AND (
                  note.token_id IS NULL
                  OR note_token_section.lyrics_revision_id = @lyrics_revision_id
              )
            ORDER BY note.note_id;
            """;
        command.Parameters.AddWithValue("translation_revision_id", translationRevisionId);
        command.Parameters.AddWithValue("lyrics_revision_id", lyricsRevisionId);

        var notes = new List<TranslationNoteSnapshot>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            notes.Add(
                new TranslationNoteSnapshot(
                    reader.GetGuid(0),
                    reader.IsDBNull(1) ? null : reader.GetGuid(1),
                    reader.IsDBNull(2) ? null : reader.GetGuid(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.IsDBNull(5) ? null : reader.GetGuid(5),
                    reader.IsDBNull(6) ? null : reader.GetString(6),
                    reader.IsDBNull(7) ? null : reader.GetString(7),
                    reader.IsDBNull(8) ? null : reader.GetString(8)));
        }

        return notes;
    }

    private static async Task<List<TranslationProvenanceSnapshot>> ReadProvenanceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid translationRevisionId,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            """
            SELECT
                provenance.source_reference_id,
                source.source_type,
                source.citation,
                source.locator,
                provenance.contribution_type,
                provenance.recorded_by,
                provenance.recorded_at
            FROM editorial.provenance_record AS provenance
            JOIN catalog.source_reference AS source
              ON source.source_reference_id = provenance.source_reference_id
            WHERE provenance.object_type = 'TRANSLATION_REVISION'
              AND provenance.object_id = @translation_revision_id
            ORDER BY provenance.recorded_at, provenance.provenance_id;
            """;
        command.Parameters.AddWithValue("translation_revision_id", translationRevisionId);

        var provenance = new List<TranslationProvenanceSnapshot>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            provenance.Add(
                new TranslationProvenanceSnapshot(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.GetString(4),
                    reader.GetGuid(5),
                    new DateTimeOffset(reader.GetDateTime(6))));
        }

        return provenance;
    }

    private static void ValidateIdentity(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId)
    {
        if (actorAccountId == Guid.Empty)
        {
            throw new ArgumentException("El actor es obligatorio.", nameof(actorAccountId));
        }

        if (recordingId == Guid.Empty)
        {
            throw new ArgumentException("La grabación es obligatoria.", nameof(recordingId));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(correlationId);
    }

    private static string NormalizeLanguage(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        var normalized = value.Trim();

        if (!LanguageTagRegex().IsMatch(normalized))
        {
            throw new TranslationAdministrationException(
                "content.translation.language.invalid",
                "El idioma objetivo debe usar un código normalizado.");
        }

        return normalized;
    }

    private static string NormalizeCode(string value, string code)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        var normalized = value.Trim().ToUpperInvariant();

        if (!CodeRegex().IsMatch(normalized))
        {
            throw new TranslationAdministrationException(
                code,
                "El tipo de traducción no es válido.");
        }

        return normalized;
    }

    [GeneratedRegex("^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$", RegexOptions.CultureInvariant)]
    private static partial Regex LanguageTagRegex();

    [GeneratedRegex("^[A-Z0-9][A-Z0-9._-]{0,63}$", RegexOptions.CultureInvariant)]
    private static partial Regex CodeRegex();

    private sealed record LyricsRevisionHead(Guid LyricsRevisionId, int RevisionNo);

    private sealed record TranslationRevisionHead(
        Guid TranslationRevisionId,
        Guid LyricsRevisionId,
        string TargetLanguage,
        string TranslationType,
        int RevisionNo,
        Guid? ParentRevisionId,
        string StatusCode,
        string ChecksumSha256);

    private sealed record TranslationLineRow(
        Guid TranslationLineId,
        Guid AnchorLineId,
        int AnchorLineNo,
        string JapaneseText,
        string VariantCode,
        string TranslatedText,
        int DisplayOrder);

    private sealed record TranslationAlignmentRow(
        Guid TranslationLineId,
        TranslationAlignmentSnapshot Snapshot);
}
