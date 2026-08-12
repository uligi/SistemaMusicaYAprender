using System.Security.Claims;
using MusicaAprender.Modules.Catalog.Infrastructure.Administration;
using MusicaAprender.Modules.Security.Infrastructure.Authorization;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public sealed record SongEditorialDossierComponent(
    string Code,
    string Label,
    string RevisionLabel,
    string StateCode,
    string OwnerLabel,
    bool Exists,
    string? Href);

public sealed record SongEditorialDossierRights(
    int TotalRecords,
    int ActiveRecords,
    int ProvenanceRecords,
    string OwnerLabel,
    string StateCode);

public sealed record SongEditorialDossierIncident(
    string ComponentCode,
    string RuleCode,
    string SeverityCode,
    string StatusCode,
    DateTime DetectedAt);

public sealed record SongEditorialDossierAccess(
    string Code,
    string Label,
    string Href);

public sealed record SongEditorialDossierResponse(
    string CanonicalTitle,
    string? RecordingTitle,
    string ArtistName,
    string RecordingStatusCode,
    string? ProviderCode,
    string? ExternalRef,
    string? SourceStatusCode,
    IReadOnlyList<SongEditorialDossierComponent> Components,
    SongEditorialDossierRights Rights,
    IReadOnlyList<SongEditorialDossierIncident> Incidents,
    IReadOnlyList<SongEditorialDossierAccess> AllowedAccesses);

public static class SongEditorialDossierEndpoints
{
    public static IEndpointRouteBuilder MapSongEditorialDossier(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/song-dossiers/{recordingId:guid}",
                ReadAsync)
            .RequireAuthorization()
            .WithName("ReadEditorialSongDossier")
            .WithTags("Editorial");

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        Guid recordingId,
        HttpContext httpContext,
        EffectiveAuthorizationService authorization,
        SongEditorialDossierService dossierService)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        if (recordingId == Guid.Empty)
        {
            return Results.BadRequest();
        }

        try
        {
            var grants =
                await authorization.ResolveScopedPermissionsAsync(
                    actorId,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            var accesses =
                ResolveAllowedAccesses(
                    recordingId,
                    grants);

            if (accesses.Count == 0)
            {
                return Results.Forbid();
            }

            var dossier =
                await dossierService.ReadAsync(
                    actorId,
                    recordingId,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            var accessByCode =
                accesses.ToDictionary(
                    static access => access.Code,
                    StringComparer.Ordinal);

            var components = dossier.Components
                .Select(component =>
                    new SongEditorialDossierComponent(
                        component.Code,
                        component.Label,
                        component.RevisionLabel,
                        component.StateCode,
                        OwnerLabel(
                            component.OwnerActorId,
                            actorId),
                        component.Exists,
                        ComponentHref(
                            component.Code,
                            accessByCode)))
                .ToArray();

            return Results.Ok(
                new SongEditorialDossierResponse(
                    dossier.Catalog.CanonicalTitle,
                    dossier.Catalog.RecordingTitle,
                    dossier.Catalog.ArtistName,
                    dossier.Catalog.RecordingStatusCode,
                    dossier.Catalog.ProviderCode,
                    dossier.Catalog.ExternalRef,
                    dossier.Catalog.SourceStatusCode,
                    components,
                    new SongEditorialDossierRights(
                        dossier.Rights.TotalRecords,
                        dossier.Rights.ActiveRecords,
                        dossier.Rights.ProvenanceRecords,
                        OwnerLabel(
                            dossier.Rights.OwnerActorId,
                            actorId),
                        dossier.Rights.ActiveRecords > 0
                            ? "ACTIVE"
                            : dossier.Rights.TotalRecords > 0
                                ? "INACTIVE"
                                : "NOT_STARTED"),
                    dossier.Incidents
                        .Select(static incident =>
                            new SongEditorialDossierIncident(
                                incident.ComponentCode,
                                incident.RuleCode,
                                incident.SeverityCode,
                                incident.StatusCode,
                                incident.DetectedAt))
                        .ToArray(),
                    accesses));
        }
        catch (SongEditorialDossierException exception)
        {
            return exception.Code == "editorial.song-dossier.not-found"
                ? Results.NotFound(
                    Problem(
                        StatusCodes.Status404NotFound,
                        "Expediente no encontrado",
                        exception.Message,
                        exception.Code))
                : Results.BadRequest(
                    Problem(
                        StatusCodes.Status400BadRequest,
                        "Expediente no válido",
                        exception.Message,
                        exception.Code));
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

    private static List<SongEditorialDossierAccess>
        ResolveAllowedAccesses(
            Guid recordingId,
            IReadOnlyList<EffectivePermissionGrant> grants)
    {
        var accesses =
            new List<SongEditorialDossierAccess>();

        var canDraftCatalog =
            IsAllowed(
                grants,
                "EDITORIAL.DRAFT",
                "M02",
                recordingId);
        var canDraftContent =
            IsAllowed(
                grants,
                "EDITORIAL.DRAFT",
                "M03",
                recordingId);
        var canDraftTranslation =
            IsAllowed(
                grants,
                "EDITORIAL.DRAFT",
                "M04",
                recordingId);
        var canDraftAnalysis =
            IsAllowed(
                grants,
                "EDITORIAL.DRAFT",
                "M05",
                recordingId);
        var canDraftExercises =
            IsAllowed(
                grants,
                "EDITORIAL.DRAFT",
                "M08",
                recordingId);
        var canDraftRights =
            IsAllowed(
                grants,
                "EDITORIAL.DRAFT",
                "M15",
                recordingId);
        var canReview =
            IsAllowed(
                grants,
                "EDITORIAL.REVIEW",
                "M15",
                recordingId);
        var canPublish =
            IsAllowed(
                grants,
                "EDITORIAL.PUBLISH",
                "M15",
                recordingId);
        var canCorrect =
            IsAllowed(
                grants,
                "EDITORIAL.CORRECT",
                "M15",
                recordingId);

        if (canDraftCatalog
            || canDraftContent
            || canDraftTranslation
            || canDraftAnalysis
            || canDraftExercises
            || canDraftRights
            || canReview
            || canPublish
            || canCorrect)
        {
            accesses.Add(
                new(
                    "DOSSIER",
                    "Expediente",
                    $"/editorial/canciones/{recordingId:D}"));
        }

        if (canDraftRights || canReview)
        {
            accesses.Add(
                new(
                    "RIGHTS",
                    "Derechos y procedencia",
                    $"/editorial/canciones/{recordingId:D}/derechos"));
        }

        if (canDraftContent)
        {
            accesses.Add(
                new(
                    "LYRICS",
                    "Letra",
                    $"/editorial/canciones/{recordingId:D}/letra"));
            accesses.Add(
                new(
                    "TIMING",
                    "Sincronización",
                    $"/editorial/canciones/{recordingId:D}/sincronizacion"));
        }

        if (canDraftTranslation || canReview)
        {
            accesses.Add(
                new(
                    "TRANSLATION",
                    "Traducción",
                    $"/editorial/canciones/{recordingId:D}/traduccion"));
        }

        if (canDraftAnalysis || canReview)
        {
            accesses.Add(
                new(
                    "ANALYSIS",
                    "Análisis lingüístico",
                    $"/editorial/canciones/{recordingId:D}/analisis"));
        }

        if (canDraftExercises || canReview)
        {
            accesses.Add(
                new(
                    "EXERCISES",
                    "Ejercicios",
                    $"/editorial/canciones/{recordingId:D}/ejercicios"));
        }

        return accesses;
    }

    private static bool IsAllowed(
        IReadOnlyList<EffectivePermissionGrant> grants,
        string permissionCode,
        string moduleCode,
        Guid recordingId)
    {
        var required =
            AuthorizationScope.ForObject(
                moduleCode,
                recordingId);

        return grants.Any(grant =>
            string.Equals(
                grant.PermissionCode,
                permissionCode,
                StringComparison.Ordinal)
            && AuthorizationScopeMatcher.Matches(
                required,
                grant.ScopeType,
                grant.ModuleCode,
                grant.ObjectId));
    }

    private static string? ComponentHref(
        string componentCode,
        Dictionary<string, SongEditorialDossierAccess> accesses)
    {
        var accessCode = componentCode switch
        {
            "RIGHTS" => "RIGHTS",
            "LYRICS" => "LYRICS",
            "TIMING" => "TIMING",
            "TRANSLATION" => "TRANSLATION",
            "ANALYSIS" => "ANALYSIS",
            "EXERCISES" => "EXERCISES",
            _ => null
        };

        return accessCode is not null
            && accesses.TryGetValue(
                accessCode,
                out var access)
                ? access.Href
                : null;
    }

    private static string OwnerLabel(
        Guid? ownerActorId,
        Guid actorId)
    {
        if (ownerActorId is null)
        {
            return "Sin responsable identificado";
        }

        return ownerActorId == actorId
            ? "Tú"
            : "Otro responsable";
    }

    private static bool TryActor(
        HttpContext context,
        out Guid actorId)
    {
        var value =
            context.User.FindFirstValue("account_id");

        return Guid.TryParse(
                value,
                out actorId)
            && actorId != Guid.Empty;
    }

    private static object Problem(
        int status,
        string title,
        string detail,
        string code) =>
        new
        {
            type = "about:blank",
            title,
            status,
            detail,
            code
        };

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode:
                StatusCodes.Status503ServiceUnavailable,
            title:
                "Expediente editorial temporalmente no disponible",
            detail:
                "No se expuso información parcial. Vuelve a intentarlo más tarde.",
            extensions:
                new Dictionary<string, object?>
                {
                    ["code"] =
                        "editorial.song-dossier.unavailable"
                });
}
