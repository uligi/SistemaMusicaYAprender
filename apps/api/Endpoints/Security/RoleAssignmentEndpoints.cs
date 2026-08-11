using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Security.Infrastructure.Administration;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Security;

public sealed record GrantRoleAssignmentRequest(
    Guid AccountId,
    string RoleCode,
    Guid? ScopeId,
    DateTimeOffset? ValidUntil,
    string Reason);

public sealed record RevokeRoleAssignmentRequest(
    string Reason);

public static class RoleAssignmentEndpoints
{
    public static IEndpointRouteBuilder MapRoleAssignments(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/security/role-assignments/catalog",
                ReadCatalogAsync)
            .RequireEffectivePermission("SECURITY.MANAGE_ROLES")
            .WithName("ReadRoleAssignmentCatalog")
            .WithTags("Security");

        endpoints.MapGet(
                "/api/v1/security/role-assignments/{accountId:guid}",
                ListAsync)
            .RequireEffectivePermission("SECURITY.MANAGE_ROLES")
            .WithName("ListRoleAssignments")
            .WithTags("Security");

        endpoints.MapPost(
                "/api/v1/security/role-assignments",
                GrantAsync)
            .RequireEffectivePermission("SECURITY.MANAGE_ROLES")
            .WithName("GrantRoleAssignment")
            .WithTags("Security");

        endpoints.MapPost(
                "/api/v1/security/role-assignments/{assignmentId:guid}/revoke",
                RevokeAsync)
            .RequireEffectivePermission("SECURITY.MANAGE_ROLES")
            .WithName("RevokeRoleAssignment")
            .WithTags("Security");

        return endpoints;
    }

    private static async Task<IResult> ReadCatalogAsync(
        HttpContext httpContext,
        RoleAssignmentAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            return Results.Ok(
                await service.ReadCatalogAsync(
                    actorId,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted));
        }
        catch (RoleAssignmentAdministrationException exception)
        {
            return Problem(exception);
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

    private static async Task<IResult> ListAsync(
        Guid accountId,
        HttpContext httpContext,
        RoleAssignmentAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            return Results.Ok(
                await service.ListAsync(
                    actorId,
                    accountId,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted));
        }
        catch (RoleAssignmentAdministrationException exception)
        {
            return Problem(exception);
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

    private static async Task<IResult> GrantAsync(
        GrantRoleAssignmentRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        RoleAssignmentAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var result = await service.GrantAsync(
                actorId,
                new GrantRoleAssignmentCommand(
                    request.AccountId,
                    request.RoleCode,
                    request.ScopeId,
                    request.ValidUntil,
                    request.Reason),
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            return result.AlreadyApplied
                ? Results.Ok(result)
                : Results.Created(
                    $"/api/v1/security/role-assignments/{result.Assignment.AccountId:D}",
                    result);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (RoleAssignmentAdministrationException exception)
        {
            return Problem(exception);
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

    private static async Task<IResult> RevokeAsync(
        Guid assignmentId,
        RevokeRoleAssignmentRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        RoleAssignmentAdministrationService service)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var result = await service.RevokeAsync(
                actorId,
                new RevokeRoleAssignmentCommand(
                    assignmentId,
                    request.Reason),
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            return Results.Ok(result);
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
        catch (RoleAssignmentAdministrationException exception)
        {
            return Problem(exception);
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

    private static bool TryActor(
        HttpContext context,
        out Guid actorId)
    {
        var value = context.User.FindFirstValue("account_id");
        return Guid.TryParse(value, out actorId)
            && actorId != Guid.Empty;
    }

    private static IResult Problem(
        RoleAssignmentAdministrationException exception)
    {
        var status = exception.Code switch
        {
            "security.authorization.denied" =>
                StatusCodes.Status403Forbidden,
            "security.role-assignment.not-found" =>
                StatusCodes.Status404NotFound,
            "security.role-assignment.target.unavailable" =>
                StatusCodes.Status404NotFound,
            "security.role-assignment.overlap" =>
                StatusCodes.Status409Conflict,
            "security.role-assignment.self-change" =>
                StatusCodes.Status409Conflict,
            "security.role-assignment.future-revoke" =>
                StatusCodes.Status409Conflict,
            _ => StatusCodes.Status400BadRequest
        };

        return Results.Problem(
            statusCode: status,
            title: status == StatusCodes.Status409Conflict
                ? "Cambio de rol no aplicable"
                : "Solicitud de rol no válida",
            detail: exception.Message,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = exception.Code
            });
    }

    private static IResult CsrfInvalid() =>
        Results.Problem(
            statusCode: StatusCodes.Status400BadRequest,
            title: "Solicitud no válida",
            detail: "Actualiza la página y vuelve a intentarlo.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "security.role-assignment.csrf.invalid"
            });

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Administración temporalmente no disponible",
            detail:
                "No se aplicó ningún cambio de acceso. "
                + "Vuelve a intentarlo más tarde.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "security.role-assignment.unavailable"
            });
}
