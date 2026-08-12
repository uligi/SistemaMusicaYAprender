using MusicaAprender.Modules.Catalog.Infrastructure.Search;

namespace MusicaAprender.Api.Endpoints.PublicCatalog;

public static class PublicSongDetailEndpoints
{
    public static IEndpointRouteBuilder MapPublicSongDetail(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapGet(
            "/api/v1/public/catalog/songs/{slug}",
            ReadAsync);

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        string slug,
        string? territory,
        string? language,
        PublicSongDetailService service,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        try
        {
            var detail = await service.ReadAsync(
                slug,
                territory ?? string.Empty,
                language,
                cancellationToken);

            httpContext.Response.Headers["Cache-Control"] = "no-store";

            return detail is null
                ? Results.NotFound()
                : Results.Ok(detail);
        }
        catch (AmbiguousPublicSongException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Cancion no disponible de forma segura",
                detail: "La ficha no puede resolverse de forma univoca. No se mostrara una combinacion potencialmente incorrecta.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "catalog.public-song.ambiguous"
                });
        }
        catch (ArgumentException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Ruta publica de cancion invalida",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "catalog.public-song.invalid-route"
                });
        }
    }
}
