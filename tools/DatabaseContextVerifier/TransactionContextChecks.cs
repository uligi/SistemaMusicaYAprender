using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using Npgsql;

namespace MusicaAprender.DatabaseContextVerifier;

internal sealed class TransactionContextChecks
{
    private static readonly Guid AccountA =
        Guid.Parse("13000000-0000-4000-8000-000000000001");

    private static readonly Guid AccountB =
        Guid.Parse("13000000-0000-4000-8000-000000000002");

    private readonly string _connectionString;
    private readonly RlsTransactionExecutor _executor;

    internal TransactionContextChecks(ContextVerificationOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        var password = ReadSecret(
            options.SecretDirectory,
            "postgres_api_password");

        _connectionString = new NpgsqlConnectionStringBuilder
        {
            Host = options.Host,
            Port = options.Port,
            Database = options.Database,
            Username = "jp_login_api",
            Password = password,
            IncludeErrorDetail = false,
            Pooling = true,
            MinPoolSize = 0,
            MaxPoolSize = 1,
            Timeout = 15,
            ApplicationName = "bl-mvp-013-context-verifier"
        }.ConnectionString;

        _executor = new RlsTransactionExecutor(_connectionString);
    }

    internal async Task RunAsync()
    {
        NpgsqlConnection.ClearAllPools();

        await VerifyTransactionLocalContextAsync();
        await VerifyRlsCrossAccountIsolationAsync();
        await VerifyPoolReuseDoesNotLeakAsync();
        await VerifyRollbackClearsContextAsync();
        VerifyUnsafeContextIsRejected();

        NpgsqlConnection.ClearAllPools();

        Console.WriteLine(
            "OK: SET LOCAL equivalente, RLS cruzado y reutilizacion de conexiones aprobados.");
    }

    private async Task VerifyTransactionLocalContextAsync()
    {
        var context = DatabaseSessionContext.Create(
            AccountA,
            "STUDENT",
            "bl013-local-context-a");

        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync();

        var backendPid = await ReadBackendPidAsync(connection);

        await using (var transaction = await connection.BeginTransactionAsync())
        {
            await RlsTransactionContext.ApplyAsync(
                connection,
                transaction,
                context);

            var snapshot = await ReadContextAsync(
                connection,
                transaction);

            AssertContext(snapshot, context);

            if (snapshot.BackendPid != backendPid)
            {
                throw new InvalidOperationException(
                    "La sesion PostgreSQL cambio dentro de la misma conexion.");
            }

            await transaction.CommitAsync();
        }

        var afterCommit = await ReadContextAsync(
            connection,
            transaction: null);

        AssertContextIsEmpty(
            afterCommit,
            "commit en la misma conexion fisica");

        if (afterCommit.BackendPid != backendPid)
        {
            throw new InvalidOperationException(
                "La prueba de limpieza post-commit no uso la misma sesion PostgreSQL.");
        }

        Console.WriteLine(
            "OK: account_id, role_code y correlation_id son locales a la transaccion.");
    }

    private async Task VerifyRlsCrossAccountIsolationAsync()
    {
        var contextA = DatabaseSessionContext.Create(
            AccountA,
            "STUDENT",
            "bl013-rls-account-a");

        var contextB = DatabaseSessionContext.Create(
            AccountB,
            "STUDENT",
            "bl013-rls-account-b");

        var visibleToA = await _executor.ExecuteAsync(
            contextA,
            ReadFixtureAccountsAsync);

        AssertSingleVisibleAccount(
            visibleToA,
            AccountA,
            "cuenta A");

        var ownUpdateA = await _executor.ExecuteAsync(
            contextA,
            (connection, transaction, cancellationToken) =>
                UpdateProfileAsync(
                    connection,
                    transaction,
                    AccountA,
                    cancellationToken));

        var crossUpdateB = await _executor.ExecuteAsync(
            contextA,
            (connection, transaction, cancellationToken) =>
                UpdateProfileAsync(
                    connection,
                    transaction,
                    AccountB,
                    cancellationToken));

        if (ownUpdateA != 1 || crossUpdateB != 0)
        {
            throw new InvalidOperationException(
                $"RLS de cuenta A esperaba UPDATE propio=1 y cruzado=0; obtuvo {ownUpdateA}/{crossUpdateB}.");
        }

        var visibleToB = await _executor.ExecuteAsync(
            contextB,
            ReadFixtureAccountsAsync);

        AssertSingleVisibleAccount(
            visibleToB,
            AccountB,
            "cuenta B");

        var crossUpdateA = await _executor.ExecuteAsync(
            contextB,
            (connection, transaction, cancellationToken) =>
                UpdateProfileAsync(
                    connection,
                    transaction,
                    AccountA,
                    cancellationToken));

        if (crossUpdateA != 0)
        {
            throw new InvalidOperationException(
                "RLS permitio escritura cruzada desde cuenta B hacia cuenta A.");
        }

        await using var noContextConnection = new NpgsqlConnection(_connectionString);
        await noContextConnection.OpenAsync();

        var withoutContext = await CountFixtureAccountsAsync(
            noContextConnection,
            transaction: null,
            CancellationToken.None);

        if (withoutContext != 0)
        {
            throw new InvalidOperationException(
                "jp_app pudo ver filas personales sin app.account_id.");
        }

        Console.WriteLine(
            "OK: RLS permite lectura/escritura propia y deniega acceso cruzado.");
    }

    private async Task VerifyPoolReuseDoesNotLeakAsync()
    {
        NpgsqlConnection.ClearAllPools();

        var contextA = DatabaseSessionContext.Create(
            AccountA,
            "STUDENT",
            "bl013-pool-account-a");

        var backendPidA = await _executor.ExecuteAsync(
            contextA,
            async (connection, transaction, cancellationToken) =>
            {
                var snapshot = await ReadContextAsync(
                    connection,
                    transaction,
                    cancellationToken);

                AssertContext(snapshot, contextA);
                return snapshot.BackendPid;
            });

        await using (var reusedConnection = new NpgsqlConnection(_connectionString))
        {
            await reusedConnection.OpenAsync();

            var reusedSnapshot = await ReadContextAsync(
                reusedConnection,
                transaction: null);

            if (reusedSnapshot.BackendPid != backendPidA)
            {
                throw new InvalidOperationException(
                    "La prueba de pool no reutilizo la conexion fisica esperada con MaxPoolSize=1.");
            }

            AssertContextIsEmpty(
                reusedSnapshot,
                "prestamo posterior del pool");
        }

        var contextB = DatabaseSessionContext.Create(
            AccountB,
            "STUDENT",
            "bl013-pool-account-b");

        var backendPidB = await _executor.ExecuteAsync(
            contextB,
            async (connection, transaction, cancellationToken) =>
            {
                var snapshot = await ReadContextAsync(
                    connection,
                    transaction,
                    cancellationToken);

                AssertContext(snapshot, contextB);
                return snapshot.BackendPid;
            });

        if (backendPidB != backendPidA)
        {
            throw new InvalidOperationException(
                "MaxPoolSize=1 no reutilizo la misma sesion entre cuenta A y cuenta B.");
        }

        Console.WriteLine(
            "OK: una conexion reutilizada no conserva contexto de la cuenta anterior.");
    }

    private async Task VerifyRollbackClearsContextAsync()
    {
        NpgsqlConnection.ClearAllPools();

        var context = DatabaseSessionContext.Create(
            AccountA,
            "STUDENT",
            "bl013-rollback-account-a");

        var expectedFailure = new InvalidOperationException(
            "BL-MVP-013 rollback intencional.");

        var backendPid = 0;

        try
        {
            await _executor.ExecuteAsync(
                context,
                async (connection, transaction, cancellationToken) =>
                {
                    var snapshot = await ReadContextAsync(
                        connection,
                        transaction,
                        cancellationToken);

                    AssertContext(snapshot, context);
                    backendPid = snapshot.BackendPid;

                    throw expectedFailure;
                });
        }
        catch (InvalidOperationException exception)
            when (ReferenceEquals(exception, expectedFailure))
        {
            // La excepcion fuerza rollback por DisposeAsync de NpgsqlTransaction.
        }

        if (backendPid == 0)
        {
            throw new InvalidOperationException(
                "La prueba de rollback no llego a establecer el contexto.");
        }

        await using var reusedConnection = new NpgsqlConnection(_connectionString);
        await reusedConnection.OpenAsync();

        var afterRollback = await ReadContextAsync(
            reusedConnection,
            transaction: null);

        if (afterRollback.BackendPid != backendPid)
        {
            throw new InvalidOperationException(
                "La prueba post-rollback no reutilizo la misma sesion PostgreSQL.");
        }

        AssertContextIsEmpty(
            afterRollback,
            "rollback y devolucion al pool");

        Console.WriteLine(
            "OK: rollback elimina el contexto antes de reutilizar la conexion.");
    }

    private static void VerifyUnsafeContextIsRejected()
    {
        ExpectArgumentException(
            () => DatabaseSessionContext.Create(
                Guid.Empty,
                "STUDENT",
                "bl013-valid-correlation"),
            "Guid.Empty");

        ExpectArgumentException(
            () => DatabaseSessionContext.Create(
                AccountA,
                "student",
                "bl013-valid-correlation"),
            "rol en minusculas");

        ExpectArgumentException(
            () => DatabaseSessionContext.Create(
                AccountA,
                "STUDENT;SET_ROLE",
                "bl013-valid-correlation"),
            "rol inseguro");

        ExpectArgumentException(
            () => DatabaseSessionContext.Create(
                AccountA,
                "STUDENT",
                "bad correlation"),
            "correlacion insegura");

        Console.WriteLine(
            "OK: valores de contexto inseguros se rechazan antes de llegar a PostgreSQL.");
    }

    private static async Task<List<Guid>> ReadFixtureAccountsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT account_id
            FROM identity.user_profile
            WHERE account_id IN (@account_a, @account_b)
            ORDER BY account_id;
            """,
            connection,
            transaction);

        command.Parameters.AddWithValue("account_a", AccountA);
        command.Parameters.AddWithValue("account_b", AccountB);

        var result = new List<Guid>();

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(reader.GetGuid(0));
        }

        return result;
    }

    private static async Task<int> UpdateProfileAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            UPDATE identity.user_profile
            SET display_name = display_name
            WHERE account_id = @account_id;
            """,
            connection,
            transaction);

        command.Parameters.AddWithValue("account_id", accountId);

        return await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<long> CountFixtureAccountsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT count(*)
            FROM identity.user_profile
            WHERE account_id IN (@account_a, @account_b);
            """,
            connection,
            transaction);

        command.Parameters.AddWithValue("account_a", AccountA);
        command.Parameters.AddWithValue("account_b", AccountB);

        var result = await command.ExecuteScalarAsync(cancellationToken);

        return Convert.ToInt64(
            result,
            System.Globalization.CultureInfo.InvariantCulture);
    }

    private static async Task<int> ReadBackendPidAsync(
        NpgsqlConnection connection)
    {
        await using var command = new NpgsqlCommand(
            "SELECT pg_backend_pid();",
            connection);

        var result = await command.ExecuteScalarAsync();

        return Convert.ToInt32(
            result,
            System.Globalization.CultureInfo.InvariantCulture);
    }

    private static async Task<ContextSnapshot> ReadContextAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        CancellationToken cancellationToken = default)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT
                NULLIF(current_setting('app.account_id', true), ''),
                NULLIF(current_setting('app.role_code', true), ''),
                NULLIF(current_setting('app.correlation_id', true), ''),
                security.current_account_id(),
                pg_backend_pid();
            """,
            connection,
            transaction);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "PostgreSQL no devolvio snapshot del contexto.");
        }

        return new ContextSnapshot(
            reader.IsDBNull(0) ? null : reader.GetString(0),
            reader.IsDBNull(1) ? null : reader.GetString(1),
            reader.IsDBNull(2) ? null : reader.GetString(2),
            reader.IsDBNull(3) ? null : reader.GetGuid(3),
            reader.GetInt32(4));
    }

    private static void AssertContext(
        ContextSnapshot snapshot,
        DatabaseSessionContext expected)
    {
        if (!string.Equals(
                snapshot.AccountSetting,
                expected.AccountId.ToString("D"),
                StringComparison.Ordinal)
            || !string.Equals(
                snapshot.RoleSetting,
                expected.RoleCode,
                StringComparison.Ordinal)
            || !string.Equals(
                snapshot.CorrelationSetting,
                expected.CorrelationId,
                StringComparison.Ordinal)
            || snapshot.CurrentAccountId != expected.AccountId)
        {
            throw new InvalidOperationException(
                "El contexto PostgreSQL no coincide con cuenta, rol y correlacion esperados.");
        }
    }

    private static void AssertContextIsEmpty(
        ContextSnapshot snapshot,
        string stage)
    {
        if (snapshot.AccountSetting is not null
            || snapshot.RoleSetting is not null
            || snapshot.CorrelationSetting is not null
            || snapshot.CurrentAccountId is not null)
        {
            throw new InvalidOperationException(
                $"El contexto PostgreSQL sobrevivio indebidamente a {stage}.");
        }
    }

    private static void AssertSingleVisibleAccount(
        List<Guid> visibleAccounts,
        Guid expected,
        string label)
    {
        if (visibleAccounts.Count != 1
            || visibleAccounts[0] != expected)
        {
            throw new InvalidOperationException(
                $"RLS para {label} no devolvio exclusivamente su propia fila.");
        }
    }

    private static void ExpectArgumentException(
        Action action,
        string label)
    {
        try
        {
            action();
        }
        catch (ArgumentException)
        {
            return;
        }

        throw new InvalidOperationException(
            $"El contexto invalido no fue rechazado: {label}.");
    }

    private static string ReadSecret(
        string secretDirectory,
        string secretName)
    {
        var path = Path.Combine(secretDirectory, secretName);

        if (!File.Exists(path))
        {
            throw new InvalidOperationException(
                $"Falta el secreto requerido '{secretName}'.");
        }

        var value = File.ReadAllText(path).Trim();

        if (value.Length < 24)
        {
            throw new InvalidOperationException(
                $"El secreto '{secretName}' es demasiado corto.");
        }

        return value;
    }

    private sealed record ContextSnapshot(
        string? AccountSetting,
        string? RoleSetting,
        string? CorrelationSetting,
        Guid? CurrentAccountId,
        int BackendPid);
}
