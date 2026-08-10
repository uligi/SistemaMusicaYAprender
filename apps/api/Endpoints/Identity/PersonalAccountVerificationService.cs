using System.Text.Json;
using MusicaAprender.BuildingBlocks.Contracts.Email;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.Queue;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;
using MusicaAprender.Modules.Identity.Application.Consent;
using MusicaAprender.Modules.Security.Infrastructure.Registration;
using MusicaAprender.Modules.Security.Infrastructure.Verification;

namespace MusicaAprender.Api.Endpoints.Identity;

public sealed class PersonalAccountVerificationService(
    IRlsTransactionExecutor transactionExecutor,
    IReliableOperationExecutor reliableOperationExecutor,
    ITransactionalEmailEnqueuer emailEnqueuer,
    PersonalEmailProtector emailProtector,
    AccountVerificationTokenService tokenService)
{
    private const string AnonymousRole = "ANONYMOUS";
    private const string ResendOperationCode = "IDENTITY.PERSONAL_ACCOUNT.VERIFICATION_RESEND";
    private static readonly TimeSpan IdempotencyRetention = TimeSpan.FromHours(24);
    private static readonly JsonSerializerOptions JsonOptions =
        new(JsonSerializerDefaults.Web);
    private static readonly PersonalAccountVerificationResponse VerifiedResponse = new(
        "VERIFIED",
        "La cuenta quedó verificada. El código no puede activar la cuenta nuevamente.");
    private static readonly PersonalAccountVerificationResponse ResendResponse = new(
        "RECEIVED",
        "Si existe una cuenta pendiente para ese correo, enviaremos un código nuevo.");

    public async Task<PersonalAccountVerificationResult> VerifyAsync(
        string? token,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (!tokenService.TryReadToken(token, out var claims)
            || claims is null)
        {
            return PersonalAccountVerificationResult.Invalid();
        }

        var context = DatabaseSessionContext.Create(
            claims.AccountId,
            AnonymousRole,
            correlationId);
        var correlationGuid = IdentityOperationCorrelation.ToGuid(correlationId);
        var requiredConsents = RequiredRegistrationConsentPolicy
            .GetCurrentNotices(DateTimeOffset.UtcNow)
            .Select(static notice => new RequiredAccountVerificationConsent(
                notice.PurposeCode,
                notice.NoticeVersion))
            .ToArray();

        var consumed = await transactionExecutor.ExecuteAsync(
            context,
            (connection, transaction, cancellation) =>
                AccountVerificationPersistence.ConsumeAsync(
                    connection,
                    transaction,
                    claims,
                    requiredConsents,
                    correlationGuid,
                    cancellation),
            cancellationToken);

        return consumed switch
        {
            AccountVerificationConsumeResult.Verified =>
                PersonalAccountVerificationResult.Verified(VerifiedResponse),
            AccountVerificationConsumeResult.AlreadyVerified =>
                PersonalAccountVerificationResult.Verified(VerifiedResponse),
            AccountVerificationConsumeResult.Expired =>
                PersonalAccountVerificationResult.Expired(),
            AccountVerificationConsumeResult.PrerequisitesNotCurrent =>
                PersonalAccountVerificationResult.PrerequisitesNotCurrent(),
            _ => PersonalAccountVerificationResult.Invalid()
        };
    }

    public async Task<PersonalAccountVerificationResendResult> ResendAsync(
        string? email,
        string idempotencyKey,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (!emailProtector.TryProtect(email, out var protectedEmail)
            || protectedEmail is null)
        {
            return PersonalAccountVerificationResendResult.InvalidEmail();
        }

        var provisionalAccountId = Guid.CreateVersion7();
        var provisionalContext = DatabaseSessionContext.Create(
            provisionalAccountId,
            AnonymousRole,
            correlationId);
        var request = ReliableOperationRequest.Create(
            ResendOperationCode,
            idempotencyKey,
            protectedEmail.LookupHash.Span,
            IdempotencyRetention);
        var responseJson = JsonSerializer.Serialize(ResendResponse, JsonOptions);
        var correlationGuid = IdentityOperationCorrelation.ToGuid(correlationId);

        var outcome = await reliableOperationExecutor.ExecuteAnonymousAsync(
            provisionalContext,
            request,
            async (connection, transaction, token) =>
            {
                var accountId =
                    await AccountVerificationPersistence.ResolvePendingAccountAsync(
                        connection,
                        transaction,
                        protectedEmail.LookupHash,
                        token);

                if (accountId is Guid pendingAccountId)
                {
                    var actualContext = DatabaseSessionContext.Create(
                        pendingAccountId,
                        AnonymousRole,
                        correlationId);
                    await RlsTransactionContext.ApplyAsync(
                        connection,
                        transaction,
                        actualContext,
                        token);

                    var verificationId = Guid.CreateVersion7();
                    var tokenHash = tokenService.CreateTokenHash(
                        pendingAccountId,
                        verificationId);

                    await AccountVerificationPersistence.CreateAsync(
                        connection,
                        transaction,
                        pendingAccountId,
                        verificationId,
                        tokenHash,
                        token);

                    await emailEnqueuer.EnqueueAsync(
                        connection,
                        transaction,
                        new EmailQueueRequest(
                            "SECURITY",
                            pendingAccountId,
                            verificationId,
                            AccountVerificationEmailTemplate.Code,
                            AccountVerificationEmailTemplate.Version,
                            AccountVerificationEmailTemplate.Language,
                            correlationGuid),
                        token);
                }

                return ReliableOperationResult.Create(
                    StatusCodes.Status202Accepted,
                    responseJson);
            },
            cancellationToken);

        var response = JsonSerializer.Deserialize<PersonalAccountVerificationResponse>(
                           outcome.ResponseReferenceJson,
                           JsonOptions)
                       ?? throw new InvalidOperationException(
                           "La respuesta idempotente de reenvio no contiene un contrato valido.");

        return PersonalAccountVerificationResendResult.Accepted(response);
    }
}

public enum PersonalAccountVerificationResultKind
{
    Verified,
    Invalid,
    Expired,
    PrerequisitesNotCurrent
}

public sealed record PersonalAccountVerificationResult(
    PersonalAccountVerificationResultKind Kind,
    PersonalAccountVerificationResponse? Response)
{
    public static PersonalAccountVerificationResult Verified(
        PersonalAccountVerificationResponse response) =>
        new(PersonalAccountVerificationResultKind.Verified, response);

    public static PersonalAccountVerificationResult Invalid() =>
        new(PersonalAccountVerificationResultKind.Invalid, Response: null);

    public static PersonalAccountVerificationResult Expired() =>
        new(PersonalAccountVerificationResultKind.Expired, Response: null);

    public static PersonalAccountVerificationResult PrerequisitesNotCurrent() =>
        new(PersonalAccountVerificationResultKind.PrerequisitesNotCurrent, Response: null);
}

public enum PersonalAccountVerificationResendResultKind
{
    Accepted,
    InvalidEmail
}

public sealed record PersonalAccountVerificationResendResult(
    PersonalAccountVerificationResendResultKind Kind,
    PersonalAccountVerificationResponse? Response)
{
    public static PersonalAccountVerificationResendResult Accepted(
        PersonalAccountVerificationResponse response) =>
        new(PersonalAccountVerificationResendResultKind.Accepted, response);

    public static PersonalAccountVerificationResendResult InvalidEmail() =>
        new(PersonalAccountVerificationResendResultKind.InvalidEmail, Response: null);
}
