using Npgsql;

namespace MusicaAprender.DatabaseReliabilityVerifier;

internal sealed record ReliabilityVerificationOptions(
    string Host,
    int Port,
    string Database,
    string SecretDirectory)
{
    public string CreateApiConnectionString()
    {
        return CreateConnectionString(
            "jp_login_api",
            "postgres_api_password",
            "bl-mvp-015-verifier-api");
    }

    public string CreateWorkerConnectionString()
    {
        return CreateConnectionString(
            "jp_login_worker",
            "postgres_worker_password",
            "bl-mvp-015-verifier-worker");
    }

    public static ReliabilityVerificationOptions Parse(string[] args)
    {
        ArgumentNullException.ThrowIfNull(args);

        var values = new Dictionary<string, string>(
            StringComparer.Ordinal);

        for (var index = 0; index < args.Length; index += 2)
        {
            if (index + 1 >= args.Length
                || !args[index].StartsWith("--", StringComparison.Ordinal))
            {
                throw new ArgumentException(
                    "Los argumentos deben usar pares --nombre valor.",
                    nameof(args));
            }

            values[args[index][2..]] = args[index + 1];
        }

        var host = Require(values, "host");
        var database = Require(values, "database");
        var secretDirectory = Require(values, "secret-directory");

        if (!int.TryParse(
                Require(values, "port"),
                out var port)
            || port is < 1 or > 65535)
        {
            throw new ArgumentException(
                "--port debe ser un puerto TCP valido.",
                nameof(args));
        }

        return new ReliabilityVerificationOptions(
            host,
            port,
            database,
            secretDirectory);
    }

    private string CreateConnectionString(
        string username,
        string secretName,
        string applicationName)
    {
        var password = ReadSecret(secretName);

        return new NpgsqlConnectionStringBuilder
        {
            Host = Host,
            Port = Port,
            Database = Database,
            Username = username,
            Password = password,
            IncludeErrorDetail = false,
            Pooling = true,
            MaxPoolSize = 4,
            ApplicationName = applicationName
        }.ConnectionString;
    }

    private string ReadSecret(string secretName)
    {
        var path = Path.Combine(
            SecretDirectory,
            secretName);

        if (!File.Exists(path))
        {
            throw new InvalidOperationException(
                $"Falta el secreto requerido '{secretName}'.");
        }

        var value = File.ReadAllText(path).Trim();

        if (value.Length < 24)
        {
            throw new InvalidOperationException(
                $"El secreto '{secretName}' no cumple la longitud minima.");
        }

        return value;
    }

    private static string Require(
        Dictionary<string, string> values,
        string name)
    {
        if (!values.TryGetValue(name, out var value)
            || string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException(
                $"Falta --{name}.",
                nameof(values));
        }

        return value.Trim();
    }
}
