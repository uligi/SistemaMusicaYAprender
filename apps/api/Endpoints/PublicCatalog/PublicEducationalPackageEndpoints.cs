using MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;

namespace MusicaAprender.Api.Endpoints.PublicCatalog;

public static class PublicEducationalPackageEndpoints
{
    public static IEndpointRouteBuilder MapPublicEducationalPackage(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapGet(
            "/api/v1/public/catalog/songs/{slug}/learning-package",
            ReadAsync);

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        string slug,
        string? territory,
        string? language,
        PublicEducationalPackageService service,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        httpContext.Response.Headers["Cache-Control"] = "public, no-cache";

        try
        {
            var package = await service.ReadAsync(
                slug,
                territory ?? string.Empty,
                language,
                cancellationToken);

            if (package is null)
            {
                return Results.NotFound();
            }

            var etag = BuildEtag(package.PublicationChecksumSha256);
            httpContext.Response.Headers.ETag = etag;

            if (MatchesIfNoneMatch(
                    httpContext.Request.Headers.IfNoneMatch.ToString(),
                    etag))
            {
                return Results.StatusCode(
                    StatusCodes.Status304NotModified);
            }

            return Results.Ok(package);
        }
        catch (AmbiguousPublicEducationalPackageException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Paquete educativo ambiguo",
                detail:
                    "Existe más de una publicación elegible. No se mezclará contenido entre publicaciones.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-package.ambiguous"
                });
        }
        catch (IncompatiblePublicEducationalPackageException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Paquete educativo incompatible",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-package.incompatible"
                });
        }
        catch (ArgumentException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Ruta pública de paquete inválida",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "content.public-package.invalid-route"
                });
        }
    }

    private static string BuildEtag(string checksum) =>
        $"\"sha256-{checksum.ToLowerInvariant()}\"";

    private static bool MatchesIfNoneMatch(
        string header,
        string currentEtag)
    {
        if (string.IsNullOrWhiteSpace(header))
        {
            return false;
        }

        return header
            .Split(',', StringSplitOptions.RemoveEmptyEntries)
            .Select(static item => item.Trim())
            .Any(item =>
                item == "*"
                || string.Equals(
                    item,
                    currentEtag,
                    StringComparison.Ordinal));
    }
}
