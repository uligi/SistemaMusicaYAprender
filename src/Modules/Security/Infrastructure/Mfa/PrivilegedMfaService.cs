using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using MusicaAprender.BuildingBlocks.Contracts.ObjectStorage;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.Modules.Security.Infrastructure.Audit;
using MusicaAprender.Modules.Security.Infrastructure.Authentication;
using MusicaAprender.Modules.Security.Infrastructure.Credentials;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Security.Infrastructure.Mfa;

public sealed class PrivilegedMfaService(
    IRlsTransactionExecutor transactionExecutor,
    IObjectStore objectStore)
{
    public const string PolicyVersion = "MFA-POLICY-1";
    public const string MethodType = "TOTP";
    public const string AssuranceLevel = "MFA";
    public const int MaximumAttempts = 5;

    public static readonly TimeSpan EnrollmentChallengeLifetime =
        TimeSpan.FromMinutes(10);

    public static readonly TimeSpan StepUpChallengeLifetime =
        TimeSpan.FromMinutes(5);

    public static readonly TimeSpan RecentAssuranceLifetime =
        TimeSpan.FromMinutes(15);

    private const string EnrollmentOperation = "SECURITY.MFA.ENROLL";
    private const string StepUpOperation = "SECURITY.MFA.STEPUP";
    private const string AssuranceOperation = "SECURITY.MFA.ASSURANCE";
    private const string TotpUseOperation = "SECURITY.MFA.TOTP_USE";
    private static readonly JsonSerializerOptions ChallengeJsonOptions =
        new(JsonSerializerDefaults.Web);

    public async Task<MfaStatus> ReadStatusAsync(
        Guid accountId,
        Guid sessionId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        var context = CreateContext(accountId, correlationId);

        return await transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                var enrolled = await HasActiveTotpAsync(
                    connection,
                    transaction,
                    accountId,
                    token);

                var assurance = await ReadRecentAssuranceAsync(
                    connection,
                    transaction,
                    accountId,
                    sessionId,
                    token);

                return new MfaStatus(
                    enrolled,
                    assurance.Active,
                    enrolled ? MethodType : null,
                    assurance.ExpiresAt);
            },
            cancellationToken);
    }

    public async Task<MfaEnrollmentStarted> BeginEnrollmentAsync(
        Guid accountId,
        Guid sessionId,
        string? currentPassword,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrEmpty(currentPassword)
            || currentPassword.Length > 4096)
        {
            throw MfaAdministrationException.InvalidReauthentication();
        }

        var secret = TotpService.CreateSecret();
        var digest = SHA256.HashData(secret);

        try
        {
            var challengeId = Guid.NewGuid();
            var context = CreateContext(accountId, correlationId);

            var expiresAt = await transactionExecutor.ExecuteAsync(
                context,
                async (connection, transaction, token) =>
                {
                    if (await HasActiveTotpAsync(
                            connection,
                            transaction,
                            accountId,
                            token))
                    {
                        throw new MfaAdministrationException(
                            "security.mfa.already-enrolled",
                            409,
                            "La cuenta ya posee un factor TOTP activo.");
                    }

                    var credential = await ReadCredentialAsync(
                        connection,
                        transaction,
                        accountId,
                        token);

                    if (credential is null
                        || !Argon2idPasswordHasher.Verify(
                            currentPassword,
                            credential.Algorithm,
                            credential.Hash,
                            credential.Parameters))
                    {
                        throw MfaAdministrationException.InvalidReauthentication();
                    }

                    var challengeExpiresAt =
                        await InsertChallengeAsync(
                            connection,
                            transaction,
                            accountId,
                            sessionId,
                            EnrollmentOperation,
                            challengeId,
                            digest,
                            "ENROLL_TOTP",
                            EnrollmentChallengeLifetime,
                            token);

                    await PrimaryAuditWriter.WriteSecurityEventAsync(
                        connection,
                        transaction,
                        accountId,
                        "MFA_ENROLLMENT_CHALLENGE",
                        "ISSUED",
                        correlationId,
                        cancellationToken: token);

                    return challengeExpiresAt;
                },
                cancellationToken);

            var base32 = TotpService.EncodeBase32(secret);
            var issuer = Uri.EscapeDataString("Música y Aprender");
            var label = Uri.EscapeDataString(
                $"Música y Aprender:{accountId:D}");

            var uri =
                $"otpauth://totp/{label}?secret={base32}"
                + $"&issuer={issuer}&algorithm=SHA1"
                + $"&digits={TotpService.Digits}"
                + $"&period={TotpService.PeriodSeconds}";

            return new MfaEnrollmentStarted(
                challengeId,
                base32,
                uri,
                expiresAt);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(secret);
            CryptographicOperations.ZeroMemory(digest);
        }
    }

    public async Task<MfaStatus> ConfirmEnrollmentAsync(
        Guid accountId,
        Guid sessionId,
        Guid challengeId,
        string? base32Secret,
        string? code,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        var secret = TotpService.DecodeBase32(base32Secret);
        if (secret.Length == 0)
        {
            throw MfaAdministrationException.InvalidChallenge();
        }

        var digest = SHA256.HashData(secret);
        StoredObjectDescriptor? stored = null;

        try
        {
            var context = CreateContext(accountId, correlationId);

            var outcome = await transactionExecutor.ExecuteAsync(
                context,
                async (connection, transaction, token) =>
                {
                    await AcquireAccountLockAsync(
                        connection,
                        transaction,
                        accountId,
                        token);

                    var challenge = await LockChallengeAsync(
                        connection,
                        transaction,
                        accountId,
                        EnrollmentOperation,
                        challengeId,
                        token);

                    ValidatePendingChallenge(
                        challenge,
                        sessionId,
                        "ENROLL_TOTP");

                    if (!CryptographicOperations.FixedTimeEquals(
                            challenge.RequestDigest,
                            digest))
                    {
                        var failure = await RegisterFailedAttemptAsync(
                            connection,
                            transaction,
                            challenge,
                            token);

                        await PrimaryAuditWriter.WriteSecurityEventAsync(
                            connection,
                            transaction,
                            accountId,
                            "MFA_ENROLLMENT_CONFIRM",
                            failure.Exhausted ? "THROTTLED" : "REJECTED",
                            correlationId,
                            cancellationToken: token);

                        return ConfirmationOutcome<MfaStatus>.FromError(
                            MfaAdministrationException.InvalidCode(failure.Exhausted));
                    }

                    var verification =
                        TotpService.Verify(secret, code, DateTimeOffset.UtcNow);

                    if (!verification.Valid)
                    {
                        var failure = await RegisterFailedAttemptAsync(
                            connection,
                            transaction,
                            challenge,
                            token);

                        await PrimaryAuditWriter.WriteSecurityEventAsync(
                            connection,
                            transaction,
                            accountId,
                            "MFA_ENROLLMENT_CONFIRM",
                            failure.Exhausted ? "THROTTLED" : "REJECTED",
                            correlationId,
                            cancellationToken: token);

                        return ConfirmationOutcome<MfaStatus>.FromError(
                            MfaAdministrationException.InvalidCode(failure.Exhausted));
                    }

                    if (await HasActiveTotpAsync(
                            connection,
                            transaction,
                            accountId,
                            token))
                    {
                        await ConsumeChallengeAsync(
                            connection,
                            transaction,
                            challenge.IdempotencyId,
                            token);

                        return ConfirmationOutcome<MfaStatus>.FromError(
                            new MfaAdministrationException(
                                "security.mfa.already-enrolled",
                                409,
                                "Otro flujo ya confirmó un factor TOTP para esta cuenta."));
                    }

                    var boundSecret = BindSecretToAccount(
                        accountId,
                        secret);

                    try
                    {
                        await using var source =
                            new MemoryStream(
                                boundSecret,
                                writable: false);

                        try
                        {
                            stored = await objectStore.StoreAsync(
                                MfaSecretReferenceCodec.CreateWriteRequest(source),
                                token);
                        }
                        catch (OperationCanceledException)
                        {
                            throw;
                        }
                        catch (Exception exception)
                        {
                            throw new MfaAdministrationException(
                                "security.mfa.storage.unavailable",
                                503,
                                "No fue posible proteger el secreto del segundo factor.",
                                exception);
                        }
                    }
                    finally
                    {
                        CryptographicOperations.ZeroMemory(boundSecret);
                    }

                    var reference =
                        MfaSecretReferenceCodec.Encode(stored);

                    const string insertMethodSql = """
                        INSERT INTO security.mfa_method (
                            account_id,
                            method_type,
                            secret_ref,
                            enrolled_at,
                            disabled_at
                        )
                        VALUES (
                            @account_id,
                            @method_type,
                            @secret_ref,
                            CURRENT_TIMESTAMP,
                            NULL
                        );
                        """;

                    await using (var methodCommand =
                                 new NpgsqlCommand(
                                     insertMethodSql,
                                     connection,
                                     transaction))
                    {
                        methodCommand.Parameters.AddWithValue(
                            "account_id",
                            accountId);
                        methodCommand.Parameters.AddWithValue(
                            "method_type",
                            MethodType);
                        methodCommand.Parameters.AddWithValue(
                            "secret_ref",
                            reference);

                        await methodCommand.ExecuteNonQueryAsync(token);
                    }

                    await ConsumeChallengeAsync(
                        connection,
                        transaction,
                        challenge.IdempotencyId,
                        token);

                    await PrimaryAuditWriter.WriteSecurityEventAsync(
                        connection,
                        transaction,
                        accountId,
                        "MFA_ENROLLMENT_CONFIRM",
                        "SUCCEEDED",
                        correlationId,
                        cancellationToken: token);

                    return ConfirmationOutcome<MfaStatus>.FromValue(
                        new MfaStatus(
                            true,
                            false,
                            MethodType,
                            null));
                },
                cancellationToken);

            if (outcome.Error is not null)
            {
                throw outcome.Error;
            }

            return outcome.Value
                ?? throw new InvalidOperationException(
                    "La confirmación MFA no produjo un resultado.");
        }
        catch
        {
            if (stored is not null)
            {
                try
                {
                    await objectStore.DeleteAsync(
                        stored,
                        MfaSecretReferenceCodec.AccessContext,
                        CancellationToken.None);
                }
                catch
                {
                    // Preserva la falla original. Si la transacción no confirmó,
                    // security.mfa_method no referencia este objeto.
                }
            }

            throw;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(secret);
            CryptographicOperations.ZeroMemory(digest);
        }
    }

    public async Task<MfaChallengeStarted> BeginStepUpAsync(
        Guid accountId,
        Guid sessionId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        var randomDigest = RandomNumberGenerator.GetBytes(32);
        try
        {
            var context = CreateContext(accountId, correlationId);
            var challengeId = Guid.NewGuid();

            var expiresAt = await transactionExecutor.ExecuteAsync(
                context,
                async (connection, transaction, token) =>
                {
                    if (!await HasActiveTotpAsync(
                            connection,
                            transaction,
                            accountId,
                            token))
                    {
                        throw new MfaAdministrationException(
                            "security.mfa.not-enrolled",
                            409,
                            "La cuenta debe confirmar primero un segundo factor.");
                    }

                    var challengeExpiresAt =
                        await InsertChallengeAsync(
                            connection,
                            transaction,
                            accountId,
                            sessionId,
                            StepUpOperation,
                            challengeId,
                            randomDigest,
                            "PRIVILEGED",
                            StepUpChallengeLifetime,
                            token);

                    await PrimaryAuditWriter.WriteSecurityEventAsync(
                        connection,
                        transaction,
                        accountId,
                        "MFA_STEP_UP_CHALLENGE",
                        "ISSUED",
                        correlationId,
                        cancellationToken: token);

                    return challengeExpiresAt;
                },
                cancellationToken);

            return new MfaChallengeStarted(
                challengeId,
                expiresAt,
                MaximumAttempts);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(randomDigest);
        }
    }

    public async Task<MfaStatus> ConfirmStepUpAsync(
        Guid accountId,
        Guid sessionId,
        Guid challengeId,
        string? code,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        var context = CreateContext(accountId, correlationId);

        var outcome = await transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                await AcquireAccountLockAsync(
                    connection,
                    transaction,
                    accountId,
                    token);

                var challenge = await LockChallengeAsync(
                    connection,
                    transaction,
                    accountId,
                    StepUpOperation,
                    challengeId,
                    token);

                ValidatePendingChallenge(
                    challenge,
                    sessionId,
                    "PRIVILEGED");

                var method = await ReadActiveTotpMethodAsync(
                    connection,
                    transaction,
                    accountId,
                    token);

                if (method is null
                    || !MfaSecretReferenceCodec.TryDecode(
                        method.SecretReference,
                        out var descriptor)
                    || descriptor is null)
                {
                    throw new MfaAdministrationException(
                        "security.mfa.method.unavailable",
                        503,
                        "El segundo factor registrado no puede verificarse de forma segura.");
                }

                byte[] storedPayload;
                await using (var destination = new MemoryStream())
                {
                    try
                    {
                        await objectStore.ReadAsync(
                            descriptor,
                            MfaSecretReferenceCodec.AccessContext,
                            destination,
                            token);
                    }
                    catch (OperationCanceledException)
                    {
                        throw;
                    }
                    catch (Exception exception)
                    {
                        throw new MfaAdministrationException(
                            "security.mfa.storage.unavailable",
                            503,
                            "No fue posible recuperar el segundo factor protegido.",
                            exception);
                    }

                    storedPayload = destination.ToArray();
                }

                var secret = UnbindSecretFromAccount(
                    accountId,
                    storedPayload);
                CryptographicOperations.ZeroMemory(storedPayload);

                try
                {
                    var verification =
                        TotpService.Verify(secret, code, DateTimeOffset.UtcNow);

                    if (!verification.Valid)
                    {
                        var failure = await RegisterFailedAttemptAsync(
                            connection,
                            transaction,
                            challenge,
                            token);

                        await PrimaryAuditWriter.WriteSecurityEventAsync(
                            connection,
                            transaction,
                            accountId,
                            "MFA_STEP_UP_CONFIRM",
                            failure.Exhausted ? "THROTTLED" : "REJECTED",
                            correlationId,
                            cancellationToken: token);

                        return ConfirmationOutcome<MfaStatus>.FromError(
                            MfaAdministrationException.InvalidCode(failure.Exhausted));
                    }

                    await ReserveTotpCounterAsync(
                        connection,
                        transaction,
                        accountId,
                        verification.Counter,
                        token);

                    await ConsumeChallengeAsync(
                        connection,
                        transaction,
                        challenge.IdempotencyId,
                        token);

                    await MarkSessionAssuranceAsync(
                        connection,
                        transaction,
                        accountId,
                        sessionId,
                        token);

                    var expiresAt = await UpsertRecentAssuranceAsync(
                        connection,
                        transaction,
                        accountId,
                        sessionId,
                        token);

                    await PrimaryAuditWriter.WriteSecurityEventAsync(
                        connection,
                        transaction,
                        accountId,
                        "MFA_STEP_UP_CONFIRM",
                        "SUCCEEDED",
                        correlationId,
                        cancellationToken: token);

                    return ConfirmationOutcome<MfaStatus>.FromValue(
                        new MfaStatus(
                            true,
                            true,
                            MethodType,
                            expiresAt));
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(secret);
                }
            },
            cancellationToken);

        if (outcome.Error is not null)
        {
            throw outcome.Error;
        }

        return outcome.Value
            ?? throw new InvalidOperationException(
                "El step-up MFA no produjo un resultado.");
    }

    public async Task<bool> HasRecentPrivilegedAssuranceAsync(
        Guid accountId,
        Guid sessionId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        var context = CreateContext(accountId, correlationId);

        return await transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                var assurance = await ReadRecentAssuranceAsync(
                    connection,
                    transaction,
                    accountId,
                    sessionId,
                    token);

                return assurance.Active;
            },
            cancellationToken);
    }

    private static byte[] BindSecretToAccount(
        Guid accountId,
        ReadOnlySpan<byte> secret)
    {
        var payload = new byte[16 + secret.Length];
        accountId.TryWriteBytes(payload.AsSpan(0, 16));
        secret.CopyTo(payload.AsSpan(16));
        return payload;
    }

    private static byte[] UnbindSecretFromAccount(
        Guid accountId,
        byte[] payload)
    {
        try
        {
            if (payload.Length != 16 + TotpService.SecretLengthBytes)
            {
                throw new MfaAdministrationException(
                    "security.mfa.method.unavailable",
                    503,
                    "El segundo factor registrado no usa el formato privado esperado.");
            }

            var boundAccount = new Guid(payload.AsSpan(0, 16));
            if (boundAccount != accountId)
            {
                throw new MfaAdministrationException(
                    "security.mfa.method.unavailable",
                    503,
                    "El segundo factor registrado no pertenece a esta cuenta.");
            }

            return payload.AsSpan(16).ToArray();
        }
        catch
        {
            CryptographicOperations.ZeroMemory(payload);
            throw;
        }
    }

    private static DatabaseSessionContext CreateContext(
        Guid accountId,
        string correlationId) =>
        DatabaseSessionContext.Create(
            accountId,
            SecuritySessionPolicy.SafeRoleCode,
            correlationId);

    private static async Task AcquireAccountLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT pg_advisory_xact_lock(
                hashtextextended(@account_id::text, 32032)
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("account_id", accountId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<ActiveCredential?> ReadCredentialAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT hash, algorithm, parameters
            FROM security.credential
            WHERE account_id = @account_id
              AND active
            ORDER BY changed_at DESC
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("account_id", accountId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new ActiveCredential(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetString(2));
    }

    private static async Task<bool> HasActiveTotpAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM security.mfa_method
                WHERE account_id = @account_id
                  AND method_type = @method_type
                  AND disabled_at IS NULL
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("account_id", accountId);
        command.Parameters.AddWithValue("method_type", MethodType);

        return (bool)(await command.ExecuteScalarAsync(cancellationToken)
            ?? false);
    }

    private static async Task<ActiveMfaMethod?> ReadActiveTotpMethodAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT secret_ref
            FROM security.mfa_method
            WHERE account_id = @account_id
              AND method_type = @method_type
              AND disabled_at IS NULL
            ORDER BY enrolled_at DESC
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("account_id", accountId);
        command.Parameters.AddWithValue("method_type", MethodType);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new ActiveMfaMethod(
            reader.GetString(0));
    }

    private static async Task<DateTimeOffset> InsertChallengeAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid sessionId,
        string operationCode,
        Guid challengeId,
        ReadOnlyMemory<byte> requestDigest,
        string purpose,
        TimeSpan lifetime,
        CancellationToken cancellationToken)
    {
        var responseReference = JsonSerializer.Serialize(
            new ChallengeState(
                sessionId.ToString("D"),
                purpose,
                0,
                PolicyVersion),
            ChallengeJsonOptions);

        const string sql = """
            INSERT INTO ops.idempotency_record (
                account_id,
                operation_code,
                idempotency_key,
                request_digest,
                response_code,
                response_ref,
                created_at,
                expires_at
            )
            VALUES (
                @account_id,
                @operation_code,
                @idempotency_key,
                @request_digest,
                102,
                @response_ref,
                CURRENT_TIMESTAMP,
                CURRENT_TIMESTAMP + @lifetime
            )
            RETURNING expires_at;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("account_id", accountId);
        command.Parameters.AddWithValue("operation_code", operationCode);
        command.Parameters.AddWithValue(
            "idempotency_key",
            challengeId.ToString("N"));
        command.Parameters.AddWithValue(
            "request_digest",
            NpgsqlDbType.Bytea,
            requestDigest.ToArray());
        command.Parameters.AddWithValue(
            "response_ref",
            NpgsqlDbType.Jsonb,
            responseReference);
        command.Parameters.AddWithValue(
            "lifetime",
            NpgsqlDbType.Interval,
            lifetime);

        var value = await command.ExecuteScalarAsync(cancellationToken);
        return ToOffset(
            value,
            "PostgreSQL no devolvió la expiración del reto MFA.");
    }

    private static async Task<ChallengeRecord> LockChallengeAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        string operationCode,
        Guid challengeId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                idempotency_id,
                request_digest,
                response_code,
                response_ref ->> 'sessionId',
                response_ref ->> 'purpose',
                COALESCE((response_ref ->> 'attempts')::integer, 0),
                response_ref ->> 'policyVersion',
                expires_at,
                expires_at > CURRENT_TIMESTAMP
            FROM ops.idempotency_record
            WHERE account_id = @account_id
              AND operation_code = @operation_code
              AND idempotency_key = @idempotency_key
            FOR UPDATE;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("account_id", accountId);
        command.Parameters.AddWithValue("operation_code", operationCode);
        command.Parameters.AddWithValue(
            "idempotency_key",
            challengeId.ToString("N"));

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw MfaAdministrationException.InvalidChallenge();
        }

        return new ChallengeRecord(
            reader.GetGuid(0),
            (byte[])reader.GetValue(1),
            reader.GetInt32(2),
            reader.IsDBNull(3) ? string.Empty : reader.GetString(3),
            reader.IsDBNull(4) ? string.Empty : reader.GetString(4),
            reader.GetInt32(5),
            reader.IsDBNull(6) ? string.Empty : reader.GetString(6),
            ToOffset(
                reader.GetValue(7),
                "PostgreSQL no devolvió la expiración del reto MFA."),
            reader.GetBoolean(8));
    }

    private static void ValidatePendingChallenge(
        ChallengeRecord challenge,
        Guid currentSessionId,
        string expectedPurpose)
    {
        if (challenge.ResponseCode == 429
            || challenge.Attempts >= MaximumAttempts)
        {
            throw MfaAdministrationException.InvalidCode(exhausted: true);
        }

        if (challenge.ResponseCode != 102)
        {
            throw new MfaAdministrationException(
                "security.mfa.challenge.consumed",
                409,
                "El reto ya no puede reutilizarse.");
        }

        if (!challenge.Active)
        {
            throw new MfaAdministrationException(
                "security.mfa.challenge.expired",
                409,
                "El reto expiró. Inicia uno nuevo.");
        }

        if (!Guid.TryParse(challenge.SessionId, out var sessionId)
            || sessionId != currentSessionId
            || !string.Equals(
                challenge.Purpose,
                expectedPurpose,
                StringComparison.Ordinal)
            || !string.Equals(
                challenge.PolicyVersion,
                PolicyVersion,
                StringComparison.Ordinal))
        {
            throw MfaAdministrationException.InvalidChallenge();
        }
    }

    private static async Task<FailedAttempt> RegisterFailedAttemptAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        ChallengeRecord challenge,
        CancellationToken cancellationToken)
    {
        var attempts = checked(challenge.Attempts + 1);
        var exhausted = attempts >= MaximumAttempts;

        const string sql = """
            UPDATE ops.idempotency_record
            SET
                response_code = CASE WHEN @exhausted THEN 429 ELSE 102 END,
                response_ref = jsonb_set(
                    response_ref,
                    '{attempts}',
                    to_jsonb(@attempts::integer),
                    true
                )
            WHERE idempotency_id = @idempotency_id;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("attempts", attempts);
        command.Parameters.AddWithValue("exhausted", exhausted);
        command.Parameters.AddWithValue(
            "idempotency_id",
            challenge.IdempotencyId);

        var changed = await command.ExecuteNonQueryAsync(cancellationToken);
        if (changed != 1)
        {
            throw new InvalidOperationException(
                "No se pudo registrar exactamente un intento MFA.");
        }

        return new FailedAttempt(exhausted);
    }

    private static async Task ConsumeChallengeAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid idempotencyId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE ops.idempotency_record
            SET
                response_code = 200,
                response_ref = jsonb_set(
                    response_ref,
                    '{consumed}',
                    'true'::jsonb,
                    true
                )
            WHERE idempotency_id = @idempotency_id
              AND response_code = 102;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "idempotency_id",
            idempotencyId);

        var changed = await command.ExecuteNonQueryAsync(cancellationToken);
        if (changed != 1)
        {
            throw MfaAdministrationException.InvalidChallenge();
        }
    }

    private static async Task ReserveTotpCounterAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        long counter,
        CancellationToken cancellationToken)
    {
        var digestInput = Encoding.ASCII.GetBytes(
            $"{accountId:D}:{counter}");
        var digest = SHA256.HashData(digestInput);

        try
        {
            const string sql = """
                INSERT INTO ops.idempotency_record (
                    account_id,
                    operation_code,
                    idempotency_key,
                    request_digest,
                    response_code,
                    response_ref,
                    created_at,
                    expires_at
                )
                VALUES (
                    @account_id,
                    @operation_code,
                    @idempotency_key,
                    @request_digest,
                    200,
                    '{"used":true}'::jsonb,
                    CURRENT_TIMESTAMP,
                    CURRENT_TIMESTAMP + INTERVAL '2 minutes'
                )
                ON CONFLICT (
                    account_id,
                    operation_code,
                    idempotency_key
                )
                DO NOTHING
                RETURNING idempotency_id;
                """;

            await using var command =
                new NpgsqlCommand(sql, connection, transaction);
            command.Parameters.AddWithValue("account_id", accountId);
            command.Parameters.AddWithValue(
                "operation_code",
                TotpUseOperation);
            command.Parameters.AddWithValue(
                "idempotency_key",
                counter.ToString(
                    System.Globalization.CultureInfo.InvariantCulture));
            command.Parameters.AddWithValue(
                "request_digest",
                NpgsqlDbType.Bytea,
                digest);

            var inserted =
                await command.ExecuteScalarAsync(cancellationToken);

            if (inserted is not Guid)
            {
                throw new MfaAdministrationException(
                    "security.mfa.code.replayed",
                    409,
                    "Ese código ya fue utilizado. Espera el siguiente código del autenticador.");
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(digestInput);
            CryptographicOperations.ZeroMemory(digest);
        }
    }

    private static async Task MarkSessionAssuranceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid sessionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE security.session
            SET
                assurance_level = @assurance_level,
                idle_expires_at = LEAST(
                    idle_expires_at,
                    CURRENT_TIMESTAMP + INTERVAL '15 minutes',
                    absolute_expires_at,
                    created_at + INTERVAL '8 hours'
                ),
                absolute_expires_at = LEAST(
                    absolute_expires_at,
                    created_at + INTERVAL '8 hours'
                )
            WHERE session_id = @session_id
              AND account_id = @account_id
              AND revoked_at IS NULL
              AND idle_expires_at > CURRENT_TIMESTAMP
              AND absolute_expires_at > CURRENT_TIMESTAMP
              AND created_at + INTERVAL '8 hours' > CURRENT_TIMESTAMP;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "assurance_level",
            AssuranceLevel);
        command.Parameters.AddWithValue("session_id", sessionId);
        command.Parameters.AddWithValue("account_id", accountId);

        var changed = await command.ExecuteNonQueryAsync(cancellationToken);
        if (changed != 1)
        {
            throw new MfaAdministrationException(
                "security.mfa.session.unavailable",
                401,
                "La sesión ya no está disponible para reforzar su autenticación.");
        }
    }

    private static async Task<DateTimeOffset> UpsertRecentAssuranceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid sessionId,
        CancellationToken cancellationToken)
    {
        var digest = SHA256.HashData(sessionId.ToByteArray());

        try
        {
            const string sql = """
                INSERT INTO ops.idempotency_record (
                    account_id,
                    operation_code,
                    idempotency_key,
                    request_digest,
                    response_code,
                    response_ref,
                    created_at,
                    expires_at
                )
                VALUES (
                    @account_id,
                    @operation_code,
                    @idempotency_key,
                    @request_digest,
                    200,
                    '{"assurance":"MFA","purpose":"PRIVILEGED"}'::jsonb,
                    CURRENT_TIMESTAMP,
                    CURRENT_TIMESTAMP + @lifetime
                )
                ON CONFLICT (
                    account_id,
                    operation_code,
                    idempotency_key
                )
                DO UPDATE SET
                    request_digest = EXCLUDED.request_digest,
                    response_code = 200,
                    response_ref = EXCLUDED.response_ref,
                    created_at = CURRENT_TIMESTAMP,
                    expires_at = CURRENT_TIMESTAMP + @lifetime
                RETURNING expires_at;
                """;

            await using var command =
                new NpgsqlCommand(sql, connection, transaction);
            command.Parameters.AddWithValue("account_id", accountId);
            command.Parameters.AddWithValue(
                "operation_code",
                AssuranceOperation);
            command.Parameters.AddWithValue(
                "idempotency_key",
                sessionId.ToString("N"));
            command.Parameters.AddWithValue(
                "request_digest",
                NpgsqlDbType.Bytea,
                digest);
            command.Parameters.AddWithValue(
                "lifetime",
                NpgsqlDbType.Interval,
                RecentAssuranceLifetime);

            var value =
                await command.ExecuteScalarAsync(cancellationToken);

            return ToOffset(
                value,
                "PostgreSQL no devolvió la expiración de la reautenticación.");
        }
        finally
        {
            CryptographicOperations.ZeroMemory(digest);
        }
    }

    private static async Task<RecentAssurance> ReadRecentAssuranceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid sessionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT assurance.expires_at
            FROM security.session AS session
            INNER JOIN ops.idempotency_record AS assurance
              ON assurance.account_id = session.account_id
             AND assurance.operation_code = @operation_code
             AND assurance.idempotency_key = @idempotency_key
             AND assurance.response_code = 200
            WHERE session.session_id = @session_id
              AND session.account_id = @account_id
              AND session.assurance_level = @assurance_level
              AND session.revoked_at IS NULL
              AND session.idle_expires_at > CURRENT_TIMESTAMP
              AND session.absolute_expires_at > CURRENT_TIMESTAMP
              AND assurance.expires_at > CURRENT_TIMESTAMP
              AND EXISTS (
                  SELECT 1
                  FROM security.mfa_method AS method
                  WHERE method.account_id = session.account_id
                    AND method.method_type = @method_type
                    AND method.disabled_at IS NULL
              )
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "operation_code",
            AssuranceOperation);
        command.Parameters.AddWithValue(
            "idempotency_key",
            sessionId.ToString("N"));
        command.Parameters.AddWithValue("session_id", sessionId);
        command.Parameters.AddWithValue("account_id", accountId);
        command.Parameters.AddWithValue(
            "assurance_level",
            AssuranceLevel);
        command.Parameters.AddWithValue(
            "method_type",
            MethodType);

        var value = await command.ExecuteScalarAsync(cancellationToken);
        if (value is null || value is DBNull)
        {
            return new RecentAssurance(false, null);
        }

        return new RecentAssurance(
            true,
            ToOffset(
                value,
                "PostgreSQL no devolvió la expiración de assurance."));
    }

    private static DateTimeOffset ToOffset(
        object? value,
        string errorMessage) =>
        value switch
        {
            DateTimeOffset offset => offset,
            DateTime dateTime => new DateTimeOffset(
                DateTime.SpecifyKind(dateTime, DateTimeKind.Utc)),
            _ => throw new InvalidOperationException(errorMessage)
        };

    private sealed record ActiveCredential(
        string Hash,
        string Algorithm,
        string Parameters);

    private sealed record ActiveMfaMethod(
        string SecretReference);

    private sealed record ChallengeRecord(
        Guid IdempotencyId,
        byte[] RequestDigest,
        int ResponseCode,
        string SessionId,
        string Purpose,
        int Attempts,
        string PolicyVersion,
        DateTimeOffset ExpiresAt,
        bool Active);

    private sealed record ChallengeState(
        string SessionId,
        string Purpose,
        int Attempts,
        string PolicyVersion);

    private sealed record FailedAttempt(
        bool Exhausted);

    private sealed record RecentAssurance(
        bool Active,
        DateTimeOffset? ExpiresAt);

    private sealed record ConfirmationOutcome<T>(
        T? Value,
        MfaAdministrationException? Error)
        where T : class
    {
        public static ConfirmationOutcome<T> FromValue(T value) =>
            new(value, null);

        public static ConfirmationOutcome<T> FromError(
            MfaAdministrationException error) =>
            new(null, error);
    }
}

public sealed record MfaStatus(
    bool Enrolled,
    bool RecentAssurance,
    string? MethodType,
    DateTimeOffset? AssuranceExpiresAt);

public sealed record MfaEnrollmentStarted(
    Guid ChallengeId,
    string Secret,
    string OtpAuthUri,
    DateTimeOffset ExpiresAt);

public sealed record MfaChallengeStarted(
    Guid ChallengeId,
    DateTimeOffset ExpiresAt,
    int MaximumAttempts);

public sealed class MfaAdministrationException : Exception
{
    public MfaAdministrationException(
        string code,
        int statusCode,
        string message,
        Exception? innerException = null)
        : base(message, innerException)
    {
        Code = code;
        StatusCode = statusCode;
    }

    public string Code { get; }

    public int StatusCode { get; }

    public static MfaAdministrationException InvalidReauthentication() =>
        new(
            "security.mfa.reauthentication.invalid",
            401,
            "La contraseña actual no pudo confirmar una autenticación reciente.");

    public static MfaAdministrationException InvalidChallenge() =>
        new(
            "security.mfa.challenge.invalid",
            400,
            "El reto MFA no es válido para esta sesión y finalidad.");

    public static MfaAdministrationException InvalidCode(bool exhausted) =>
        exhausted
            ? new(
                "security.mfa.challenge.exhausted",
                429,
                "El reto alcanzó el máximo de intentos. Inicia uno nuevo.")
            : new(
                "security.mfa.code.invalid",
                400,
                "El código del autenticador no es válido.");
}
