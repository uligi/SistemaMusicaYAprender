using MusicaAprender.BuildingBlocks.Infrastructure.ObjectStorage;
using Npgsql;

namespace MusicaAprender.ObjectStoreVerifier;

internal sealed class ObjectStoreVerificationOptions
{
    private ObjectStoreVerificationOptions(
        Uri endpoint,
        string bucket,
        string secretDirectory,
        string databaseHost,
        int databasePort,
        string databaseName)
    {
        Endpoint = endpoint;
        Bucket = bucket;
        SecretDirectory = secretDirectory;
        DatabaseHost = databaseHost;
        DatabasePort = databasePort;
        DatabaseName = databaseName;

        AccessKey = ReadSecret("object_store_access_key", 16);
        SecretKey = ReadSecret("object_store_secret_key", 32);
        EncryptionKeyHex = ReadSecret("object_store_encryption_key", 64);
        WorkerPassword = ReadSecret("postgres_worker_password", 24);
    }

    public Uri Endpoint { get; }

    public string Bucket { get; }

    public string SecretDirectory { get; }

    public string DatabaseHost { get; }

    public int DatabasePort { get; }

    public string DatabaseName { get; }

    public string AccessKey { get; }

    public string SecretKey { get; }

    public string EncryptionKeyHex { get; }

    public string WorkerPassword { get; }

    public static string EncryptionKeyReference =>
        "local-secret://object_store_encryption_key/v1";

    public ObjectStoreOptions CreateObjectStoreOptions()
    {
        return new ObjectStoreOptions(
            Endpoint,
            Bucket,
            AccessKey,
            SecretKey,
            EncryptionKeyHex,
            EncryptionKeyReference);
    }

    public string CreateWorkerConnectionString()
    {
        return new NpgsqlConnectionStringBuilder
        {
            Host = DatabaseHost,
            Port = DatabasePort,
            Database = DatabaseName,
            Username = "jp_login_worker",
            Password = WorkerPassword,
            IncludeErrorDetail = false,
            Pooling = false,
            Timeout = 15
        }.ConnectionString;
    }

    public static ObjectStoreVerificationOptions Parse(string[] args)
    {
        ArgumentNullException.ThrowIfNull(args);

        var values = new Dictionary<string, string>(
            StringComparer.Ordinal);

        for (var index = 0; index < args.Length; index += 2)
        {
            if (index + 1 >= args.Length ||
                !args[index].StartsWith("--", StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "Argumentos invalidos para ObjectStoreVerifier.");
            }

            values[args[index][2..]] = args[index + 1];
        }

        var endpointText = Require(values, "endpoint");

        if (!Uri.TryCreate(endpointText, UriKind.Absolute, out var endpoint))
        {
            throw new InvalidOperationException(
                "--endpoint debe ser una URL absoluta.");
        }

        if (!int.TryParse(
                Require(values, "pg-port"),
                out var databasePort) ||
            databasePort is < 1 or > 65535)
        {
            throw new InvalidOperationException(
                "--pg-port debe ser un puerto TCP valido.");
        }

        var secretDirectory = Path.GetFullPath(
            Require(values, "secret-dir"));

        if (!Directory.Exists(secretDirectory))
        {
            throw new InvalidOperationException(
                "No existe el secret store indicado.");
        }

        return new ObjectStoreVerificationOptions(
            endpoint,
            Require(values, "bucket"),
            secretDirectory,
            Require(values, "pg-host"),
            databasePort,
            Require(values, "pg-database"));
    }

    private string ReadSecret(string name, int minimumLength)
    {
        var path = Path.Combine(SecretDirectory, name);

        if (!File.Exists(path))
        {
            throw new InvalidOperationException(
                $"Falta el secreto requerido '{name}'.");
        }

        var value = File.ReadAllText(path).Trim();

        if (value.Length < minimumLength || value.Length > 4096)
        {
            throw new InvalidOperationException(
                $"El secreto '{name}' no cumple el formato esperado.");
        }

        return value;
    }

    private static string Require(
        Dictionary<string, string> values,
        string name)
    {
        if (!values.TryGetValue(name, out var value) ||
            string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException(
                $"Falta el argumento --{name}.");
        }

        return value.Trim();
    }
}
