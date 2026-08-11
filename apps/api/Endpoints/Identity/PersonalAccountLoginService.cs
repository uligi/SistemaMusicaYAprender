using System.Security.Cryptography;
using System.Text;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.Modules.Security.Infrastructure.Authentication;
using MusicaAprender.Modules.Security.Infrastructure.Credentials;
using MusicaAprender.Modules.Security.Infrastructure.Registration;

namespace MusicaAprender.Api.Endpoints.Identity;

public sealed class PersonalAccountLoginService
{
    private const string DummyPassword = "Credencial uniforme no reutilizable 2026";
    private readonly IRlsTransactionExecutor _transactionExecutor;
    private readonly PersonalEmailProtector _emailProtector;
    private readonly LoginAbuseFingerprintService _abuseFingerprintService;
    private readonly LoginAbusePolicy _abusePolicy;
    private readonly PasswordCredential _dummyCredential;

    public PersonalAccountLoginService(
        IRlsTransactionExecutor transactionExecutor,
        PersonalEmailProtector emailProtector,
        LoginAbuseFingerprintService abuseFingerprintService,
        LoginAbusePolicy abusePolicy,
        Argon2idPasswordHasher passwordHasher)
    {
        _transactionExecutor = transactionExecutor;
        _emailProtector = emailProtector;
        _abuseFingerprintService = abuseFingerprintService;
        _abusePolicy = abusePolicy;
        _dummyCredential = passwordHasher.CreateCredential(DummyPassword);
    }

    public async Task<PersonalAccountLoginResult> AuthenticateAsync(
        string? email,
        string? password,
        string clientAddress,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        var emailIsValid = _emailProtector.TryProtect(email, out var protectedEmail)
                           && protectedEmail is not null;
        var lookupHash = emailIsValid
            ? protectedEmail!.LookupHash
            : new ReadOnlyMemory<byte>(new byte[32]);

        var accountFingerprint = _abuseFingerprintService.CreateAccountFingerprint(
            lookupHash.Span);
        var clientFingerprint = _abuseFingerprintService.CreateClientFingerprint(
            clientAddress);

        try
        {
            var provisionalContext = DatabaseSessionContext.Create(
                Guid.CreateVersion7(),
                SecuritySessionPolicy.AnonymousRoleCode,
                correlationId);

            var result = await _transactionExecutor.ExecuteAsync(
                provisionalContext,
                async (connection, transaction, token) =>
                {
                    await LoginAbusePersistence.AcquireAttemptLocksAsync(
                        connection,
                        transaction,
                        accountFingerprint,
                        clientFingerprint,
                        token);

                    var abuseState = await LoginAbusePersistence.EvaluateAsync(
                        connection,
                        transaction,
                        accountFingerprint,
                        clientFingerprint,
                        _abusePolicy,
                        token);

                    if (abuseState.IsLimited)
                    {
                        await LoginAbusePersistence.RecordRateLimitedAsync(
                            connection,
                            transaction,
                            clientFingerprint,
                            correlationId,
                            token);

                        return PersonalAccountLoginResult.RateLimited(
                            abuseState.RetryAfterSeconds);
                    }

                    var credential = await SecurityLoginPersistence.ResolveActiveCredentialAsync(
                        connection,
                        transaction,
                        lookupHash,
                        token);

                    var passwordIsUsable = TryNormalizePassword(
                        password,
                        out var normalizedPassword);
                    var credentialToVerify =
                        emailIsValid && passwordIsUsable && credential is not null
                            ? credential
                            : new ActivePasswordCredential(
                                Guid.Empty,
                                _dummyCredential.Hash,
                                _dummyCredential.Algorithm,
                                _dummyCredential.Parameters);
                    var candidate = passwordIsUsable
                        ? normalizedPassword!
                        : DummyPassword;

                    var verified = Argon2idPasswordHasher.Verify(
                        candidate,
                        credentialToVerify.Algorithm,
                        credentialToVerify.Hash,
                        credentialToVerify.Parameters);

                    if (!verified
                        || credential is null
                        || !emailIsValid
                        || !passwordIsUsable)
                    {
                        await LoginAbusePersistence.RecordFailureAsync(
                            connection,
                            transaction,
                            accountFingerprint,
                            clientFingerprint,
                            correlationId,
                            token);

                        return PersonalAccountLoginResult.Rejected();
                    }

                    await LoginAbusePersistence.RecordSuccessAsync(
                        connection,
                        transaction,
                        accountFingerprint,
                        correlationId,
                        token);

                    return PersonalAccountLoginResult.Authenticated(
                        credential.AccountId);
                },
                cancellationToken);

            return result;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(accountFingerprint);
            CryptographicOperations.ZeroMemory(clientFingerprint);
        }
    }

    private static bool TryNormalizePassword(string? password, out string? normalized)
    {
        normalized = null;
        if (string.IsNullOrEmpty(password) || password.Length > 512)
        {
            return false;
        }

        try
        {
            normalized = password.Normalize(NormalizationForm.FormC);
        }
        catch (ArgumentException)
        {
            return false;
        }

        var length = normalized.EnumerateRunes().Count();
        return length is >= 15 and <= 128;
    }
}

public enum PersonalAccountLoginResultKind
{
    Authenticated,
    Rejected,
    RateLimited
}

public sealed record PersonalAccountLoginResult(
    PersonalAccountLoginResultKind Kind,
    Guid AccountId,
    int RetryAfterSeconds)
{
    public static PersonalAccountLoginResult Authenticated(Guid accountId) =>
        new(PersonalAccountLoginResultKind.Authenticated, accountId, 0);

    public static PersonalAccountLoginResult Rejected() =>
        new(PersonalAccountLoginResultKind.Rejected, Guid.Empty, 0);

    public static PersonalAccountLoginResult RateLimited(int retryAfterSeconds) =>
        new(
            PersonalAccountLoginResultKind.RateLimited,
            Guid.Empty,
            Math.Max(1, retryAfterSeconds));
}
