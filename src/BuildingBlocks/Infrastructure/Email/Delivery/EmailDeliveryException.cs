namespace MusicaAprender.BuildingBlocks.Infrastructure.Email.Delivery;

public sealed class EmailDeliveryException : Exception
{
    public EmailDeliveryException(string errorCode)
        : base("La entrega de correo informo un fallo controlado.")
    {
        ErrorCode = EmailCode.RequireCode(errorCode, nameof(errorCode));
    }

    public string ErrorCode { get; }
}
