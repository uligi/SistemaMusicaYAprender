using System.Text.Json;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;
using MusicaAprender.Modules.Identity.Application.Consent;
using MusicaAprender.Modules.Identity.Infrastructure.Registration;
using MusicaAprender.Modules.Security.Infrastructure.Registration;

namespace MusicaAprender.Api.Endpoints.Identity;

public sealed class PersonalAccountRegistrationService(
    IReliableOperationExecutor reliableOperationExecutor,
    PersonalEmailProtector emailProtector)
{
    private const string OperationCode = "IDENTITY.PERSONAL_ACCOUNT.REGISTER";
    private const string AnonymousRole = "ANONYMOUS";
    private static readonly TimeSpan IdempotencyRetention = TimeSpan.FromHours(24);
    private static readonly JsonSerializerOptions ResponseJsonOptions =
        new(JsonSerializerDefaults.Web);
    private static readonly PersonalAccountRegistrationResponse AcceptedResponse = new(
        "RECEIVED",
        "La solicitud fue recibida. El resultado no confirma si el correo ya estaba registrado.");

    public async Task<PersonalAccountRegistrationResult> RegisterAsync(
        string? email,
        IReadOnlyList<PersonalAccountRegistrationConsentRequest>? consents,
        string idempotencyKey,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (!emailProtector.TryProtect(email, out var protectedEmail)
            || protectedEmail is null)
        {
            return PersonalAccountRegistrationResult.InvalidEmail();
        }

        var validation = RequiredRegistrationConsentPolicy.Validate(
            consents?.Select(static consent => new RegistrationConsentSubmission(
                    consent.PurposeCode,
                    consent.NoticeVersion,
                    consent.Decision))
                .ToArray(),
            DateTimeOffset.UtcNow);

        if (!validation.IsValid)
        {
            return PersonalAccountRegistrationResult.InvalidConsents(validation.Error);
        }

        var proposedAccountId = Guid.CreateVersion7();
        var provisionalContext = DatabaseSessionContext.Create(
            proposedAccountId,
            AnonymousRole,
            correlationId);
        var reliableRequest = ReliableOperationRequest.Create(
            OperationCode,
            idempotencyKey,
            CreateCanonicalRequest(protectedEmail, validation.AcceptedConsents),
            IdempotencyRetention);
        var responseJson = JsonSerializer.Serialize(AcceptedResponse, ResponseJsonOptions);

        var outcome = await reliableOperationExecutor.ExecuteAnonymousAsync(
            provisionalContext,
            reliableRequest,
            async (connection, transaction, token) =>
            {
                var created = await SecurityAccountRegistrationWriter.TryCreatePendingAsync(
                    connection,
                    transaction,
                    proposedAccountId,
                    protectedEmail,
                    token);

                if (created)
                {
                    await IdentityProfileRegistrationWriter.CreateMinimalAsync(
                        connection,
                        transaction,
                        proposedAccountId,
                        token);

                    await IdentityConsentRegistrationWriter.CreateAcceptedAsync(
                        connection,
                        transaction,
                        proposedAccountId,
                        validation.AcceptedConsents,
                        token);
                }

                return ReliableOperationResult.Create(
                    StatusCodes.Status202Accepted,
                    responseJson);
            },
            cancellationToken);

        var response = JsonSerializer.Deserialize<PersonalAccountRegistrationResponse>(
                           outcome.ResponseReferenceJson,
                           ResponseJsonOptions)
                       ?? throw new InvalidOperationException(
                           "La respuesta idempotente de registro no contiene un contrato valido.");

        return PersonalAccountRegistrationResult.Accepted(response);
    }

    private static byte[] CreateCanonicalRequest(
        ProtectedEmail protectedEmail,
        IReadOnlyList<AcceptedRegistrationConsent> consents) =>
        JsonSerializer.SerializeToUtf8Bytes(
            new CanonicalRegistrationRequest(
                Convert.ToHexString(protectedEmail.LookupHash.Span),
                consents.Select(static consent => new CanonicalRegistrationConsent(
                        consent.PurposeCode,
                        consent.NoticeVersion,
                        consent.Decision))
                    .ToArray()),
            ResponseJsonOptions);

    private sealed record CanonicalRegistrationRequest(
        string EmailLookupHash,
        IReadOnlyList<CanonicalRegistrationConsent> Consents);

    private sealed record CanonicalRegistrationConsent(
        string PurposeCode,
        string NoticeVersion,
        bool Decision);
}

public enum PersonalAccountRegistrationResultKind
{
    Accepted,
    InvalidEmail,
    InvalidConsents
}

public sealed record PersonalAccountRegistrationResult(
    PersonalAccountRegistrationResultKind Kind,
    PersonalAccountRegistrationResponse? Response,
    RegistrationConsentValidationError ConsentError)
{
    public static PersonalAccountRegistrationResult Accepted(
        PersonalAccountRegistrationResponse response) =>
        new(
            PersonalAccountRegistrationResultKind.Accepted,
            response,
            RegistrationConsentValidationError.None);

    public static PersonalAccountRegistrationResult InvalidEmail() =>
        new(
            PersonalAccountRegistrationResultKind.InvalidEmail,
            Response: null,
            RegistrationConsentValidationError.None);

    public static PersonalAccountRegistrationResult InvalidConsents(
        RegistrationConsentValidationError error) =>
        new(
            PersonalAccountRegistrationResultKind.InvalidConsents,
            Response: null,
            error);
}
