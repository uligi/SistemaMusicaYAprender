namespace MusicaAprender.BuildingBlocks.Contracts.Email;

public interface IVersionedEmailTemplate
{
    string TemplateCode { get; }

    int TemplateVersion { get; }

    string LanguageTag { get; }

    Task<RenderedEmailMessage> RenderAsync(
        EmailDeliveryContext context,
        CancellationToken cancellationToken = default);
}
