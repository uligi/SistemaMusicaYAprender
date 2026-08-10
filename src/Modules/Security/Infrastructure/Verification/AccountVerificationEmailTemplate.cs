using Microsoft.Extensions.Configuration;
using MusicaAprender.BuildingBlocks.Contracts.Email;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.Delivery;
using MusicaAprender.Modules.Security.Infrastructure.Registration;
using Npgsql;

namespace MusicaAprender.Modules.Security.Infrastructure.Verification;

public sealed class AccountVerificationEmailTemplate(
    string connectionString,
    PersonalEmailProtector emailProtector,
    AccountVerificationTokenService tokenService)
    : IVersionedEmailTemplate
{
    public const string Code = "PERSONAL_ACCOUNT_VERIFICATION";
    public const int Version = 1;
    public const string Language = "es";

    private readonly string _connectionString =
        !string.IsNullOrWhiteSpace(connectionString)
            ? connectionString
            : throw new ArgumentException(
                "La plantilla requiere una conexion PostgreSQL.",
                nameof(connectionString));
    private readonly PersonalEmailProtector _emailProtector =
        emailProtector ?? throw new ArgumentNullException(nameof(emailProtector));
    private readonly AccountVerificationTokenService _tokenService =
        tokenService ?? throw new ArgumentNullException(nameof(tokenService));

    public string TemplateCode => Code;

    public int TemplateVersion => Version;

    public string LanguageTag => Language;

    public static AccountVerificationEmailTemplate FromConfiguration(
        IConfiguration configuration,
        PersonalEmailProtector emailProtector,
        AccountVerificationTokenService tokenService)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var connectionString = configuration.GetConnectionString("PostgreSQL");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException(
                "Falta ConnectionStrings:PostgreSQL para la plantilla de verificacion.");
        }

        return new AccountVerificationEmailTemplate(
            connectionString,
            emailProtector,
            tokenService);
    }

    public async Task<RenderedEmailMessage> RenderAsync(
        EmailDeliveryContext context,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);

        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        const string sql = """
            SELECT account.email_cipher
            FROM security.account_verification AS verification
            INNER JOIN security.account AS account
                ON account.account_id = verification.account_id
            WHERE verification.verification_id = @verification_id
              AND verification.account_id = @account_id
              AND verification.consumed_at IS NULL
              AND verification.expires_at > CURRENT_TIMESTAMP
              AND account.status_code = 'PENDING'
              AND account.verified_at IS NULL;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("verification_id", context.DeliveryReference);
        command.Parameters.AddWithValue("account_id", context.AggregateId);

        var value = await command.ExecuteScalarAsync(cancellationToken);
        if (value is not byte[] emailCipher)
        {
            throw new EmailDeliveryException(
                "ACCOUNT_VERIFICATION_NOT_DELIVERABLE");
        }

        var recipient = _emailProtector.Unprotect(emailCipher);
        var token = _tokenService.CreateToken(
            context.AggregateId,
            context.DeliveryReference);

        var subject =
            $"[BL025][ACCOUNT_VERIFICATION:v1] {context.DeliveryReference:N}";
        var body =
            $"""
            Verifica tu cuenta de Musica y Aprender.

            Copia este codigo de un solo uso:

            {token}

            Abre /verificar-cuenta e introduce el codigo manualmente. El codigo vence 30 minutos despues de su emision. No lo compartas ni lo guardes en una URL.
            """;

        return new RenderedEmailMessage(
            recipient,
            subject,
            body);
    }
}
