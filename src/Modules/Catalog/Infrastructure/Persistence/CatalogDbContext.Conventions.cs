using Microsoft.EntityFrameworkCore;
using MusicaAprender.BuildingBlocks.Infrastructure.Database.Modeling;

namespace MusicaAprender.Modules.Catalog.Infrastructure.Persistence;

public partial class CatalogDbContext
{
    // La declaracion partial generada por EF Core es de instancia; no puede hacerse static.
#pragma warning disable CA1822
    partial void OnModelCreatingPartial(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyPhysicalSchemaConventions("catalog");
    }
#pragma warning restore CA1822
}
