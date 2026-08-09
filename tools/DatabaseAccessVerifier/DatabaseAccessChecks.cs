using Npgsql;

namespace MusicaAprender.DatabaseAccessVerifier;

internal sealed class DatabaseAccessChecks
{
    private const string PermissionDeniedSqlState = "42501";

    private readonly AccessVerificationOptions _options;

    internal DatabaseAccessChecks(AccessVerificationOptions options)
    {
        _options = options;
    }

    internal async Task RunAsync()
    {
        await VerifyCurrentUserAsync(
            "jp_login_api",
            "postgres_api_password");

        await VerifyCurrentUserAsync(
            "jp_login_backoffice",
            "postgres_backoffice_password");

        await VerifyCurrentUserAsync(
            "jp_login_worker",
            "postgres_worker_password");

        await VerifyCurrentUserAsync(
            "jp_login_readonly",
            "postgres_readonly_password");

        await VerifyCurrentUserAsync(
            "jp_login_migrator",
            "postgres_migrator_password");

        await ExpectSuccessAsync(
            "API SELECT catalog",
            "jp_login_api",
            "postgres_api_password",
            "SELECT count(*) FROM catalog.artist;");

        await ExpectPermissionDeniedAsync(
            "API no SET ROLE owner",
            "jp_login_api",
            "postgres_api_password",
            "SET ROLE jp_owner;");

        await ExpectPermissionDeniedAsync(
            "API no SET ROLE migrator",
            "jp_login_api",
            "postgres_api_password",
            "SET ROLE jp_migrator;");

        await ExpectPermissionDeniedAsync(
            "API no DDL catalog",
            "jp_login_api",
            "postgres_api_password",
            "CREATE TABLE catalog.bl_mvp_012_probe(id integer);",
            "DROP TABLE IF EXISTS catalog.bl_mvp_012_probe;");

        await ExpectSuccessAsync(
            "Backoffice UPDATE permitido",
            "jp_login_backoffice",
            "postgres_backoffice_password",
            "UPDATE catalog.artist SET artist_id = artist_id WHERE false;");

        await ExpectPermissionDeniedAsync(
            "Backoffice DELETE denegado",
            "jp_login_backoffice",
            "postgres_backoffice_password",
            "DELETE FROM catalog.artist WHERE false;");

        await ExpectSuccessAsync(
            "Worker DML ops permitido",
            "jp_login_worker",
            "postgres_worker_password",
            "DELETE FROM ops.idempotency_record WHERE false;");

        await ExpectPermissionDeniedAsync(
            "Worker no SET ROLE owner",
            "jp_login_worker",
            "postgres_worker_password",
            "SET ROLE jp_owner;");

        await ExpectPermissionDeniedAsync(
            "Worker no DDL ops",
            "jp_login_worker",
            "postgres_worker_password",
            "CREATE TABLE ops.bl_mvp_012_probe(id integer);",
            "DROP TABLE IF EXISTS ops.bl_mvp_012_probe;");

        await ExpectSuccessAsync(
            "Readonly vista publica",
            "jp_login_readonly",
            "postgres_readonly_password",
            "SELECT * FROM catalog.v_public_song LIMIT 0;");

        await ExpectPermissionDeniedAsync(
            "Readonly no SELECT tabla privada",
            "jp_login_readonly",
            "postgres_readonly_password",
            "SELECT * FROM catalog.artist LIMIT 0;");

        await ExpectPermissionDeniedAsync(
            "Readonly no INSERT",
            "jp_login_readonly",
            "postgres_readonly_password",
            "INSERT INTO catalog.artist DEFAULT VALUES;");

        await ExpectPermissionDeniedAsync(
            "Readonly no UPDATE",
            "jp_login_readonly",
            "postgres_readonly_password",
            "UPDATE catalog.artist SET artist_id = artist_id WHERE false;");

        await ExpectPermissionDeniedAsync(
            "Readonly no DELETE",
            "jp_login_readonly",
            "postgres_readonly_password",
            "DELETE FROM catalog.artist WHERE false;");

        await ExpectSuccessAsync(
            "Migrator puede SET ROLE owner",
            "jp_login_migrator",
            "postgres_migrator_password",
            "SET ROLE jp_owner; RESET ROLE;");

        Console.WriteLine(
            "OK: autenticacion real y pruebas positivas/negativas de minimo privilegio aprobadas.");
    }

    private async Task VerifyCurrentUserAsync(
        string username,
        string secretName)
    {
        await using var connection = await OpenAsync(username, secretName);
        await using var command = new NpgsqlCommand("SELECT current_user;", connection);

        var currentUser = (string?)await command.ExecuteScalarAsync();

        if (!string.Equals(currentUser, username, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"La conexion esperaba current_user={username} y obtuvo {currentUser ?? "<null>"}.");
        }

        Console.WriteLine($"OK: autenticacion separada {username}.");
    }

    private async Task ExpectSuccessAsync(
        string name,
        string username,
        string secretName,
        string sql)
    {
        await using var connection = await OpenAsync(username, secretName);
        await using var command = new NpgsqlCommand(sql, connection);

        await command.ExecuteNonQueryAsync();
        Console.WriteLine($"OK: {name}.");
    }

    private async Task ExpectPermissionDeniedAsync(
        string name,
        string username,
        string secretName,
        string sql,
        string? cleanupSql = null)
    {
        await using var connection = await OpenAsync(username, secretName);

        try
        {
            await using var command = new NpgsqlCommand(sql, connection);
            await command.ExecuteNonQueryAsync();

            if (!string.IsNullOrWhiteSpace(cleanupSql))
            {
                await using var cleanup = new NpgsqlCommand(cleanupSql, connection);
                await cleanup.ExecuteNonQueryAsync();
            }
        }
        catch (PostgresException exception)
            when (string.Equals(
                exception.SqlState,
                PermissionDeniedSqlState,
                StringComparison.Ordinal))
        {
            Console.WriteLine($"OK: denegacion esperada - {name}.");
            return;
        }

        throw new InvalidOperationException(
            $"La operacion prohibida no fue rechazada por permisos: {name}.");
    }

    private async Task<NpgsqlConnection> OpenAsync(
        string username,
        string secretName)
    {
        var password = ReadSecret(secretName);

        var connectionString = new NpgsqlConnectionStringBuilder
        {
            Host = _options.Host,
            Port = _options.Port,
            Database = _options.Database,
            Username = username,
            Password = password,
            IncludeErrorDetail = false,
            Pooling = false,
            Timeout = 15
        }.ConnectionString;

        var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        return connection;
    }

    private string ReadSecret(string secretName)
    {
        var path = Path.Combine(_options.SecretDirectory, secretName);

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
}
