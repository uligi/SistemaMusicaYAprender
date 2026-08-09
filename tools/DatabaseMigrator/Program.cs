using Microsoft.EntityFrameworkCore;
using MusicaAprender.DatabaseMigrator;
using Npgsql;

var migrationOptions = MigrationCommandLine.Parse(args);

var password = File.ReadAllText(migrationOptions.PasswordFile).Trim();
if (password.Length < 1)
{
    throw new InvalidOperationException("El archivo de secreto PostgreSQL esta vacio.");
}

var connectionString = new NpgsqlConnectionStringBuilder
{
    Host = migrationOptions.Host,
    Port = migrationOptions.Port,
    Database = migrationOptions.Database,
    Username = migrationOptions.Username,
    Password = password,
    IncludeErrorDetail = false,
    Pooling = false,
    Timeout = 15
}.ConnectionString;

var dbContextOptions = new DbContextOptionsBuilder<PhysicalSchemaDbContext>()
    .UseNpgsql(
        connectionString,
        postgres =>
        {
            postgres.CommandTimeout(900);
            postgres.MigrationsAssembly(typeof(PhysicalSchemaDbContext).Assembly.FullName);

            // BL-MVP-012A:
            // La identidad de migracion usa un search_path endurecido. EF Core no debe
            // resolver __EFMigrationsHistory contra pg_catalog; su ubicacion fisica es
            // explicitamente public y CREATE sobre public pertenece solo a jp_migrator.
            postgres.MigrationsHistoryTable("__EFMigrationsHistory", "public");
        })
    .Options;

using var context = new PhysicalSchemaDbContext(dbContextOptions);

Console.WriteLine("Aplicando migraciones fisicas aprobadas...");
context.Database.Migrate();
Console.WriteLine("OK: migracion fisica EF Core aplicada.");
