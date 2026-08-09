using MusicaAprender.ObjectStoreVerifier;

var options = ObjectStoreVerificationOptions.Parse(args);

Console.WriteLine(
    "Verificando IObjectStore privado, cifrado, checksum, metadatos y autorizacion...");

await ObjectStoreChecks.RunAsync(options);

Console.WriteLine(
    "OK: BL-MVP-016 almacenamiento privado verificado.");
