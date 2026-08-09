using Microsoft.EntityFrameworkCore;

namespace MusicaAprender.DatabaseMigrator;

public sealed class PhysicalSchemaDbContext(
    DbContextOptions<PhysicalSchemaDbContext> options)
    : DbContext(options);
