using System.Collections.ObjectModel;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;
using MusicaAprender.BuildingBlocks.Contracts.Email;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.Queue;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Email.Delivery;

public sealed class EmailDeliveryJobDispatcher
{
    private const int LeaseSeconds = 60;

    private readonly string _connectionString;
    private readonly IEmailSender _emailSender;
    private readonly ReadOnlyCollection<IVersionedEmailTemplate> _templates;

    public EmailDeliveryJobDispatcher(
        IConfiguration configuration,
        IEmailSender emailSender,
        IEnumerable<IVersionedEmailTemplate> templates)
        : this(
            RequireConnectionString(configuration),
            emailSender,
            templates)
    {
    }

    private EmailDeliveryJobDispatcher(
        string connectionString,
        IEmailSender emailSender,
        IEnumerable<IVersionedEmailTemplate> templates)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString);
        ArgumentNullException.ThrowIfNull(emailSender);
        ArgumentNullException.ThrowIfNull(templates);

        _connectionString = connectionString;
        _emailSender = emailSender;

        var materialized = templates.ToArray();

        foreach (var template in materialized)
        {
            EmailCode.RequireCode(
                template.TemplateCode,
                nameof(template.TemplateCode));
            EmailCode.RequireLanguageTag(
                template.LanguageTag,
                nameof(template.LanguageTag));

            if (template.TemplateVersion <= 0)
            {
                throw new InvalidOperationException(
                    "Cada plantilla de correo debe declarar una version mayor que cero.");
            }
        }

        var duplicate = materialized
            .GroupBy(
                static item => CreateTemplateKey(
                    item.TemplateCode,
                    item.TemplateVersion,
                    item.LanguageTag),
                StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault(static group => group.Count() > 1);

        if (duplicate is not null)
        {
            throw new InvalidOperationException(
                "Codigo, version e idioma deben identificar una plantilla de correo unica.");
        }

        _templates = Array.AsReadOnly(materialized);
    }

    public int RegisteredTemplateCount => _templates.Count;

    public static EmailDeliveryJobDispatcher CreateForConnectionString(
        string connectionString,
        IEmailSender emailSender,
        IEnumerable<IVersionedEmailTemplate> templates)
    {
        return new EmailDeliveryJobDispatcher(
            connectionString,
            emailSender,
            templates);
    }

    public Task<EmailDeliveryJobOutcome> DispatchNextAsync(
        CancellationToken cancellationToken = default)
    {
        if (_templates.Count == 0)
        {
            return Task.FromResult(EmailDeliveryJobOutcome.NoWork);
        }

        return DispatchCoreAsync(null, cancellationToken);
    }

    public Task<EmailDeliveryJobOutcome> DispatchJobAsync(
        Guid jobId,
        CancellationToken cancellationToken = default)
    {
        if (jobId == Guid.Empty)
        {
            throw new ArgumentException(
                "JobId no puede ser Guid.Empty.",
                nameof(jobId));
        }

        return DispatchCoreAsync(jobId, cancellationToken);
    }

    private async Task<EmailDeliveryJobOutcome> DispatchCoreAsync(
        Guid? requestedJobId,
        CancellationToken cancellationToken)
    {
        var claim = await ClaimAsync(
            requestedJobId,
            cancellationToken);

        if (claim is null)
        {
            return EmailDeliveryJobOutcome.NoWork;
        }

        EmailDeliveryPayload payload;
        IVersionedEmailTemplate template;
        RenderedEmailMessage rendered;

        try
        {
            payload = EmailDeliveryPayload.Parse(claim.PayloadJson);

            if (payload.DeliveryId != claim.JobId)
            {
                throw new EmailDeliveryException(
                    "EMAIL_JOB_PAYLOAD_MISMATCH");
            }

            template = FindTemplate(payload);

            rendered = await template.RenderAsync(
                payload.ToContext(claim.CorrelationId),
                cancellationToken);

            await _emailSender.SendAsync(
                rendered,
                payload.ToContext(claim.CorrelationId),
                cancellationToken);
        }
        catch (OperationCanceledException)
            when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
#pragma warning disable CA1031 // Frontera de resiliencia: el trabajo debe quedar reintentable y observable.
        catch (Exception exception)
#pragma warning restore CA1031
        {
            var errorCode = GetSafeErrorCode(exception);
            var errorDigest = CreateErrorDigest(
                exception,
                errorCode);

            var terminal =
                claim.AttemptNo >= OutboxRetryPolicy.MaxAttempts;

            TimeSpan? retryDelay = terminal
                ? null
                : OutboxRetryPolicy.CalculateDelay(
                    claim.JobId,
                    claim.AttemptNo);

            DateTime? nextAttemptAt = retryDelay is null
                ? null
                : DateTime.UtcNow + retryDelay.Value;

            await CompleteFailureAsync(
                claim,
                errorCode,
                errorDigest,
                nextAttemptAt,
                terminal,
                cancellationToken);

            EmailDeliveryPayload? safePayload = null;

            try
            {
                safePayload = EmailDeliveryPayload.Parse(
                    claim.PayloadJson);
            }
            catch (InvalidOperationException)
            {
            }

            return new EmailDeliveryJobOutcome(
                terminal
                    ? EmailDeliveryJobOutcomeKind.Review
                    : EmailDeliveryJobOutcomeKind.RetryScheduled,
                claim.JobId,
                claim.CorrelationId,
                claim.AttemptNo,
                safePayload?.TemplateCode,
                safePayload?.TemplateVersion ?? 0,
                errorCode);
        }

        await CompleteSuccessAsync(
            claim,
            cancellationToken);

        return new EmailDeliveryJobOutcome(
            EmailDeliveryJobOutcomeKind.Succeeded,
            claim.JobId,
            claim.CorrelationId,
            claim.AttemptNo,
            payload.TemplateCode,
            payload.TemplateVersion);
    }

    private IVersionedEmailTemplate FindTemplate(
        EmailDeliveryPayload payload)
    {
        var template = _templates.FirstOrDefault(
            candidate =>
                string.Equals(
                    candidate.TemplateCode,
                    payload.TemplateCode,
                    StringComparison.Ordinal)
                && candidate.TemplateVersion == payload.TemplateVersion
                && string.Equals(
                    candidate.LanguageTag,
                    payload.LanguageTag,
                    StringComparison.OrdinalIgnoreCase));

        return template
            ?? throw new EmailDeliveryException(
                "EMAIL_TEMPLATE_UNAVAILABLE");
    }

    private async Task<ClaimedEmailJob?> ClaimAsync(
        Guid? requestedJobId,
        CancellationToken cancellationToken)
    {
        await using var connection =
            new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var transaction =
            await connection.BeginTransactionAsync(cancellationToken);

        const string sql = """
            SELECT
                job_id,
                payload::text,
                attempt_count,
                correlation_id
            FROM ops.background_job
            WHERE job_type = @job_type
              AND (
                    (
                        status_code = 'PENDING'
                        AND scheduled_at <= CURRENT_TIMESTAMP
                    )
                    OR (
                        status_code = 'RETRY_WAIT'
                        AND next_attempt_at IS NOT NULL
                        AND next_attempt_at <= CURRENT_TIMESTAMP
                    )
                    OR (
                        status_code = 'RUNNING'
                        AND next_attempt_at IS NOT NULL
                        AND next_attempt_at <= CURRENT_TIMESTAMP
                    )
                  )
              AND (@requested_job_id IS NULL OR job_id = @requested_job_id)
            ORDER BY
                COALESCE(next_attempt_at, scheduled_at),
                scheduled_at,
                job_id
            LIMIT 1
            FOR UPDATE SKIP LOCKED;
            """;

        await using var select =
            new NpgsqlCommand(sql, connection, transaction);

        select.Parameters.AddWithValue(
            "job_type",
            EmailJobProjectionConsumer.JobType);
        select.Parameters.AddWithValue(
            "requested_job_id",
            NpgsqlDbType.Uuid,
            requestedJobId is null
                ? DBNull.Value
                : requestedJobId.Value);

        await using var reader =
            await select.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            await reader.CloseAsync();
            await transaction.RollbackAsync(cancellationToken);
            return null;
        }

        var jobId = reader.GetGuid(0);
        var payloadJson = reader.GetString(1);
        var attemptNo = checked(reader.GetInt32(2) + 1);
        var correlationId = reader.GetGuid(3);

        await reader.CloseAsync();

        const string claimSql = """
            UPDATE ops.background_job
            SET status_code = 'RUNNING',
                next_attempt_at =
                    CURRENT_TIMESTAMP + make_interval(secs => @lease_seconds)
            WHERE job_id = @job_id;
            """;

        await using var claimCommand =
            new NpgsqlCommand(claimSql, connection, transaction);

        claimCommand.Parameters.AddWithValue(
            "lease_seconds",
            LeaseSeconds);
        claimCommand.Parameters.AddWithValue(
            "job_id",
            jobId);

        await claimCommand.ExecuteNonQueryAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        return new ClaimedEmailJob(
            jobId,
            payloadJson,
            attemptNo,
            correlationId,
            DateTime.UtcNow);
    }

    private async Task CompleteSuccessAsync(
        ClaimedEmailJob claim,
        CancellationToken cancellationToken)
    {
        await CompleteAsync(
            claim,
            "SUCCEEDED",
            "SUCCESS",
            null,
            null,
            null,
            cancellationToken);
    }

    private async Task CompleteFailureAsync(
        ClaimedEmailJob claim,
        string errorCode,
        byte[] errorDigest,
        DateTime? nextAttemptAt,
        bool terminal,
        CancellationToken cancellationToken)
    {
        await CompleteAsync(
            claim,
            terminal ? "REVIEW" : "RETRY_WAIT",
            "FAILURE",
            errorCode,
            errorDigest,
            nextAttemptAt,
            cancellationToken);
    }

    private async Task CompleteAsync(
        ClaimedEmailJob claim,
        string jobStatus,
        string resultCode,
        string? errorCode,
        byte[]? errorDigest,
        DateTime? nextAttemptAt,
        CancellationToken cancellationToken)
    {
        await using var connection =
            new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var transaction =
            await connection.BeginTransactionAsync(cancellationToken);

        const string updateSql = """
            UPDATE ops.background_job
            SET status_code = @status_code,
                next_attempt_at = @next_attempt_at,
                attempt_count = @attempt_no
            WHERE job_id = @job_id
              AND job_type = @job_type
              AND status_code = 'RUNNING';
            """;

        await using var update =
            new NpgsqlCommand(updateSql, connection, transaction);

        update.Parameters.AddWithValue(
            "status_code",
            jobStatus);
        update.Parameters.AddWithValue(
            "next_attempt_at",
            NpgsqlDbType.TimestampTz,
            nextAttemptAt is null
                ? DBNull.Value
                : nextAttemptAt.Value);
        update.Parameters.AddWithValue(
            "attempt_no",
            claim.AttemptNo);
        update.Parameters.AddWithValue(
            "job_id",
            claim.JobId);
        update.Parameters.AddWithValue(
            "job_type",
            EmailJobProjectionConsumer.JobType);

        var affected =
            await update.ExecuteNonQueryAsync(cancellationToken);

        if (affected != 1)
        {
            throw new InvalidOperationException(
                "El trabajo de correo perdio su reclamacion antes de registrar el resultado.");
        }

        const string attemptSql = """
            INSERT INTO ops.job_attempt (
                job_attempt_id,
                job_id,
                attempt_no,
                started_at,
                finished_at,
                result_code,
                error_code,
                error_digest
            )
            VALUES (
                @job_attempt_id,
                @job_id,
                @attempt_no,
                @started_at,
                CURRENT_TIMESTAMP,
                @result_code,
                @error_code,
                @error_digest
            );
            """;

        await using var attempt =
            new NpgsqlCommand(attemptSql, connection, transaction);

        attempt.Parameters.AddWithValue(
            "job_attempt_id",
            Guid.CreateVersion7());
        attempt.Parameters.AddWithValue(
            "job_id",
            claim.JobId);
        attempt.Parameters.AddWithValue(
            "attempt_no",
            claim.AttemptNo);
        attempt.Parameters.AddWithValue(
            "started_at",
            claim.StartedAt);
        attempt.Parameters.AddWithValue(
            "result_code",
            resultCode);
        attempt.Parameters.AddWithValue(
            "error_code",
            NpgsqlDbType.Varchar,
            errorCode is null
                ? DBNull.Value
                : errorCode);
        attempt.Parameters.AddWithValue(
            "error_digest",
            NpgsqlDbType.Bytea,
            errorDigest is null
                ? DBNull.Value
                : errorDigest);

        await attempt.ExecuteNonQueryAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    private static string GetSafeErrorCode(Exception exception)
    {
        return exception is EmailDeliveryException controlled
            ? controlled.ErrorCode
            : "EMAIL_DELIVERY_FAILED";
    }

    private static byte[] CreateErrorDigest(
        Exception exception,
        string errorCode)
    {
        var material =
            $"{exception.GetType().FullName}\n{errorCode}";

        return SHA256.HashData(
            Encoding.UTF8.GetBytes(material));
    }

    private static string CreateTemplateKey(
        string templateCode,
        int templateVersion,
        string languageTag)
    {
        return $"{templateCode}:{templateVersion}:{languageTag}";
    }

    private static string RequireConnectionString(
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var connectionString =
            configuration.GetConnectionString("PostgreSQL");

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException(
                "Falta ConnectionStrings:PostgreSQL para los trabajos de correo.");
        }

        return connectionString;
    }

    private sealed record ClaimedEmailJob(
        Guid JobId,
        string PayloadJson,
        int AttemptNo,
        Guid CorrelationId,
        DateTime StartedAt);
}
