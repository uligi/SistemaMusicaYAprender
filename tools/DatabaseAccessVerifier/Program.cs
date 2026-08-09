using MusicaAprender.DatabaseAccessVerifier;

var options = AccessVerificationOptions.Parse(args);
var checks = new DatabaseAccessChecks(options);

Console.WriteLine("Verificando identidades PostgreSQL separadas...");
await checks.RunAsync();
Console.WriteLine("OK: BL-MVP-012 acceso PostgreSQL verificado.");
