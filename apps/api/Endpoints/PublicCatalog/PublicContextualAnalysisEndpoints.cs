using MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

namespace MusicaAprender.Api.Endpoints.PublicCatalog;

public static class PublicContextualAnalysisEndpoints
{
    public static IEndpointRouteBuilder MapPublicContextualAnalysis(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapGet(
            "/api/v1/public/catalog/songs/{slug}/analysis/{token}",
            ReadAsync);

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        string slug,
        string token,
        string? territory,
        string? language,
        PublicContextualAnalysisService service,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        httpContext.Response.Headers["Cache-Control"] = "no-store";

        try
        {
            var analysis = await service.ReadAsync(
                slug,
                token,
                territory ?? string.Empty,
                language,
                cancellationToken);

            return analysis is null
                ? Results.NotFound()
                : Results.Ok(analysis);
        }
        catch (AmbiguousPublicContextualAnalysisException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Análisis contextual no disponible de forma segura",
                detail:
                    "La publicación o el token no puede resolverse de forma unívoca. No se mezclará otro análisis.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-analysis.ambiguous"
                });
        }
        catch (IncompatiblePublicContextualAnalysisException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Análisis contextual incompatible",
                detail:
                    "El análisis publicado no corresponde a la revisión japonesa activa. Se conserva un estado seguro.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-analysis.incompatible"
                });
        }
        catch (ArgumentException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Ruta de análisis contextual inválida",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-analysis.invalid-route"
                });
        }
    }
}
