using System.Text.RegularExpressions;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Catalog.Infrastructure.Administration;

public sealed record RecordingDraftAutosaveInput(
    string? RecordingTitle,
    long? RecordingDurationMs,
    long? SourceDurationMs,
    long OffsetMs);

public sealed record RecordingDraftAutosaveSnapshot(
    Guid RecordingId,
    Guid SourceId,
    string? RecordingTitle,
    long? RecordingDurationMs,
    long? SourceDurationMs,
    long OffsetMs,
    string RecordingStatusCode,
    string SourceStatusCode,
    long RecordingVersion,
    long SourceVersion)
{
    public string ETag =>
        $"\"recording-{RecordingVersion}-source-{SourceVersion}\"";
}

public sealed class RecordingDraftAutosaveException(
    string code,
    string message,
    RecordingDraftAutosaveSnapshot? current = null)
    : InvalidOperationException(message)
{
    public string Code { get; } = code;

    public RecordingDraftAutosaveSnapshot? Current { get; } = current;
}

public sealed partial class RecordingDraftAutosaveService(
    ISongDraftAdministrationTransactionExecutor transactionExecutor)
{
    private const int MaxRecordingTitleLength = 512;
    private const string DraftStatusCode = "DRAFT";

    [GeneratedRegex(
        "^\"recording-(?<recording>[1-9][0-9]*)-source-(?<source>[1-9][0-9]*)\"$",
        RegexOptions.CultureInvariant)]
    private static partial Regex ETagPattern();

    public Task<RecordingDraftAutosaveSnapshot> ReadAsync(
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
            async (connection, transaction, token) =>
                await ReadSnapshotAsync(
                    connection,
                    transaction,
                    recordingId,
                    lockRows: false,
                    token)
                ?? throw new RecordingDraftAutosaveException(
                    "catalog.recording.autosave.not-found",
                    "No existe una grabación editorial editable con ese identificador."),
            cancellationToken);
    }

    public Task<RecordingDraftAutosaveSnapshot> SaveAsync(
        Guid actorAccountId,
        Guid recordingId,
        RecordingDraftAutosaveInput input,
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
        var expected = ParseETag(ifMatch);

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                SaveCoreAsync(
                    connection,
                    transaction,
                    recordingId,
                    prepared,
                    expected,
                    token),
            cancellationToken);
    }

    private static async Task<RecordingDraftAutosaveSnapshot> SaveCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        RecordingDraftAutosaveInput input,
        ExpectedVersions expected,
        CancellationToken cancellationToken)
    {
        var current = await ReadSnapshotAsync(
            connection,
            transaction,
            recordingId,
            lockRows: true,
            cancellationToken)
            ?? throw new RecordingDraftAutosaveException(
                "catalog.recording.autosave.not-found",
                "No existe una grabación editorial editable con ese identificador.");

        if (!string.Equals(
                current.RecordingStatusCode,
                DraftStatusCode,
                StringComparison.Ordinal)
            || !string.Equals(
                current.SourceStatusCode,
                DraftStatusCode,
                StringComparison.Ordinal))
        {
            throw new RecordingDraftAutosaveException(
                "catalog.recording.autosave.not-editable",
                "Solo un borrador de grabación y su fuente en DRAFT pueden autoguardarse.",
                current);
        }

        if (current.RecordingVersion != expected.RecordingVersion
            || current.SourceVersion != expected.SourceVersion)
        {
            throw new RecordingDraftAutosaveException(
                "catalog.recording.autosave.conflict",
                "La grabación cambió desde la lectura anterior. Compara la versión vigente antes de continuar.",
                current);
        }

        var recordingChanged =
            !string.Equals(
                current.RecordingTitle,
                input.RecordingTitle,
                StringComparison.Ordinal)
            || current.RecordingDurationMs != input.RecordingDurationMs;

        var sourceChanged =
            current.SourceDurationMs != input.SourceDurationMs
            || current.OffsetMs != input.OffsetMs;

        var recordingVersion = current.RecordingVersion;
        var sourceVersion = current.SourceVersion;

        if (recordingChanged)
        {
            const string updateRecording = """
                UPDATE catalog.recording
                SET
                    recording_title = @recording_title,
                    duration_ms = @duration_ms,
                    version = version + 1
                WHERE recording_id = @recording_id
                  AND version = @recording_version
                  AND status_code = 'DRAFT'
                RETURNING version;
                """;

            await using var command =
                new NpgsqlCommand(
                    updateRecording,
                    connection,
                    transaction);

            command.Parameters.AddWithValue(
                "recording_id",
                NpgsqlDbType.Uuid,
                recordingId);
            command.Parameters.AddWithValue(
                "recording_version",
                NpgsqlDbType.Bigint,
                expected.RecordingVersion);
            AddNullableText(
                command,
                "recording_title",
                input.RecordingTitle);
            AddNullableInt64(
                command,
                "duration_ms",
                input.RecordingDurationMs);

            var updated =
                await command.ExecuteScalarAsync(cancellationToken);

            if (updated is not long newVersion)
            {
                var latest = await ReadSnapshotAsync(
                    connection,
                    transaction,
                    recordingId,
                    lockRows: false,
                    cancellationToken);

                throw new RecordingDraftAutosaveException(
                    "catalog.recording.autosave.conflict",
                    "Otra edición modificó la grabación antes de confirmar el autoguardado.",
                    latest);
            }

            recordingVersion = newVersion;
        }

        if (sourceChanged)
        {
            const string updateSource = """
                UPDATE catalog.recording_source
                SET
                    duration_ms = @duration_ms,
                    offset_ms = @offset_ms,
                    version = version + 1
                WHERE source_id = @source_id
                  AND recording_id = @recording_id
                  AND version = @source_version
                  AND status_code = 'DRAFT'
                RETURNING version;
                """;

            await using var command =
                new NpgsqlCommand(
                    updateSource,
                    connection,
                    transaction);

            command.Parameters.AddWithValue(
                "source_id",
                NpgsqlDbType.Uuid,
                current.SourceId);
            command.Parameters.AddWithValue(
                "recording_id",
                NpgsqlDbType.Uuid,
                recordingId);
            command.Parameters.AddWithValue(
                "source_version",
                NpgsqlDbType.Bigint,
                expected.SourceVersion);
            AddNullableInt64(
                command,
                "duration_ms",
                input.SourceDurationMs);
            command.Parameters.AddWithValue(
                "offset_ms",
                NpgsqlDbType.Bigint,
                input.OffsetMs);

            var updated =
                await command.ExecuteScalarAsync(cancellationToken);

            if (updated is not long newVersion)
            {
                var latest = await ReadSnapshotAsync(
                    connection,
                    transaction,
                    recordingId,
                    lockRows: false,
                    cancellationToken);

                throw new RecordingDraftAutosaveException(
                    "catalog.recording.autosave.conflict",
                    "Otra edición modificó la fuente antes de confirmar el autoguardado.",
                    latest);
            }

            sourceVersion = newVersion;
        }

        return current with
        {
            RecordingTitle = input.RecordingTitle,
            RecordingDurationMs = input.RecordingDurationMs,
            SourceDurationMs = input.SourceDurationMs,
            OffsetMs = input.OffsetMs,
            RecordingVersion = recordingVersion,
            SourceVersion = sourceVersion
        };
    }

    private static async Task<RecordingDraftAutosaveSnapshot?> ReadSnapshotAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        bool lockRows,
        CancellationToken cancellationToken)
    {
        var recording = await ReadRecordingAsync(
            connection,
            transaction,
            recordingId,
            lockRows,
            cancellationToken);

        if (recording is null)
        {
            return null;
        }

        var source = await ReadSourceAsync(
            connection,
            transaction,
            recordingId,
            lockRows,
            cancellationToken);

        if (source is null)
        {
            return null;
        }

        return new RecordingDraftAutosaveSnapshot(
            recordingId,
            source.SourceId,
            recording.RecordingTitle,
            recording.DurationMs,
            source.DurationMs,
            source.OffsetMs,
            recording.StatusCode,
            source.StatusCode,
            recording.Version,
            source.Version);
    }

    private static async Task<RecordingRow?> ReadRecordingAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        bool lockRow,
        CancellationToken cancellationToken)
    {
        var sql = """
            SELECT
                recording_title,
                duration_ms,
                status_code,
                version
            FROM catalog.recording
            WHERE recording_id = @recording_id
            """
            + (lockRow ? "\nFOR UPDATE;" : ";");

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
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new RecordingRow(
            reader.IsDBNull(0) ? null : reader.GetString(0),
            reader.IsDBNull(1) ? null : reader.GetInt64(1),
            reader.GetString(2),
            reader.GetInt64(3));
    }

    private static async Task<SourceRow?> ReadSourceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        bool lockRow,
        CancellationToken cancellationToken)
    {
        var sql = """
            SELECT
                source_id,
                duration_ms,
                offset_ms,
                status_code,
                version
            FROM catalog.recording_source
            WHERE recording_id = @recording_id
              AND provider_code = 'YOUTUBE'
            ORDER BY
                CASE WHEN status_code = 'DRAFT' THEN 0 ELSE 1 END,
                version DESC,
                source_id DESC
            LIMIT 1
            """
            + (lockRow ? "\nFOR UPDATE;" : ";");

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
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new SourceRow(
            reader.GetGuid(0),
            reader.IsDBNull(1) ? null : reader.GetInt64(1),
            reader.GetInt64(2),
            reader.GetString(3),
            reader.GetInt64(4));
    }

    private static RecordingDraftAutosaveInput Prepare(
        RecordingDraftAutosaveInput input)
    {
        var title = string.IsNullOrWhiteSpace(input.RecordingTitle)
            ? null
            : input.RecordingTitle.Trim();

        if (title is { Length: > MaxRecordingTitleLength })
        {
            throw new RecordingDraftAutosaveException(
                "catalog.recording.autosave.title.too-long",
                "El título de grabación supera el máximo permitido.");
        }

        ValidateDuration(
            input.RecordingDurationMs,
            "catalog.recording.autosave.recording-duration.invalid",
            "La duración de la grabación debe ser positiva.");
        ValidateDuration(
            input.SourceDurationMs,
            "catalog.recording.autosave.source-duration.invalid",
            "La duración de la fuente debe ser positiva.");

        if (input.OffsetMs < 0)
        {
            throw new RecordingDraftAutosaveException(
                "catalog.recording.autosave.offset.invalid",
                "El desplazamiento de la fuente no puede ser negativo.");
        }

        return input with
        {
            RecordingTitle = title
        };
    }

    private static void ValidateDuration(
        long? duration,
        string code,
        string message)
    {
        if (duration is <= 0)
        {
            throw new RecordingDraftAutosaveException(
                code,
                message);
        }
    }

    private static ExpectedVersions ParseETag(
        string ifMatch)
    {
        if (string.IsNullOrWhiteSpace(ifMatch))
        {
            throw new RecordingDraftAutosaveException(
                "catalog.recording.autosave.precondition-required",
                "El autoguardado requiere la versión leída mediante If-Match.");
        }

        var match = ETagPattern().Match(ifMatch.Trim());

        if (!match.Success
            || !long.TryParse(
                match.Groups["recording"].Value,
                out var recordingVersion)
            || !long.TryParse(
                match.Groups["source"].Value,
                out var sourceVersion))
        {
            throw new RecordingDraftAutosaveException(
                "catalog.recording.autosave.etag.invalid",
                "El ETag editorial no tiene un formato válido.");
        }

        return new ExpectedVersions(
            recordingVersion,
            sourceVersion);
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
            throw new RecordingDraftAutosaveException(
                "catalog.recording.autosave.recording.invalid",
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

    private static void AddNullableInt64(
        NpgsqlCommand command,
        string name,
        long? value)
    {
        var parameter =
            command.Parameters.Add(
                name,
                NpgsqlDbType.Bigint);

        parameter.Value =
            value is null
                ? DBNull.Value
                : value.Value;
    }

    private sealed record ExpectedVersions(
        long RecordingVersion,
        long SourceVersion);

    private sealed record RecordingRow(
        string? RecordingTitle,
        long? DurationMs,
        string StatusCode,
        long Version);

    private sealed record SourceRow(
        Guid SourceId,
        long? DurationMs,
        long OffsetMs,
        string StatusCode,
        long Version);
}
