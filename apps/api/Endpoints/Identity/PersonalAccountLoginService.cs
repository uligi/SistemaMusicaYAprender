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
    private readonly PasswordCredential _dummyCredential;

    public PersonalAccountLoginService(
        IRlsTransactionExecutor transactionExecutor,
        PersonalEmailProtector emailProtector,
        Argon2idPasswordHasher passwordHasher)
    {
        _transactionExecutor = transactionExecutor;
        _emailProtector = emailProtector;
        _dummyCredential = passwordHasher.CreateCredential(DummyPassword);
    }

    public async Task<PersonalAccountLoginResult> AuthenticateAsync(
        string? email,
        string? password,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        var emailIsValid = _emailProtector.TryProtect(email, out var protectedEmail)
                           && protectedEmail is not null;
        var lookupHash = emailIsValid
            ? protectedEmail!.LookupHash
            : new ReadOnlyMemory<byte>(new byte[32]);

        var provisionalContext = DatabaseSessionContext.Create(
            Guid.CreateVersion7(),
            SecuritySessionPolicy.AnonymousRoleCode,
            correlationId);

        var credential = await _transactionExecutor.ExecuteAsync(
            provisionalContext,
            (connection, transaction, token) =>
                SecurityLoginPersistence.ResolveActiveCredentialAsync(
                    connection,
                    transaction,
                    lookupHash,
                    token),
            cancellationToken);

        var passwordIsUsable = TryNormalizePassword(password, out var normalizedPassword);
        var credentialToVerify = emailIsValid && passwordIsUsable && credential is not null
            ? credential
            : new ActivePasswordCredential(
                Guid.Empty,
                _dummyCredential.Hash,
                _dummyCredential.Algorithm,
                _dummyCredential.Parameters);
        var candidate = passwordIsUsable ? normalizedPassword! : DummyPassword;

        var verified = Argon2idPasswordHasher.Verify(
            candidate,
            credentialToVerify.Algorithm,
            credentialToVerify.Hash,
            credentialToVerify.Parameters);

        return verified && credential is not null && emailIsValid && passwordIsUsable
            ? PersonalAccountLoginResult.Authenticated(credential.AccountId)
            : PersonalAccountLoginResult.Rejected();
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

public sealed record PersonalAccountLoginResult(
    bool IsAuthenticated,
    Guid AccountId)
{
    public static PersonalAccountLoginResult Authenticated(Guid accountId) =>
        new(true, accountId);

    public static PersonalAccountLoginResult Rejected() =>
        new(false, Guid.Empty);
}
