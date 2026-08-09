using MusicaAprender.DatabaseModelVerifier;

var options = ModelVerificationOptions.Parse(args);
var checks = new DatabaseModelChecks(options);

Console.WriteLine("Verificando nueve modelos EF Core contra PostgreSQL 18...");
await checks.RunAsync();
Console.WriteLine("OK: BL-MVP-014 modelo EF Core por esquema verificado.");
