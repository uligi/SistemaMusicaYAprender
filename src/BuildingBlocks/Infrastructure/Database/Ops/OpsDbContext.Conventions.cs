using Microsoft.EntityFrameworkCore;
using MusicaAprender.BuildingBlocks.Infrastructure.Database.Modeling;

namespace MusicaAprender.BuildingBlocks.Infrastructure.Database.Ops;

public partial class OpsDbContext
{
    // La declaracion partial generada por EF Core es de instancia; no puede hacerse static.
#pragma warning disable CA1822
    partial void OnModelCreatingPartial(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyPhysicalSchemaConventions("ops");
    }
#pragma warning restore CA1822
}
