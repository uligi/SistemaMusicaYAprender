using System.Globalization;
using System.Net.Sockets;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace MusicaAprender.Api.Health;

internal sealed class SmtpHealthCheck : IHealthCheck
{
    private readonly IConfiguration _configuration;

    public SmtpHealthCheck(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var host = _configuration["Dependencies:SmtpHost"];
        var portText = _configuration["Dependencies:SmtpPort"];

        if (string.IsNullOrWhiteSpace(host) ||
            !int.TryParse(
                portText,
                NumberStyles.None,
                CultureInfo.InvariantCulture,
                out var port) ||
            port is < 1 or > 65535)
        {
            return Failure(context, "SMTP health configuration is missing or invalid.");
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(HealthConstants.DependencyTimeout);

        try
        {
            using var client = new TcpClient();
            await client.ConnectAsync(host, port, timeout.Token);

            return client.Connected
                ? HealthCheckResult.Healthy("SMTP service is reachable.")
                : Failure(context, "SMTP service is unavailable.");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return Failure(context, "SMTP service did not answer in time.");
        }
        catch (SocketException)
        {
            return Failure(context, "SMTP service is unavailable.");
        }
        catch (ArgumentException)
        {
            return Failure(context, "SMTP health configuration is invalid.");
        }
        catch (InvalidOperationException)
        {
            return Failure(context, "SMTP service is unavailable.");
        }
    }

    private static HealthCheckResult Failure(
        HealthCheckContext context,
        string description)
    {
        return new HealthCheckResult(
            context.Registration.FailureStatus,
            description);
    }
}
