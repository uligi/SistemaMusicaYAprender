using MusicaAprender.DatabaseReliabilityVerifier;

var options = ReliabilityVerificationOptions.Parse(args);
var checks = new ReliabilityChecks(options);

Console.WriteLine("Verificando outbox, inbox e idempotencia contra PostgreSQL 18...");
await checks.RunAsync();
Console.WriteLine("OK: BL-MVP-015 outbox, inbox, idempotencia y reintentos verificados.");
