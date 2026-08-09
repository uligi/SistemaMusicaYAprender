using Microsoft.EntityFrameworkCore;
using MusicaAprender.BuildingBlocks.Infrastructure.Database.Modeling;

namespace MusicaAprender.Modules.Progress.Infrastructure.Persistence;

public partial class ProgressDbContext
{
    // La declaracion partial generada por EF Core es de instancia; no puede hacerse static.
#pragma warning disable CA1822
    partial void OnModelCreatingPartial(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyPhysicalSchemaConventions("progress");
    }
#pragma warning restore CA1822
}
