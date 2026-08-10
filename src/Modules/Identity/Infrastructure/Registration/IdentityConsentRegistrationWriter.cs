using MusicaAprender.Modules.Identity.Application.Consent;
using Npgsql;

namespace MusicaAprender.Modules.Identity.Infrastructure.Registration;

public static class IdentityConsentRegistrationWriter
{
    public static async Task CreateAcceptedAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        IReadOnlyCollection<AcceptedRegistrationConsent> consents,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);
        ArgumentNullException.ThrowIfNull(consents);

        if (consents.Count == 0 || consents.Any(static consent => !consent.Decision))
        {
            throw new ArgumentException(
                "El registro requiere al menos una aceptación afirmativa.",
                nameof(consents));
        }

        const string sql = """
            INSERT INTO identity.consent_record (
                account_id,
                purpose_code,
                notice_version,
                decision,
                decided_at
            )
            VALUES (
                @account_id,
                @purpose_code,
                @notice_version,
                TRUE,
                CURRENT_TIMESTAMP
            );
            """;

        var changed = 0;
        foreach (var consent in consents)
        {
            await using var command = new NpgsqlCommand(sql, connection, transaction);
            command.Parameters.AddWithValue("account_id", accountId);
            command.Parameters.AddWithValue("purpose_code", consent.PurposeCode);
            command.Parameters.AddWithValue("notice_version", consent.NoticeVersion);
            changed += await command.ExecuteNonQueryAsync(cancellationToken);
        }

        if (changed != consents.Count)
        {
            throw new InvalidOperationException(
                "No se pudo conservar exactamente una evidencia por consentimiento obligatorio.");
        }
    }
}
