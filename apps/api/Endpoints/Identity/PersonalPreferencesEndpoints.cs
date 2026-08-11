using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Mvc;
using MusicaAprender.Api.Security;
using MusicaAprender.Modules.Identity.Application.Preferences;
using MusicaAprender.Modules.Identity.Infrastructure.Preferences;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Identity;

public static class PersonalPreferencesEndpoints
{
    public static IEndpointRouteBuilder MapPersonalPreferences(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/preferences",
                GetAsync)
            .RequireAuthorization()
            .Produces<PersonalPreferencesResponse>(
                StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("GetPersonalPreferences")
            .WithTags("Identity");

        endpoints.MapPut(
                "/api/v1/preferences",
                PutAsync)
            .RequireAuthorization()
            .Accepts<PersonalPreferenceDraft>("application/json")
            .Produces<PersonalPreferencesResponse>(
                StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .WithName("PutPersonalPreferences")
            .WithTags("Identity");

        return endpoints;
    }

    private static async Task<IResult> GetAsync(
        HttpContext httpContext,
        IHttpDatabaseSessionContextFactory contextFactory,
        PersonalPreferenceService preferences,
        CancellationToken cancellationToken)
    {
        try
        {
            var context =
                contextFactory.CreateRequired(httpContext);
            var snapshot =
                await preferences.GetAsync(
                    context,
                    cancellationToken);

            httpContext.Response.Headers.CacheControl =
                "private, no-store";
            return Results.Ok(ToResponse(snapshot));
        }
        catch (NpgsqlException)
        {
            return StorageUnavailable();
        }
        catch (InvalidOperationException)
        {
            return StorageUnavailable();
        }
    }

    private static async Task<IResult> PutAsync(
        [FromBody] PersonalPreferenceDraft request,
        HttpContext httpContext,
        IAntiforgery antiforgery,
        IHttpDatabaseSessionContextFactory contextFactory,
        PersonalPreferenceService preferences,
        CancellationToken cancellationToken)
    {
        try
        {
            await antiforgery.ValidateRequestAsync(httpContext);

            var context =
                contextFactory.CreateRequired(httpContext);
            var snapshot =
                await preferences.UpdateAsync(
                    context,
                    request,
                    cancellationToken);

            httpContext.Response.Headers.CacheControl =
                "private, no-store";
            return Results.Ok(ToResponse(snapshot));
        }
        catch (AntiforgeryValidationException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Solicitud no válida",
                detail:
                    "Actualiza la página y vuelve a confirmar tus preferencias.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "identity.preferences.csrf.invalid"
                });
        }
        catch (PersonalPreferenceValidationException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Preferencia no válida",
                detail:
                    "La última configuración confirmada se conserva sin cambios.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] =
                        exception.Validation.ErrorCode
                        ?? "identity.preferences.invalid",
                    ["field"] =
                        exception.Validation.Field
                });
        }
        catch (PersonalPreferenceConcurrencyException exception)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Las preferencias cambiaron",
                detail:
                    "Recarga la configuración vigente antes de volver a confirmar.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "identity.preferences.version.conflict",
                    ["currentVersion"] = exception.CurrentVersion
                });
        }
        catch (NpgsqlException)
        {
            return StorageUnavailable();
        }
        catch (InvalidOperationException)
        {
            return StorageUnavailable();
        }
    }

    private static PersonalPreferencesResponse ToResponse(
        PersonalPreferenceSnapshot snapshot) =>
        new(
            snapshot.PreferenceSetId,
            snapshot.Version,
            snapshot.RevisionNo,
            snapshot.Values,
            snapshot.UpdatedAt,
            snapshot.Profile,
            new PersonalPreferenceOptions(
                [new PreferenceLanguageOption(
                    PersonalPreferencePolicy.SpanishLanguageCode,
                    "Español",
                    snapshot.Values.Provenance.LanguageCatalogVersion)],
                PersonalPreferencePolicy.FuriganaModes,
                PersonalPreferencePolicy.RomajiModes,
                PersonalPreferencePolicy.FontScalePercents,
                PersonalPreferencePolicy.PrivacyVisibilities));

    private static IResult StorageUnavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Preferencias temporalmente no disponibles",
            detail:
                "La última configuración confirmada permanece intacta. "
                + "Vuelve a intentarlo más tarde.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "identity.preferences.unavailable"
            });
}

public sealed record PreferenceLanguageOption(
    string Code,
    string Label,
    long Version);

public sealed record PersonalPreferenceOptions(
    IReadOnlyList<PreferenceLanguageOption> Languages,
    IReadOnlyList<string> FuriganaModes,
    IReadOnlyList<string> RomajiModes,
    IReadOnlyList<int> FontScalePercents,
    IReadOnlyList<string> PrivacyVisibilities);

public sealed record PersonalPreferencesResponse(
    Guid PreferenceSetId,
    long Version,
    int RevisionNo,
    PersonalPreferenceValues Values,
    DateTimeOffset UpdatedAt,
    PersonalProfileSummary Profile,
    PersonalPreferenceOptions Options);
