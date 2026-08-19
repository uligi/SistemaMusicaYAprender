using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.Modules.Identity.Infrastructure.Profile;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Identity;

public sealed record ClaimPersonalUsernameRequest(
    string? Username);

public static class PersonalUsernameEndpoints
{
    public static IEndpointRouteBuilder MapPersonalUsername(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/profile/username",
                GetAsync)
            .RequireAuthorization()
            .WithName("GetPersonalUsername")
            .WithTags("Identity");

        endpoints.MapPost(
                "/api/v1/profile/username",
                ClaimAsync)
            .RequireAuthorization()
            .WithName("ClaimPersonalUsername")
            .WithTags("Identity");

        return endpoints;
    }

    private static async Task<IResult> GetAsync(
        HttpContext httpContext,
        IHttpDatabaseSessionContextFactory contextFactory,
        PersonalUsernameService service)
    {
        try
        {
            var context =
                contextFactory.CreateRequired(httpContext);
            var snapshot =
                await service.GetAsync(
                    context,
                    httpContext.RequestAborted);

            httpContext.Response.Headers.CacheControl =
                "private, no-store";
            return Results.Ok(snapshot);
        }
        catch (NpgsqlException)
        {
            return Unavailable();
        }
        catch (InvalidOperationException)
        {
            return Unavailable();
        }
    }

    private static async Task<IResult> ClaimAsync(
        ClaimPersonalUsernameRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        IHttpDatabaseSessionContextFactory contextFactory,
        PersonalUsernameService service)
    {
        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var context =
                contextFactory.CreateRequired(httpContext);
            var snapshot =
                await service.ClaimAsync(
                    context,
                    request.Username,
                    httpContext.RequestAborted);

            httpContext.Response.Headers.CacheControl =
                "private, no-store";
            return Results.Ok(snapshot);
        }
        catch (AntiforgeryValidationException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Solicitud no válida",
                detail:
                    "Actualiza la página y vuelve a confirmar el nombre de usuario.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "identity.username.csrf.invalid"
                });
        }
        catch (PersonalUsernameException exception)
        {
            return Results.Problem(
                statusCode: exception.StatusCode,
                title: exception.StatusCode == 409
                    ? "Nombre de usuario no disponible"
                    : "Nombre de usuario no válido",
                detail: exception.Message,
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = exception.Code
                });
        }
        catch (NpgsqlException)
        {
            return Unavailable();
        }
        catch (InvalidOperationException)
        {
            return Unavailable();
        }
    }

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Perfil temporalmente no disponible",
            detail:
                "No se cambió el nombre de usuario. Vuelve a intentarlo más tarde.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "identity.username.unavailable-service"
            });
}
