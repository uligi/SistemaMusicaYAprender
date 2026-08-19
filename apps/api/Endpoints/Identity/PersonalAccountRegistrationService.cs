using System.Security.Cryptography;
using System.Text.Json;
using MusicaAprender.BuildingBlocks.Contracts.Email;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.Queue;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;
using MusicaAprender.Modules.Identity.Application.Consent;
using MusicaAprender.Modules.Identity.Application.Profile;
using MusicaAprender.Modules.Identity.Infrastructure.Preferences;
using MusicaAprender.Modules.Identity.Infrastructure.Registration;
using MusicaAprender.Modules.Security.Infrastructure.Audit;
using MusicaAprender.Modules.Security.Infrastructure.Credentials;
using MusicaAprender.Modules.Security.Infrastructure.Registration;
using MusicaAprender.Modules.Security.Infrastructure.Verification;

namespace MusicaAprender.Api.Endpoints.Identity;

public sealed class PersonalAccountRegistrationService(
    IReliableOperationExecutor reliableOperationExecutor,
    ITransactionalEmailEnqueuer emailEnqueuer,
    PersonalEmailProtector emailProtector,
    PasswordRequestFingerprintService passwordFingerprintService,
    Argon2idPasswordHasher passwordHasher,
    AccountVerificationTokenService tokenService)
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
        string? username,
        string? email,
        string? password,
        IReadOnlyList<PersonalAccountRegistrationConsentRequest>? consents,
        string idempotencyKey,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        var usernameValidation = UsernamePolicy.Validate(username);
        if (!usernameValidation.IsValid
            || usernameValidation.NormalizedUsername is null)
        {
            return PersonalAccountRegistrationResult.InvalidUsername(
                usernameValidation.Error);
        }

        var normalizedUsername =
            usernameValidation.NormalizedUsername;

        if (!emailProtector.TryProtect(email, out var protectedEmail)
            || protectedEmail is null)
        {
            return PersonalAccountRegistrationResult.InvalidEmail();
        }

        var passwordValidation = PasswordPolicy.Validate(password);
        if (!passwordValidation.IsValid
            || passwordValidation.NormalizedPassword is null)
        {
            return PersonalAccountRegistrationResult.InvalidPassword(passwordValidation.Error);
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
        var reliableRequest = CreateReliableRequest(
            normalizedUsername,
            protectedEmail,
            passwordValidation.NormalizedPassword,
            validation.AcceptedConsents,
            idempotencyKey);
        var responseJson = JsonSerializer.Serialize(AcceptedResponse, ResponseJsonOptions);
        var correlationGuid = IdentityOperationCorrelation.ToGuid(correlationId);

        ReliableOperationOutcome outcome;

        try
        {
            outcome = await reliableOperationExecutor.ExecuteAnonymousAsync(
                provisionalContext,
                reliableRequest,
                async (connection, transaction, token) =>
                {
                    var credential = passwordHasher.CreateCredential(
                        passwordValidation.NormalizedPassword);
                    var created = await SecurityAccountRegistrationWriter.TryCreatePendingAsync(
                        connection,
                        transaction,
                        proposedAccountId,
                        protectedEmail,
                        credential,
                        token);

                    if (created)
                    {
                        await IdentityProfileRegistrationWriter.CreateMinimalAsync(
                            connection,
                            transaction,
                            proposedAccountId,
                            normalizedUsername,
                            token);

                        var preferencesCreated =
                            await PersonalPreferenceService.TryCreateInitialAsync(
                                connection,
                                transaction,
                                proposedAccountId,
                                token);

                        if (!preferencesCreated)
                        {
                            throw new InvalidOperationException(
                                "La cuenta nueva ya contiene una cabeza de preferencias inesperada.");
                        }

                        await IdentityConsentRegistrationWriter.CreateAcceptedAsync(
                            connection,
                            transaction,
                            proposedAccountId,
                            validation.AcceptedConsents,
                            token);

                        var verificationId = Guid.CreateVersion7();
                        var verificationTokenHash = tokenService.CreateTokenHash(
                            proposedAccountId,
                            verificationId);

                        await AccountVerificationPersistence.CreateAsync(
                            connection,
                            transaction,
                            proposedAccountId,
                            verificationId,
                            verificationTokenHash,
                            token);

                        await emailEnqueuer.EnqueueAsync(
                            connection,
                            transaction,
                            new EmailQueueRequest(
                                "SECURITY",
                                proposedAccountId,
                                verificationId,
                                AccountVerificationEmailTemplate.Code,
                                AccountVerificationEmailTemplate.Version,
                                AccountVerificationEmailTemplate.Language,
                                correlationGuid),
                            token);

                        await PrimaryAuditWriter.WriteSecurityEventAsync(
                            connection,
                            transaction,
                            proposedAccountId,
                            "ACCOUNT_REGISTRATION",
                            "SUCCEEDED",
                            correlationId,
                            cancellationToken: token);
                    }
                    else
                    {
                        await PrimaryAuditWriter.WriteSecurityEventAsync(
                            connection,
                            transaction,
                            accountId: null,
                            eventType: "ACCOUNT_REGISTRATION",
                            resultCode: "RECEIVED_OR_EXISTING",
                            correlationId: correlationId,
                            clientFingerprint: protectedEmail.LookupHash,
                            cancellationToken: token);
                    }

                    return ReliableOperationResult.Create(
                        StatusCodes.Status202Accepted,
                        responseJson);
                },
                        cancellationToken);
        }
        catch (UsernameUnavailableException)
        {
            return PersonalAccountRegistrationResult.InvalidUsername(
                UsernameValidationError.Unavailable);
        }

        var response = JsonSerializer.Deserialize<PersonalAccountRegistrationResponse>(
                   outcome.ResponseReferenceJson,
                   ResponseJsonOptions)
               ?? throw new InvalidOperationException(
                   "La respuesta idempotente de registro no contiene un contrato valido.");

        return PersonalAccountRegistrationResult.Accepted(response);
    }

    private ReliableOperationRequest CreateReliableRequest(
        string normalizedUsername,
        ProtectedEmail protectedEmail,
        string normalizedPassword,
        IReadOnlyList<AcceptedRegistrationConsent> consents,
        string idempotencyKey)
    {
        var passwordFingerprint = passwordFingerprintService.CreateFingerprint(
            normalizedPassword);
        byte[]? canonicalRequest = null;

        try
        {
            canonicalRequest = CreateCanonicalRequest(
                normalizedUsername,
                protectedEmail,
                passwordFingerprint,
                consents);

            return ReliableOperationRequest.Create(
                OperationCode,
                idempotencyKey,
                canonicalRequest,
                IdempotencyRetention);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(passwordFingerprint);
            if (canonicalRequest is not null)
            {
                CryptographicOperations.ZeroMemory(canonicalRequest);
            }
        }
    }

    private static byte[] CreateCanonicalRequest(
        string normalizedUsername,
        ProtectedEmail protectedEmail,
        byte[] passwordFingerprint,
        IReadOnlyList<AcceptedRegistrationConsent> consents) =>
        JsonSerializer.SerializeToUtf8Bytes(
            new CanonicalRegistrationRequest(
                normalizedUsername,
                Convert.ToHexString(protectedEmail.LookupHash.Span),
                passwordFingerprint,
                consents.Select(static consent => new CanonicalRegistrationConsent(
                        consent.PurposeCode,
                        consent.NoticeVersion,
                        consent.Decision))
                    .ToArray()),
            ResponseJsonOptions);

    private sealed record CanonicalRegistrationRequest(
        string Username,
        string EmailLookupHash,
        byte[] PasswordFingerprint,
        IReadOnlyList<CanonicalRegistrationConsent> Consents);

    private sealed record CanonicalRegistrationConsent(
        string PurposeCode,
        string NoticeVersion,
        bool Decision);
}

public enum PersonalAccountRegistrationResultKind
{
    Accepted,
    InvalidUsername,
    InvalidEmail,
    InvalidPassword,
    InvalidConsents
}

public sealed record PersonalAccountRegistrationResult(
    PersonalAccountRegistrationResultKind Kind,
    PersonalAccountRegistrationResponse? Response,
    RegistrationConsentValidationError ConsentError,
    PasswordValidationError PasswordError,
    UsernameValidationError UsernameError)
{
    public static PersonalAccountRegistrationResult Accepted(
        PersonalAccountRegistrationResponse response) =>
        new(
            PersonalAccountRegistrationResultKind.Accepted,
                    response,
                    RegistrationConsentValidationError.None,
                    PasswordValidationError.None,
                    UsernameValidationError.None);

    public static PersonalAccountRegistrationResult InvalidUsername(
        UsernameValidationError error) =>
        new(
            PersonalAccountRegistrationResultKind.InvalidUsername,
            Response: null,
            RegistrationConsentValidationError.None,
            PasswordValidationError.None,
            error);

    public static PersonalAccountRegistrationResult InvalidEmail() =>
new(
    PersonalAccountRegistrationResultKind.InvalidEmail,
            Response: null,
            RegistrationConsentValidationError.None,
            PasswordValidationError.None,
            UsernameValidationError.None);

    public static PersonalAccountRegistrationResult InvalidPassword(
PasswordValidationError error) =>
new(
    PersonalAccountRegistrationResultKind.InvalidPassword,
            Response: null,
            RegistrationConsentValidationError.None,
            error,
            UsernameValidationError.None);

    public static PersonalAccountRegistrationResult InvalidConsents(
RegistrationConsentValidationError error) =>
new(
    PersonalAccountRegistrationResultKind.InvalidConsents,
                Response: null,
                error,
                PasswordValidationError.None,
                UsernameValidationError.None);
}
