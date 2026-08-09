namespace MusicaAprender.BuildingBlocks.Contracts.Email;

public interface IEmailSender
{
    Task SendAsync(
        RenderedEmailMessage message,
        EmailDeliveryContext context,
        CancellationToken cancellationToken = default);
}
