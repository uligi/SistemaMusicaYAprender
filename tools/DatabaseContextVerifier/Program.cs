using MusicaAprender.DatabaseContextVerifier;

var options = ContextVerificationOptions.Parse(args);
var checks = new TransactionContextChecks(options);

Console.WriteLine("Verificando contexto transaccional RLS y limpieza de pool...");
await checks.RunAsync();
Console.WriteLine("OK: BL-MVP-013 contexto transaccional RLS verificado.");
