using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Konscious.Security.Cryptography;
using Microsoft.Extensions.Configuration;

namespace MusicaAprender.Modules.Security.Infrastructure.Credentials;

public sealed class Argon2idPasswordHasher
{
    public const string Algorithm = "ARGON2ID";
    private const int Argon2Version = 19;
    private const int MinimumMemorySizeKiB = 19 * 1024;
    private const int MaximumMemorySizeKiB = 1024 * 1024;
    private const int MinimumIterations = 2;
    private const int MaximumIterations = 10;
    private const int MaximumParallelism = 16;
    private const int MinimumSaltLength = 16;
    private const int MaximumSaltLength = 64;
    private const int MinimumHashLength = 32;
    private const int MaximumHashLength = 64;
    private const string ConfigurationPrefix = "PasswordHashing:Argon2id:";
    private static readonly JsonSerializerOptions ParameterJsonOptions =
        new(JsonSerializerDefaults.Web);

    private readonly Argon2idPasswordHashingOptions _options;

    public Argon2idPasswordHasher(Argon2idPasswordHashingOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        ValidateParameters(
            options.MemorySizeKiB,
            options.Iterations,
            options.Parallelism,
            options.SaltLength,
            options.HashLength);
        _options = options;
    }

    public static Argon2idPasswordHasher FromConfiguration(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var defaults = new Argon2idPasswordHashingOptions();
        return new Argon2idPasswordHasher(
            new Argon2idPasswordHashingOptions(
                ReadInteger(configuration, "MemorySizeKiB", defaults.MemorySizeKiB),
                ReadInteger(configuration, "Iterations", defaults.Iterations),
                ReadInteger(configuration, "Parallelism", defaults.Parallelism),
                ReadInteger(configuration, "SaltLength", defaults.SaltLength),
                ReadInteger(configuration, "HashLength", defaults.HashLength)));
    }

    public PasswordCredential CreateCredential(string normalizedPassword)
    {
        ArgumentNullException.ThrowIfNull(normalizedPassword);

        var salt = RandomNumberGenerator.GetBytes(_options.SaltLength);
        var hash = Derive(
            normalizedPassword,
            salt,
            _options.MemorySizeKiB,
            _options.Iterations,
            _options.Parallelism,
            _options.HashLength);

        try
        {
            var parameters = new StoredArgon2idParameters(
                Argon2Version,
                _options.MemorySizeKiB,
                _options.Iterations,
                _options.Parallelism,
                _options.HashLength,
                Convert.ToBase64String(salt),
                "NFC",
                PasswordPolicy.Version);

            return new PasswordCredential(
                Algorithm,
                Convert.ToBase64String(hash),
                JsonSerializer.Serialize(parameters, ParameterJsonOptions));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(salt);
            CryptographicOperations.ZeroMemory(hash);
        }
    }

    public static bool Verify(
        string? candidate,
        string? algorithm,
        string? storedHash,
        string? storedParameters)
    {
        if (string.IsNullOrEmpty(candidate)
            || !string.Equals(algorithm, Algorithm, StringComparison.Ordinal)
            || string.IsNullOrWhiteSpace(storedHash)
            || string.IsNullOrWhiteSpace(storedParameters)
            || storedHash.Length > 256
            || storedParameters.Length > 2048)
        {
            return false;
        }

        string normalized;
        try
        {
            normalized = candidate.Normalize(NormalizationForm.FormC);
        }
        catch (ArgumentException)
        {
            return false;
        }

        StoredArgon2idParameters? parameters;
        byte[] expectedHash;
        byte[] salt;
        try
        {
            parameters = JsonSerializer.Deserialize<StoredArgon2idParameters>(
                storedParameters,
                ParameterJsonOptions);
            expectedHash = Convert.FromBase64String(storedHash);
            salt = parameters is null || parameters.Salt.Length > 128
                ? []
                : Convert.FromBase64String(parameters.Salt);
        }
        catch (Exception exception) when (
            exception is JsonException or FormatException or ArgumentNullException)
        {
            return false;
        }

        try
        {
            if (parameters is null
                || parameters.Version != Argon2Version
                || parameters.Normalization != "NFC"
                || expectedHash.Length != parameters.HashLength
                || !ParametersAreSafe(parameters, salt.Length))
            {
                return false;
            }

            var actualHash = Derive(
                normalized,
                salt,
                parameters.MemorySizeKiB,
                parameters.Iterations,
                parameters.Parallelism,
                parameters.HashLength);

            try
            {
                return CryptographicOperations.FixedTimeEquals(actualHash, expectedHash);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(actualHash);
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(expectedHash);
            CryptographicOperations.ZeroMemory(salt);
        }
    }

    private static byte[] Derive(
        string normalizedPassword,
        byte[] salt,
        int memorySizeKiB,
        int iterations,
        int parallelism,
        int hashLength)
    {
        var passwordBytes = Encoding.UTF8.GetBytes(normalizedPassword);
        try
        {
            using var argon2 = new Argon2id(passwordBytes)
            {
                Salt = salt,
                MemorySize = memorySizeKiB,
                Iterations = iterations,
                DegreeOfParallelism = parallelism
            };

            return argon2.GetBytes(hashLength);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(passwordBytes);
        }
    }

    private static bool ParametersAreSafe(
        StoredArgon2idParameters parameters,
        int saltLength)
    {
        try
        {
            ValidateParameters(
                parameters.MemorySizeKiB,
                parameters.Iterations,
                parameters.Parallelism,
                saltLength,
                parameters.HashLength);
            return true;
        }
        catch (ArgumentOutOfRangeException)
        {
            return false;
        }
    }

    private static void ValidateParameters(
        int memorySizeKiB,
        int iterations,
        int parallelism,
        int saltLength,
        int hashLength)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(memorySizeKiB, MinimumMemorySizeKiB);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(memorySizeKiB, MaximumMemorySizeKiB);
        ArgumentOutOfRangeException.ThrowIfLessThan(iterations, MinimumIterations);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(iterations, MaximumIterations);
        ArgumentOutOfRangeException.ThrowIfLessThan(parallelism, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(parallelism, MaximumParallelism);
        ArgumentOutOfRangeException.ThrowIfLessThan(saltLength, MinimumSaltLength);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(saltLength, MaximumSaltLength);
        ArgumentOutOfRangeException.ThrowIfLessThan(hashLength, MinimumHashLength);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(hashLength, MaximumHashLength);
    }

    private static int ReadInteger(
        IConfiguration configuration,
        string suffix,
        int defaultValue)
    {
        var key = ConfigurationPrefix + suffix;
        var value = configuration[key];
        if (string.IsNullOrWhiteSpace(value))
        {
            return defaultValue;
        }

        if (!int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var parsed))
        {
            throw new InvalidOperationException($"'{key}' debe contener un entero valido.");
        }

        return parsed;
    }

    private sealed record StoredArgon2idParameters(
        [property: JsonPropertyName("v")] int Version,
        [property: JsonPropertyName("m")] int MemorySizeKiB,
        [property: JsonPropertyName("t")] int Iterations,
        [property: JsonPropertyName("p")] int Parallelism,
        [property: JsonPropertyName("l")] int HashLength,
        [property: JsonPropertyName("s")] string Salt,
        [property: JsonPropertyName("n")] string Normalization,
        [property: JsonPropertyName("policy")] string Policy);
}

public sealed record Argon2idPasswordHashingOptions(
    int MemorySizeKiB = 65_536,
    int Iterations = 3,
    int Parallelism = 1,
    int SaltLength = 16,
    int HashLength = 32);

public sealed record PasswordCredential(
    string Algorithm,
    string Hash,
    string Parameters);
