using MusicaAprender.BuildingBlocks.Infrastructure.Database;

namespace MusicaAprender.Api.Security;

internal interface IHttpDatabaseSessionContextFactory
{
    DatabaseSessionContext CreateRequired(HttpContext httpContext);
}
