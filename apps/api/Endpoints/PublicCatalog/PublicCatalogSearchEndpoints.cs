using MusicaAprender.Modules.Catalog.Infrastructure.Search;

namespace MusicaAprender.Api.Endpoints.PublicCatalog;

public static class PublicCatalogSearchEndpoints
{
    public static IEndpointRouteBuilder MapPublicCatalogSearch(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapGet(
            "/api/v1/public/catalog/search",
            SearchAsync);

        return endpoints;
    }

    private static async Task<IResult> SearchAsync(
        string? query,
        string? territory,
        string? language,
        int? pageSize,
        string? cursor,
        PublicCatalogSearchService service,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        try
        {
            var page = await service.SearchAsync(
                query,
                territory ?? string.Empty,
                language,
                pageSize,
                cursor,
                cancellationToken);

            httpContext.Response.Headers["Cache-Control"] = "no-store";

            return Results.Ok(page);
        }
        catch (ArgumentException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Consulta de catálogo inválida",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "catalog.public-search.invalid-query"
                });
        }
    }
}
