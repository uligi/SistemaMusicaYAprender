using System.Globalization;
using MailKit.Net.Smtp;
using MimeKit;
using MusicaAprender.BuildingBlocks.Contracts.Email;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Email.Smtp;

public sealed class MailKitEmailSender(SmtpOptions options)
    : IEmailSender
{
    private readonly SmtpOptions _options =
        options ?? throw new ArgumentNullException(nameof(options));

    public async Task SendAsync(
        RenderedEmailMessage message,
        EmailDeliveryContext context,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(message);
        ArgumentNullException.ThrowIfNull(context);

        ValidateMessage(message);

        var mimeMessage = new MimeMessage();

        mimeMessage.From.Add(
            new MailboxAddress(
                _options.FromDisplayName,
                _options.FromAddress));

        mimeMessage.To.Add(
            MailboxAddress.Parse(
                message.RecipientAddress));

        mimeMessage.Subject = message.Subject;
        mimeMessage.MessageId =
            $"{context.DeliveryId:N}@musica-aprender.local";

        mimeMessage.Headers.Add(
            "X-MusicaAprender-Template-Code",
            context.TemplateCode);
        mimeMessage.Headers.Add(
            "X-MusicaAprender-Template-Version",
            context.TemplateVersion.ToString(
                CultureInfo.InvariantCulture));
        mimeMessage.Headers.Add(
            "X-MusicaAprender-Correlation-Id",
            context.CorrelationId.ToString("D"));

        var bodyBuilder = new BodyBuilder
        {
            TextBody = message.TextBody
        };

        if (!string.IsNullOrWhiteSpace(message.HtmlBody))
        {
            bodyBuilder.HtmlBody = message.HtmlBody;
        }

        mimeMessage.Body = bodyBuilder.ToMessageBody();

        using var client = new SmtpClient
        {
            Timeout = _options.TimeoutMilliseconds
        };

        await client.ConnectAsync(
            _options.Host,
            _options.Port,
            _options.SocketOptions,
            cancellationToken);

        await client.SendAsync(
            mimeMessage,
            cancellationToken);

        await client.DisconnectAsync(
            true,
            cancellationToken);
    }

    private static void ValidateMessage(
        RenderedEmailMessage message)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(
            message.RecipientAddress);
        ArgumentException.ThrowIfNullOrWhiteSpace(
            message.Subject);
        ArgumentException.ThrowIfNullOrWhiteSpace(
            message.TextBody);

        if (message.Subject.Contains('\r')
            || message.Subject.Contains('\n'))
        {
            throw new ArgumentException(
                "Subject no puede contener saltos de linea.",
                nameof(message));
        }

        if (message.Subject.Length > 200)
        {
            throw new ArgumentException(
                "Subject no puede exceder 200 caracteres.",
                nameof(message));
        }

        if (message.TextBody.Length > 1_000_000
            || (message.HtmlBody?.Length ?? 0) > 1_000_000)
        {
            throw new ArgumentException(
                "El cuerpo del correo excede el limite interno permitido.",
                nameof(message));
        }
    }
}
