using MusicaAprender.BuildingBlocks.Contracts.Email;

namespace MusicaAprender.EmailDeliveryVerifier;

internal sealed class SyntheticVerificationEmailTemplate
    : IVersionedEmailTemplate
{
    public const string Code = "ACCOUNT_VERIFICATION";
    public const int Version = 1;
    public const string Language = "es";

    public string TemplateCode => Code;

    public int TemplateVersion => Version;

    public string LanguageTag => Language;

    public Task<RenderedEmailMessage> RenderAsync(
        EmailDeliveryContext context,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var subject =
            $"[BL017][ACCOUNT_VERIFICATION:v1] {context.DeliveryId:N}";

        var message = new RenderedEmailMessage(
            $"bl017-{context.DeliveryId:N}@example.test",
            subject,
            "Mensaje sintetico BL-MVP-017. No contiene tokens ni datos personales.");

        return Task.FromResult(message);
    }
}
