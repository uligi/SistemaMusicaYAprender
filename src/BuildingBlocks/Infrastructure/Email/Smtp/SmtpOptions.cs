using MailKit.Security;
using Microsoft.Extensions.Configuration;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Email.Smtp;

public sealed record SmtpOptions(
    string Host,
    int Port,
    string FromAddress,
    string FromDisplayName,
    SecureSocketOptions SocketOptions,
    int TimeoutMilliseconds)
{
    public static SmtpOptions FromConfiguration(
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var host = configuration["Smtp:Host"];

        if (string.IsNullOrWhiteSpace(host))
        {
            throw new InvalidOperationException(
                "Falta la configuracion no secreta Smtp:Host.");
        }

        var port = ReadInt(
            configuration["Smtp:Port"],
            25,
            1,
            65535,
            "Smtp:Port");

        var timeout = ReadInt(
            configuration["Smtp:TimeoutMilliseconds"],
            10000,
            1000,
            120000,
            "Smtp:TimeoutMilliseconds");

        var fromAddress =
            configuration["Smtp:FromAddress"]
            ?? "no-reply@musica-aprender.local";

        var fromDisplayName =
            configuration["Smtp:FromDisplayName"]
            ?? "Musica y Aprender";

        var security = ParseSecurity(
            configuration["Smtp:Security"]);

        return new SmtpOptions(
            host.Trim(),
            port,
            fromAddress.Trim(),
            fromDisplayName.Trim(),
            security,
            timeout);
    }

    private static SecureSocketOptions ParseSecurity(
        string? value)
    {
        if (string.IsNullOrWhiteSpace(value)
            || string.Equals(
                value,
                "None",
                StringComparison.OrdinalIgnoreCase))
        {
            return SecureSocketOptions.None;
        }

        if (string.Equals(
            value,
            "Auto",
            StringComparison.OrdinalIgnoreCase))
        {
            return SecureSocketOptions.Auto;
        }

        if (string.Equals(
            value,
            "StartTls",
            StringComparison.OrdinalIgnoreCase))
        {
            return SecureSocketOptions.StartTls;
        }

        if (string.Equals(
            value,
            "StartTlsWhenAvailable",
            StringComparison.OrdinalIgnoreCase))
        {
            return SecureSocketOptions.StartTlsWhenAvailable;
        }

        if (string.Equals(
            value,
            "SslOnConnect",
            StringComparison.OrdinalIgnoreCase))
        {
            return SecureSocketOptions.SslOnConnect;
        }

        throw new InvalidOperationException(
            "Smtp:Security debe ser None, Auto, StartTls, StartTlsWhenAvailable o SslOnConnect.");
    }

    private static int ReadInt(
        string? value,
        int defaultValue,
        int minimum,
        int maximum,
        string key)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return defaultValue;
        }

        if (!int.TryParse(value, out var parsed)
            || parsed < minimum
            || parsed > maximum)
        {
            throw new InvalidOperationException(
                $"{key} no contiene un entero valido.");
        }

        return parsed;
    }
}
