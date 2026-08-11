using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace MusicaAprender.Modules.Security.Infrastructure.Mfa;

public static class TotpService
{
    public const int Digits = 6;
    public const int PeriodSeconds = 30;
    public const int SecretLengthBytes = 20;
    public const int AllowedClockSkewSteps = 1;

    private const string Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    public static byte[] CreateSecret() =>
        RandomNumberGenerator.GetBytes(SecretLengthBytes);

    public static string EncodeBase32(ReadOnlySpan<byte> value)
    {
        if (value.IsEmpty)
        {
            throw new ArgumentException("El secreto TOTP no puede estar vacío.", nameof(value));
        }

        var builder = new StringBuilder((value.Length * 8 + 4) / 5);
        var buffer = 0;
        var bitsLeft = 0;

        foreach (var current in value)
        {
            buffer = (buffer << 8) | current;
            bitsLeft += 8;

            while (bitsLeft >= 5)
            {
                bitsLeft -= 5;
                builder.Append(Alphabet[(buffer >> bitsLeft) & 31]);
            }
        }

        if (bitsLeft > 0)
        {
            builder.Append(Alphabet[(buffer << (5 - bitsLeft)) & 31]);
        }

        return builder.ToString();
    }

    public static byte[] DecodeBase32(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return [];
        }

        var normalized = value
            .Trim()
            .Replace(" ", string.Empty, StringComparison.Ordinal)
            .Replace("-", string.Empty, StringComparison.Ordinal)
            .TrimEnd('=')
            .ToUpperInvariant();

        if (normalized.Length is < 16 or > 128)
        {
            return [];
        }

        var output = new byte[(normalized.Length * 5) / 8];
        var outputIndex = 0;
        var buffer = 0;
        var bitsLeft = 0;

        foreach (var character in normalized)
        {
            var alphabetIndex = Alphabet.IndexOf(character);
            if (alphabetIndex < 0)
            {
                CryptographicOperations.ZeroMemory(output);
                return [];
            }

            buffer = (buffer << 5) | alphabetIndex;
            bitsLeft += 5;

            if (bitsLeft < 8)
            {
                continue;
            }

            bitsLeft -= 8;
            if (outputIndex < output.Length)
            {
                output[outputIndex++] = (byte)(buffer >> bitsLeft);
            }
        }

        if (outputIndex != output.Length)
        {
            CryptographicOperations.ZeroMemory(output);
            return [];
        }

        return output;
    }

    public static TotpVerificationResult Verify(
        ReadOnlySpan<byte> secret,
        string? candidate,
        DateTimeOffset now)
    {
        if (secret.Length < 16
            || string.IsNullOrWhiteSpace(candidate)
            || candidate.Length != Digits
            || candidate.Any(static character => !char.IsAsciiDigit(character)))
        {
            return TotpVerificationResult.Invalid;
        }

        var expectedBytes = new byte[Digits];
        var candidateBytes = Encoding.ASCII.GetBytes(candidate);

        try
        {
            var currentCounter = now.ToUnixTimeSeconds() / PeriodSeconds;

            for (var offset = -AllowedClockSkewSteps; offset <= AllowedClockSkewSteps; offset++)
            {
                var counter = checked(currentCounter + offset);
                var expected = Generate(secret, counter);

                for (var index = Digits - 1; index >= 0; index--)
                {
                    expectedBytes[index] = (byte)('0' + expected % 10);
                    expected /= 10;
                }

                if (CryptographicOperations.FixedTimeEquals(expectedBytes, candidateBytes))
                {
                    return new TotpVerificationResult(true, counter);
                }
            }

            return TotpVerificationResult.Invalid;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(expectedBytes);
            CryptographicOperations.ZeroMemory(candidateBytes);
        }
    }

    public static string GenerateCode(
        ReadOnlySpan<byte> secret,
        DateTimeOffset now)
    {
        var counter = now.ToUnixTimeSeconds() / PeriodSeconds;
        return Generate(secret, counter).ToString(
            "D6",
            System.Globalization.CultureInfo.InvariantCulture);
    }

    private static int Generate(
        ReadOnlySpan<byte> secret,
        long counter)
    {
        Span<byte> counterBytes = stackalloc byte[8];
        BinaryPrimitives.WriteInt64BigEndian(counterBytes, counter);

        var key = secret.ToArray();
        byte[] digest;

        try
        {
#pragma warning disable CA5350 // TOTP RFC 6238 interoperability uses HMAC-SHA1 by policy.
            using var hmac = new HMACSHA1(key);
#pragma warning restore CA5350
            digest = hmac.ComputeHash(counterBytes.ToArray());
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }

        try
        {
            var offset = digest[^1] & 0x0f;
            var binary =
                ((digest[offset] & 0x7f) << 24)
                | ((digest[offset + 1] & 0xff) << 16)
                | ((digest[offset + 2] & 0xff) << 8)
                | (digest[offset + 3] & 0xff);

            return binary % 1_000_000;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(digest);
        }
    }
}

public readonly record struct TotpVerificationResult(
    bool Valid,
    long Counter)
{
    public static TotpVerificationResult Invalid => new(false, 0);
}
