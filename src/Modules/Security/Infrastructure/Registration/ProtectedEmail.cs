namespace MusicaAprender.Modules.Security.Infrastructure.Registration;

public sealed record ProtectedEmail(
    ReadOnlyMemory<byte> LookupHash,
    ReadOnlyMemory<byte> Ciphertext);
