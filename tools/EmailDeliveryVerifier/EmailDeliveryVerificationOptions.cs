using Npgsql;

namespace MusicaAprender.EmailDeliveryVerifier;

internal sealed record EmailDeliveryVerificationOptions(
    string ApiConnectionString,
    string WorkerConnectionString,
    string SmtpHost,
    int SmtpPort,
    Uri MailpitApiBase)
{
    public static EmailDeliveryVerificationOptions Load(
        string[] args)
    {
        ArgumentNullException.ThrowIfNull(args);

        var repoRoot = FindRepoRoot();
        var secretDirectory =
            Path.Combine(repoRoot, "secrets", "local");

        var host =
            Environment.GetEnvironmentVariable("PGHOST")
            ?? "127.0.0.1";

        var database =
            Environment.GetEnvironmentVariable("PGDATABASE")
            ?? "musica_aprender";

        var port = ReadPort(
            Environment.GetEnvironmentVariable("PGPORT"),
            5432);

        var smtpHost =
            Environment.GetEnvironmentVariable("SMTP_HOST")
            ?? "127.0.0.1";

        var smtpPort = ReadPort(
            Environment.GetEnvironmentVariable("SMTP_PORT"),
            1025);

        var mailpitBase =
            Environment.GetEnvironmentVariable("MAILPIT_API_BASE")
            ?? "http://127.0.0.1:8025/";

        var apiPassword =
            ReadSecret(
                secretDirectory,
                "postgres_api_password");

        var workerPassword =
            ReadSecret(
                secretDirectory,
                "postgres_worker_password");

        return new EmailDeliveryVerificationOptions(
            BuildConnectionString(
                host,
                port,
                database,
                "jp_login_api",
                apiPassword),
            BuildConnectionString(
                host,
                port,
                database,
                "jp_login_worker",
                workerPassword),
            smtpHost,
            smtpPort,
            new Uri(mailpitBase, UriKind.Absolute));
    }

    private static string FindRepoRoot()
    {
        var current =
            new DirectoryInfo(
                Directory.GetCurrentDirectory());

        while (current is not null)
        {
            if (File.Exists(
                Path.Combine(
                    current.FullName,
                    "MusicaAprender.sln")))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        throw new InvalidOperationException(
            "No se encontro la raiz del repositorio.");
    }

    private static string ReadSecret(
        string secretDirectory,
        string name)
    {
        var path =
            Path.Combine(secretDirectory, name);

        if (!File.Exists(path))
        {
            throw new InvalidOperationException(
                $"Falta el secreto local requerido '{name}'.");
        }

        var value =
            File.ReadAllText(path).Trim();

        if (value.Length < 24)
        {
            throw new InvalidOperationException(
                $"El secreto local '{name}' no es valido.");
        }

        return value;
    }

    private static string BuildConnectionString(
        string host,
        int port,
        string database,
        string username,
        string password)
    {
        return new NpgsqlConnectionStringBuilder
        {
            Host = host,
            Port = port,
            Database = database,
            Username = username,
            Password = password,
            IncludeErrorDetail = false,
            Pooling = true
        }.ConnectionString;
    }

    private static int ReadPort(
        string? value,
        int defaultPort)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return defaultPort;
        }

        if (!int.TryParse(value, out var port)
            || port is < 1 or > 65535)
        {
            throw new InvalidOperationException(
                "Se configuro un puerto TCP invalido.");
        }

        return port;
    }
}
