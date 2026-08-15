using MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

namespace MusicaAprender.Api.Endpoints.PublicCatalog;

public static class PublicSongLearningLayersEndpoints
{
    public static IEndpointRouteBuilder MapPublicSongLearningLayers(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapGet(
            "/api/v1/public/catalog/songs/{slug}/layers",
            ReadAsync);

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        string slug,
        string? territory,
        string? language,
        PublicSongLearningLayersService service,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        httpContext.Response.Headers["Cache-Control"] = "no-store";

        try
        {
            var layers = await service.ReadAsync(
                slug,
                territory ?? string.Empty,
                language,
                cancellationToken);

            return layers is null
                ? Results.NotFound()
                : Results.Ok(layers);
        }
        catch (AmbiguousPublicLearningLayersException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Capas educativas no disponibles de forma segura",
                detail:
                    "La publicación no puede resolverse de forma unívoca. No se mezclarán revisiones educativas.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-layers.ambiguous"
                });
        }
        catch (IncompatiblePublicLearningLayersException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Capas educativas incompatibles",
                detail:
                    "La letra, traducción o análisis publicados no pertenecen a la misma revisión. Se conserva un estado seguro.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-layers.incompatible"
                });
        }
        catch (ArgumentException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Ruta pública de capas inválida",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-layers.invalid-route"
                });
        }
    }
}
