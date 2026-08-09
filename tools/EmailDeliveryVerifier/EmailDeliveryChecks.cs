using System.Text.Json;
using MailKit.Security;
using MusicaAprender.BuildingBlocks.Contracts.Email;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.Delivery;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.Queue;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.Smtp;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Inbox;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Outbox;
using Npgsql;

namespace MusicaAprender.EmailDeliveryVerifier;

internal static class EmailDeliveryChecks
{
    public static async Task RunAsync(
        EmailDeliveryVerificationOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        Console.WriteLine(
            "Verificando cola de correo, trabajo reintentable, plantilla versionada y SMTP interno...");

        var aggregateId = Guid.CreateVersion7();
        var deliveryReference = Guid.CreateVersion7();
        var correlationId = Guid.CreateVersion7();

        var queue =
            new TransactionalEmailEnqueuer(
                new TransactionalOutboxWriter());

        EmailQueueReceipt receipt =
            await EnqueueWithoutSmtpAsync(
                options,
                queue,
                aggregateId,
                deliveryReference,
                correlationId);

        await VerifyMinimizedOutboxPayloadAsync(
            options,
            receipt.EventId);

        await ProjectEmailJobAsync(
            options,
            receipt.EventId,
            receipt.DeliveryId);

        await VerifyRetryThenSuccessAsync(
            options,
            receipt.DeliveryId);

        await VerifyMailpitCapturedOnceAsync(
            options,
            receipt.DeliveryId);

        Console.WriteLine(
            "OK: la evidencia sintetica se conserva porque ops.job_attempt es append-only.");

        Console.WriteLine(
            "OK: BL-MVP-017 correo en cola verificado: transaccion no bloqueante, trabajo reintentable, plantilla v1 y SMTP interno.");
    }

    private static async Task<EmailQueueReceipt> EnqueueWithoutSmtpAsync(
        EmailDeliveryVerificationOptions options,
        TransactionalEmailEnqueuer queue,
        Guid aggregateId,
        Guid deliveryReference,
        Guid correlationId)
    {
        await using var connection =
            new NpgsqlConnection(options.ApiConnectionString);

        await connection.OpenAsync();

        await using var transaction =
            await connection.BeginTransactionAsync();

        var request = new EmailQueueRequest(
            "IDENTITY",
            aggregateId,
            deliveryReference,
            SyntheticVerificationEmailTemplate.Code,
            SyntheticVerificationEmailTemplate.Version,
            SyntheticVerificationEmailTemplate.Language,
            correlationId);

        var receipt =
            await queue.EnqueueAsync(
                connection,
                transaction,
                request);

        await transaction.CommitAsync();

        Console.WriteLine(
            "OK: la transaccion que solicita correo confirma solo el outbox y no espera SMTP.");

        return receipt;
    }

    private static async Task VerifyMinimizedOutboxPayloadAsync(
        EmailDeliveryVerificationOptions options,
        Guid eventId)
    {
        await using var connection =
            new NpgsqlConnection(options.WorkerConnectionString);

        await connection.OpenAsync();

        const string sql = """
            SELECT payload::text
            FROM ops.outbox_message
            WHERE event_id = @event_id;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection);

        command.Parameters.AddWithValue(
            "event_id",
            eventId);

        var value =
            await command.ExecuteScalarAsync();

        var payload =
            value as string
            ?? throw new InvalidOperationException(
                "No se encontro el evento de correo en outbox.");

        if (payload.Contains('@', StringComparison.Ordinal)
            || payload.Contains(
                "example.test",
                StringComparison.OrdinalIgnoreCase)
            || payload.Contains(
                "token",
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                "El outbox de correo contiene destinatario, token o material sensible.");
        }

        Console.WriteLine(
            "OK: el outbox conserva solo referencias opacas y la identidad de plantilla; no persiste destinatario ni token.");
    }

    private static async Task ProjectEmailJobAsync(
        EmailDeliveryVerificationOptions options,
        Guid eventId,
        Guid deliveryId)
    {
        var dispatcher =
            OutboxDispatcher.CreateForConnectionString(
                options.WorkerConnectionString,
                new IOutboxConsumer[]
                {
                    new EmailJobProjectionConsumer()
                },
                new InboxConsumerExecutor());

        var outcome =
            await dispatcher.DispatchEventAsync(eventId);

        if (outcome.Kind
            != OutboxDispatchOutcomeKind.Processed)
        {
            throw new InvalidOperationException(
                "El evento de correo no se proyecto como trabajo reintentable.");
        }

        await using var connection =
            new NpgsqlConnection(options.WorkerConnectionString);

        await connection.OpenAsync();

        const string sql = """
            SELECT status_code, attempt_count
            FROM ops.background_job
            WHERE job_id = @job_id
              AND job_type = 'EMAIL_DELIVERY';
            """;

        await using var command =
            new NpgsqlCommand(sql, connection);

        command.Parameters.AddWithValue(
            "job_id",
            deliveryId);

        await using var reader =
            await command.ExecuteReaderAsync();

        if (!await reader.ReadAsync()
            || reader.GetString(0) != "PENDING"
            || reader.GetInt32(1) != 0)
        {
            throw new InvalidOperationException(
                "El trabajo EMAIL_DELIVERY no quedo pendiente y sin intentos.");
        }

        Console.WriteLine(
            "OK: outbox/inbox proyecta exactamente un background_job EMAIL_DELIVERY.");
    }

    private static async Task VerifyRetryThenSuccessAsync(
        EmailDeliveryVerificationOptions options,
        Guid deliveryId)
    {
        var template =
            new SyntheticVerificationEmailTemplate();

        var failingSender =
            new MailKitEmailSender(
                new SmtpOptions(
                    "127.0.0.1",
                    1,
                    "no-reply@musica-aprender.local",
                    "Musica y Aprender",
                    SecureSocketOptions.None,
                    2000));

        var failingDispatcher =
            EmailDeliveryJobDispatcher.CreateForConnectionString(
                options.WorkerConnectionString,
                failingSender,
                new IVersionedEmailTemplate[]
                {
                    template
                });

        var first =
            await failingDispatcher.DispatchJobAsync(deliveryId);

        if (first.Kind
                != EmailDeliveryJobOutcomeKind.RetryScheduled
            || first.AttemptNo != 1)
        {
            throw new InvalidOperationException(
                "El primer fallo SMTP no produjo un reintento observable.");
        }

        await ForceRetryDueAsync(
            options,
            deliveryId);

        var sender =
            new MailKitEmailSender(
                new SmtpOptions(
                    options.SmtpHost,
                    options.SmtpPort,
                    "no-reply@musica-aprender.local",
                    "Musica y Aprender",
                    SecureSocketOptions.None,
                    5000));

        var dispatcher =
            EmailDeliveryJobDispatcher.CreateForConnectionString(
                options.WorkerConnectionString,
                sender,
                new IVersionedEmailTemplate[]
                {
                    template
                });

        var second =
            await dispatcher.DispatchJobAsync(deliveryId);

        if (second.Kind
                != EmailDeliveryJobOutcomeKind.Succeeded
            || second.AttemptNo != 2
            || !string.Equals(
                second.TemplateCode,
                SyntheticVerificationEmailTemplate.Code,
                StringComparison.Ordinal)
            || second.TemplateVersion
                != SyntheticVerificationEmailTemplate.Version)
        {
            throw new InvalidOperationException(
                "El segundo intento SMTP no completo la plantilla versionada esperada.");
        }

        await VerifyAttemptEvidenceAsync(
            options,
            deliveryId);

        Console.WriteLine(
            "OK: fallo SMTP transitorio -> RETRY_WAIT; segundo intento -> SUCCEEDED con evidencia de ambos intentos.");
    }

    private static async Task ForceRetryDueAsync(
        EmailDeliveryVerificationOptions options,
        Guid deliveryId)
    {
        await using var connection =
            new NpgsqlConnection(options.WorkerConnectionString);

        await connection.OpenAsync();

        const string sql = """
            UPDATE ops.background_job
            SET next_attempt_at = CURRENT_TIMESTAMP
            WHERE job_id = @job_id
              AND job_type = 'EMAIL_DELIVERY'
              AND status_code = 'RETRY_WAIT';
            """;

        await using var command =
            new NpgsqlCommand(sql, connection);

        command.Parameters.AddWithValue(
            "job_id",
            deliveryId);

        if (await command.ExecuteNonQueryAsync() != 1)
        {
            throw new InvalidOperationException(
                "No se pudo adelantar el reintento sintetico.");
        }
    }

    private static async Task VerifyAttemptEvidenceAsync(
        EmailDeliveryVerificationOptions options,
        Guid deliveryId)
    {
        await using var connection =
            new NpgsqlConnection(options.WorkerConnectionString);

        await connection.OpenAsync();

        const string sql = """
            SELECT
                j.status_code,
                j.attempt_count,
                COUNT(a.job_attempt_id),
                COUNT(*) FILTER (WHERE a.result_code = 'FAILURE'),
                COUNT(*) FILTER (WHERE a.result_code = 'SUCCESS')
            FROM ops.background_job j
            LEFT JOIN ops.job_attempt a
              ON a.job_id = j.job_id
            WHERE j.job_id = @job_id
            GROUP BY j.status_code, j.attempt_count;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection);

        command.Parameters.AddWithValue(
            "job_id",
            deliveryId);

        await using var reader =
            await command.ExecuteReaderAsync();

        if (!await reader.ReadAsync())
        {
            throw new InvalidOperationException(
                "No se encontro evidencia del trabajo de correo.");
        }

        if (reader.GetString(0) != "SUCCEEDED"
            || reader.GetInt32(1) != 2
            || reader.GetInt64(2) != 2
            || reader.GetInt64(3) != 1
            || reader.GetInt64(4) != 1)
        {
            throw new InvalidOperationException(
                "La evidencia de intentos SMTP no coincide con 1 fallo y 1 exito.");
        }
    }

    private static async Task VerifyMailpitCapturedOnceAsync(
        EmailDeliveryVerificationOptions options,
        Guid deliveryId)
    {
        using var client = new HttpClient
        {
            BaseAddress = options.MailpitApiBase,
            Timeout = TimeSpan.FromSeconds(5)
        };

        using var response =
            await client.GetAsync("api/v1/messages");

        response.EnsureSuccessStatusCode();

        await using var stream =
            await response.Content.ReadAsStreamAsync();

        using var document =
            await JsonDocument.ParseAsync(stream);

        var subject =
            $"[BL017][ACCOUNT_VERIFICATION:v1] {deliveryId:N}";

        var matches =
            CountObjectsWithSubject(
                document.RootElement,
                subject);

        if (matches != 1)
        {
            throw new InvalidOperationException(
                $"Mailpit debia contener exactamente un mensaje sintetico BL-MVP-017 y encontro {matches}.");
        }

        Console.WriteLine(
            "OK: Mailpit capturo exactamente un correo sintetico con plantilla ACCOUNT_VERIFICATION v1.");
    }

    private static int CountObjectsWithSubject(
        JsonElement element,
        string expectedSubject)
    {
        var count = 0;

        if (element.ValueKind == JsonValueKind.Object)
        {
            var matchedCurrentObject = false;

            foreach (var property in element.EnumerateObject())
            {
                if (string.Equals(
                        property.Name,
                        "Subject",
                        StringComparison.OrdinalIgnoreCase)
                    && property.Value.ValueKind
                        == JsonValueKind.String
                    && string.Equals(
                        property.Value.GetString(),
                        expectedSubject,
                        StringComparison.Ordinal))
                {
                    matchedCurrentObject = true;
                }

                count += CountObjectsWithSubject(
                    property.Value,
                    expectedSubject);
            }

            if (matchedCurrentObject)
            {
                count++;
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray())
            {
                count += CountObjectsWithSubject(
                    item,
                    expectedSubject);
            }
        }

        return count;
    }
}
