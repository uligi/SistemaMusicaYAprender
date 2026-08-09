namespace MusicaAprender.BuildingBlocks.Contracts.Email;

public sealed record RenderedEmailMessage(
    string RecipientAddress,
    string Subject,
    string TextBody,
    string? HtmlBody = null);
