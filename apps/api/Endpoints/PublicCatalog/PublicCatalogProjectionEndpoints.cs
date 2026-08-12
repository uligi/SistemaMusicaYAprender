using MusicaAprender.Modules.Editorial.Infrastructure.PublicCatalog;

namespace MusicaAprender.Api.Endpoints.PublicCatalog;

public static class PublicCatalogProjectionEndpoints
{
    public static IEndpointRouteBuilder MapPublicCatalogProjection(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapGet(
            "/api/v1/public/catalog/publications/{publicationId:guid}/projection",
            ReadAsync);

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        Guid publicationId,
        string territory,
        string? language,
        PublicCatalogProjectionService service,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        try
        {
            var publication = await service.ReadEligibleAsync(
                publicationId,
                territory,
                language,
                cancellationToken);

            httpContext.Response.Headers["Cache-Control"] = "no-store";

            return publication is null
                ? Results.NotFound()
                : Results.Ok(publication);
        }
        catch (ArgumentException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Contexto público inválido",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "catalog.public-projection.invalid-context"
                });
        }
    }
}
