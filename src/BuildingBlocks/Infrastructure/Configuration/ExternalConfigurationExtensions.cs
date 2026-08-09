using Microsoft.Extensions.Configuration;
using Npgsql;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Configuration;

public static class ExternalConfigurationExtensions
{
    private const string DefaultSecretDirectory = "/run/secrets";

    private const string DefaultPostgreSqlPasswordSecret = "postgres_password";
    private const string ObjectStoreAccessKeySecret = "object_store_access_key";
    private const string ObjectStoreSecretKeySecret = "object_store_secret_key";

    public static ConfigurationManager AddMusicaAprenderExternalConfiguration(
        this ConfigurationManager configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var requireExternalSecrets = ReadBoolean(
            configuration["Secrets:RequireExternal"],
            defaultValue: false);

        var secretDirectory =
            configuration["Secrets:Directory"]
            ?? DefaultSecretDirectory;

        if (!requireExternalSecrets && !Directory.Exists(secretDirectory))
        {
            return configuration;
        }

        var postgresPasswordSecret = ReadSecretName(
            configuration["Database:PasswordSecret"],
            DefaultPostgreSqlPasswordSecret);

        var postgresPassword = ReadSecret(
            secretDirectory,
            postgresPasswordSecret,
            minimumLength: 24);

        var objectStoreAccessKey = ReadSecret(
            secretDirectory,
            ObjectStoreAccessKeySecret,
            minimumLength: 16);

        var objectStoreSecretKey = ReadSecret(
            secretDirectory,
            ObjectStoreSecretKeySecret,
            minimumLength: 32);

        var databaseHost = RequireNonSecret(configuration, "Database:Host");
        var databaseName = RequireNonSecret(configuration, "Database:Name");
        var databaseUsername = RequireNonSecret(configuration, "Database:Username");
        var databasePort = ReadPort(configuration["Database:Port"], 5432);

        var connectionString = new NpgsqlConnectionStringBuilder
        {
            Host = databaseHost,
            Port = databasePort,
            Database = databaseName,
            Username = databaseUsername,
            Password = postgresPassword,
            IncludeErrorDetail = false,
            Pooling = true
        }.ConnectionString;

        configuration.AddInMemoryCollection(
            new Dictionary<string, string?>
            {
                ["ConnectionStrings:PostgreSQL"] = connectionString,
                ["ObjectStore:AccessKey"] = objectStoreAccessKey,
                ["ObjectStore:SecretKey"] = objectStoreSecretKey
            });

        return configuration;
    }

    private static string ReadSecret(
        string secretDirectory,
        string secretName,
        int minimumLength)
    {
        var path = Path.Combine(secretDirectory, secretName);

        if (!File.Exists(path))
        {
            throw new InvalidOperationException(
                $"Falta el secreto requerido '{secretName}' en el secret store configurado.");
        }

        var value = File.ReadAllText(path).Trim();

        if (value.Length < minimumLength)
        {
            throw new InvalidOperationException(
                $"El secreto '{secretName}' no cumple la longitud minima requerida.");
        }

        if (value.Length > 4096)
        {
            throw new InvalidOperationException(
                $"El secreto '{secretName}' excede la longitud maxima permitida.");
        }

        return value;
    }

    private static string ReadSecretName(
        string? value,
        string defaultName)
    {
        var secretName = string.IsNullOrWhiteSpace(value)
            ? defaultName
            : value.Trim();

        foreach (var character in secretName)
        {
            if (!(char.IsAsciiLetterOrDigit(character) || character is '_' or '-'))
            {
                throw new InvalidOperationException(
                    "Database:PasswordSecret contiene un nombre de secreto no permitido.");
            }
        }

        if (secretName.Length is < 1 or > 128)
        {
            throw new InvalidOperationException(
                "Database:PasswordSecret debe tener entre 1 y 128 caracteres.");
        }

        return secretName;
    }

    private static string RequireNonSecret(
        ConfigurationManager configuration,
        string key)
    {
        var value = configuration[key];

        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException(
                $"Falta la configuracion no secreta requerida '{key}'.");
        }

        return value.Trim();
    }

    private static int ReadPort(string? value, int defaultPort)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return defaultPort;
        }

        if (!int.TryParse(value, out var port) || port is < 1 or > 65535)
        {
            throw new InvalidOperationException(
                "Database:Port debe ser un puerto TCP valido.");
        }

        return port;
    }

    private static bool ReadBoolean(string? value, bool defaultValue)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return defaultValue;
        }

        if (!bool.TryParse(value, out var result))
        {
            throw new InvalidOperationException(
                "Secrets:RequireExternal debe ser true o false.");
        }

        return result;
    }
}
