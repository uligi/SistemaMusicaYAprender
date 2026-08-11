using System.Security.Claims;
using Microsoft.AspNetCore.Antiforgery;
using MusicaAprender.Modules.Security.Infrastructure.Mfa;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Security;

public sealed record BeginMfaEnrollmentRequest(
    string CurrentPassword);

public sealed record ConfirmMfaEnrollmentRequest(
    Guid ChallengeId,
    string Secret,
    string Code);

public sealed record ConfirmMfaStepUpRequest(
    Guid ChallengeId,
    string Code);

public sealed record MfaMethodPolicyResponse(
    string MethodType,
    bool EnrollmentAllowed,
    bool StepUpAllowed,
    int Digits,
    int PeriodSeconds,
    int ClockSkewSteps);

public sealed record MfaPolicyResponse(
    string Version,
    IReadOnlyList<MfaMethodPolicyResponse> Methods,
    string PrivilegedAssuranceLevel,
    int RecentAssuranceMinutes,
    int MaximumAttempts);

public static class PrivilegedMfaEndpoints
{
    public static IEndpointRouteBuilder MapPrivilegedMfa(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/security/mfa/status",
                ReadStatusAsync)
            .RequireAuthorization()
            .WithName("ReadMfaStatus")
            .WithTags("Security");

        endpoints.MapGet(
                "/api/v1/security/mfa/policy",
                ReadPolicy)
            .RequireAuthorization()
            .WithName("ReadMfaPolicy")
            .WithTags("Security");

        endpoints.MapPost(
                "/api/v1/security/mfa/enrollment/start",
                BeginEnrollmentAsync)
            .RequireAuthorization()
            .WithName("BeginMfaEnrollment")
            .WithTags("Security");

        endpoints.MapPost(
                "/api/v1/security/mfa/enrollment/confirm",
                ConfirmEnrollmentAsync)
            .RequireAuthorization()
            .WithName("ConfirmMfaEnrollment")
            .WithTags("Security");

        endpoints.MapPost(
                "/api/v1/security/mfa/step-up/start",
                BeginStepUpAsync)
            .RequireAuthorization()
            .WithName("BeginMfaStepUp")
            .WithTags("Security");

        endpoints.MapPost(
                "/api/v1/security/mfa/step-up/confirm",
                ConfirmStepUpAsync)
            .RequireAuthorization()
            .WithName("ConfirmMfaStepUp")
            .WithTags("Security");

        return endpoints;
    }

    private static IResult ReadPolicy() =>
        Results.Ok(
            new MfaPolicyResponse(
                PrivilegedMfaService.PolicyVersion,
                [
                    new MfaMethodPolicyResponse(
                        PrivilegedMfaService.MethodType,
                        EnrollmentAllowed: true,
                        StepUpAllowed: true,
                        TotpService.Digits,
                        TotpService.PeriodSeconds,
                        TotpService.AllowedClockSkewSteps)
                ],
                PrivilegedMfaService.AssuranceLevel,
                (int)PrivilegedMfaService.RecentAssuranceLifetime.TotalMinutes,
                PrivilegedMfaService.MaximumAttempts));

    private static async Task<IResult> ReadStatusAsync(
        HttpContext httpContext,
        PrivilegedMfaService service)
    {
        if (!TryActorSession(
                httpContext,
                out var accountId,
                out var sessionId))
        {
            return Results.Unauthorized();
        }

        return await ExecuteAsync(
            () => service.ReadStatusAsync(
                accountId,
                sessionId,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted));
    }

    private static async Task<IResult> BeginEnrollmentAsync(
        BeginMfaEnrollmentRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        PrivilegedMfaService service)
    {
        if (!TryActorSession(
                httpContext,
                out var accountId,
                out var sessionId))
        {
            return Results.Unauthorized();
        }

        var csrf = await ValidateCsrfAsync(
            httpContext,
            antiforgery);
        if (csrf is not null)
        {
            return csrf;
        }

        return await ExecuteAsync(
            () => service.BeginEnrollmentAsync(
                accountId,
                sessionId,
                request.CurrentPassword,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted));
    }

    private static async Task<IResult> ConfirmEnrollmentAsync(
        ConfirmMfaEnrollmentRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        PrivilegedMfaService service)
    {
        if (!TryActorSession(
                httpContext,
                out var accountId,
                out var sessionId))
        {
            return Results.Unauthorized();
        }

        var csrf = await ValidateCsrfAsync(
            httpContext,
            antiforgery);
        if (csrf is not null)
        {
            return csrf;
        }

        return await ExecuteAsync(
            () => service.ConfirmEnrollmentAsync(
                accountId,
                sessionId,
                request.ChallengeId,
                request.Secret,
                request.Code,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted));
    }

    private static async Task<IResult> BeginStepUpAsync(
        HttpContext httpContext,
        IAntiforgery antiforgery,
        PrivilegedMfaService service)
    {
        if (!TryActorSession(
                httpContext,
                out var accountId,
                out var sessionId))
        {
            return Results.Unauthorized();
        }

        var csrf = await ValidateCsrfAsync(
            httpContext,
            antiforgery);
        if (csrf is not null)
        {
            return csrf;
        }

        return await ExecuteAsync(
            () => service.BeginStepUpAsync(
                accountId,
                sessionId,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted));
    }

    private static async Task<IResult> ConfirmStepUpAsync(
        ConfirmMfaStepUpRequest request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        PrivilegedMfaService service)
    {
        if (!TryActorSession(
                httpContext,
                out var accountId,
                out var sessionId))
        {
            return Results.Unauthorized();
        }

        var csrf = await ValidateCsrfAsync(
            httpContext,
            antiforgery);
        if (csrf is not null)
        {
            return csrf;
        }

        return await ExecuteAsync(
            () => service.ConfirmStepUpAsync(
                accountId,
                sessionId,
                request.ChallengeId,
                request.Code,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted));
    }

    private static async Task<IResult?> ValidateCsrfAsync(
        HttpContext httpContext,
        IAntiforgery antiforgery)
    {
        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);
            return null;
        }
        catch (AntiforgeryValidationException)
        {
            return CsrfInvalid();
        }
    }

    private static async Task<IResult> ExecuteAsync<T>(
        Func<Task<T>> operation)
    {
        try
        {
            return Results.Ok(await operation());
        }
        catch (MfaAdministrationException exception)
        {
            return Results.Problem(
                statusCode: exception.StatusCode,
                title: Title(exception.StatusCode),
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

    private static bool TryActorSession(
        HttpContext httpContext,
        out Guid accountId,
        out Guid sessionId)
    {
        var accountValue =
            httpContext.User.FindFirstValue("account_id");
        var sessionValue =
            httpContext.User.FindFirstValue("session_id");

        sessionId = Guid.Empty;

        return Guid.TryParse(accountValue, out accountId)
            && accountId != Guid.Empty
            && Guid.TryParse(sessionValue, out sessionId)
            && sessionId != Guid.Empty;
    }

    private static string Title(int statusCode) =>
        statusCode switch
        {
            StatusCodes.Status401Unauthorized =>
                "Reautenticación no confirmada",
            StatusCodes.Status409Conflict =>
                "Reto MFA no aplicable",
            StatusCodes.Status429TooManyRequests =>
                "Reto MFA agotado",
            StatusCodes.Status503ServiceUnavailable =>
                "MFA temporalmente no disponible",
            _ => "Verificación MFA no válida"
        };

    private static IResult CsrfInvalid() =>
        Results.Problem(
            statusCode: StatusCodes.Status400BadRequest,
            title: "Solicitud no válida",
            detail: "Actualiza la página y vuelve a intentarlo.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "security.mfa.csrf.invalid"
            });

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "MFA temporalmente no disponible",
            detail:
                "No se amplió la autenticación de la sesión. "
                + "Vuelve a intentarlo más tarde.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "security.mfa.unavailable"
            });
}
