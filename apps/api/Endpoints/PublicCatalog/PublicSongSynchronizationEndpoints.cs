using MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

namespace MusicaAprender.Api.Endpoints.PublicCatalog;

public static class PublicSongSynchronizationEndpoints
{
    public static IEndpointRouteBuilder MapPublicSongSynchronization(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapGet(
            "/api/v1/public/catalog/songs/{slug}/synchronization",
            ReadAsync);

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        string slug,
        string? territory,
        string? language,
        PublicSongSynchronizationService service,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        try
        {
            var synchronization = await service.ReadAsync(
                slug,
                territory ?? string.Empty,
                language,
                cancellationToken);

            httpContext.Response.Headers["Cache-Control"] = "no-store";

            return synchronization is null
                ? Results.NotFound()
                : Results.Ok(synchronization);
        }
        catch (AmbiguousPublicSynchronizationException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Sincronización no disponible de forma segura",
                detail: "La publicación no puede resolverse de forma unívoca. No se activará una línea potencialmente incorrecta.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-synchronization.ambiguous"
                });
        }
        catch (IncompatiblePublicSynchronizationException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Sincronización incompatible",
                detail: "La revisión temporal publicada no coincide con la fuente o la letra exactas. El reproductor puede degradarse sin activar contenido incorrecto.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-synchronization.incompatible"
                });
        }
        catch (ArgumentException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Ruta pública de sincronización inválida",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-synchronization.invalid-route"
                });
        }
    }
}
