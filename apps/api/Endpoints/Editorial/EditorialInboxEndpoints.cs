using System.Security.Claims;
using MusicaAprender.Modules.Catalog.Infrastructure.Administration;
using MusicaAprender.Modules.Security.Infrastructure.Authorization;
using Npgsql;

namespace MusicaAprender.Api.Endpoints.Editorial;

public sealed record EditorialInboxAction(
    string Code,
    string Label,
    string Href);

public sealed record EditorialInboxLock(
    bool Active,
    string? OperationCode,
    DateTime? ExpiresAt);

public sealed record EditorialInboxItem(
    Guid RecordingId,
    string CanonicalTitle,
    string? RecordingTitle,
    string ArtistName,
    string StateCode,
    string OwnerLabel,
    EditorialInboxLock Lock,
    string ProvenanceLabel,
    string? ProviderCode,
    DateTime? LastActivityAt,
    string NextAction,
    IReadOnlyList<EditorialInboxAction> Actions);

public sealed record EditorialInboxResponse(
    IReadOnlyList<EditorialInboxItem> Items,
    int CandidateCount,
    int VisibleCount);

public static class EditorialInboxEndpoints
{
    private static readonly string[] RelevantPermissions =
    [
        "EDITORIAL.DRAFT",
        "EDITORIAL.REVIEW",
        "EDITORIAL.PUBLISH",
        "EDITORIAL.CORRECT"
    ];

    public static IEndpointRouteBuilder MapEditorialInbox(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
                "/api/v1/editorial/inbox",
                ReadAsync)
            .RequireAuthorization()
            .WithName("ReadEditorialInbox")
            .WithTags("Editorial");

        return endpoints;
    }

    private static async Task<IResult> ReadAsync(
        HttpContext httpContext,
        EditorialInboxService inbox,
        EffectiveAuthorizationService authorization)
    {
        if (!TryActor(httpContext, out var actorId))
        {
            return Results.Unauthorized();
        }

        try
        {
            var candidates = await inbox.ReadCandidatesAsync(
                actorId,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            var grants = await authorization.ResolveScopedPermissionsAsync(
                actorId,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            var items = candidates
                .Select(candidate => BuildVisibleItem(
                    candidate,
                    actorId,
                    grants))
                .Where(static item => item is not null)
                .Cast<EditorialInboxItem>()
                .ToArray();

            return Results.Ok(new EditorialInboxResponse(
                items,
                candidates.Count,
                items.Length));
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

    private static EditorialInboxItem? BuildVisibleItem(
        EditorialInboxCandidate candidate,
        Guid actorId,
        IReadOnlyList<EffectivePermissionGrant> grants)
    {
        var canDraft = IsAllowed(
            grants,
            "EDITORIAL.DRAFT",
            "M02",
            candidate.RecordingId);
        var canRightsDraft = IsAllowed(
            grants,
            "EDITORIAL.DRAFT",
            "M15",
            candidate.RecordingId);
        var canReview = IsAllowed(
            grants,
            "EDITORIAL.REVIEW",
            "M15",
            candidate.RecordingId);
        var canPublish = IsAllowed(
            grants,
            "EDITORIAL.PUBLISH",
            "M15",
            candidate.RecordingId);
        var canCorrect = IsAllowed(
            grants,
            "EDITORIAL.CORRECT",
            "M15",
            candidate.RecordingId);

        if (!canDraft
            && !canRightsDraft
            && !canReview
            && !canPublish
            && !canCorrect)
        {
            return null;
        }

        var actions = new List<EditorialInboxAction>();

        if (canDraft)
        {
            actions.Add(new EditorialInboxAction(
                "OPEN_DRAFT",
                "Abrir expediente",
                $"/editorial/canciones/{candidate.RecordingId:D}"));
        }

        if (canRightsDraft || canReview)
        {
            actions.Add(new EditorialInboxAction(
                "OPEN_RIGHTS",
                "Derechos y procedencia",
                $"/editorial/canciones/{candidate.RecordingId:D}/derechos"));
        }

        if (canReview && candidate.PackageId is { } packageId)
        {
            actions.Add(new EditorialInboxAction(
                "OPEN_REVIEW",
                "Abrir paquete de revisión",
                $"/editorial/paquetes/{packageId:D}"));
        }

        var stateCode = ResolveState(candidate);
        var nextAction = ResolveNextAction(
            candidate,
            canDraft,
            canReview,
            canPublish,
            canCorrect);

        return new EditorialInboxItem(
            candidate.RecordingId,
            candidate.CanonicalTitle,
            candidate.RecordingTitle,
            candidate.ArtistName,
            stateCode,
            ResolveOwner(candidate.OwnerActorId, actorId),
            new EditorialInboxLock(
                candidate.LockExpiresAt is not null,
                candidate.LockOperationCode,
                candidate.LockExpiresAt),
            candidate.HasProvenance
                ? "Procedencia registrada"
                : "Procedencia pendiente",
            candidate.ProviderCode,
            candidate.LastActivityAt,
            nextAction,
            actions);
    }

    private static bool IsAllowed(
        IReadOnlyList<EffectivePermissionGrant> grants,
        string permissionCode,
        string moduleCode,
        Guid objectId)
    {
        var required = AuthorizationScope.ForObject(
            moduleCode,
            objectId);

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

    private static string ResolveState(
        EditorialInboxCandidate candidate)
    {
        if (!string.IsNullOrWhiteSpace(
                candidate.PublicationStatusCode))
        {
            return $"PUBLICATION:{candidate.PublicationStatusCode}";
        }

        if (!string.IsNullOrWhiteSpace(
                candidate.SubmissionStatusCode))
        {
            return $"REVIEW:{candidate.SubmissionStatusCode}";
        }

        if (!string.IsNullOrWhiteSpace(
                candidate.PackageStatusCode))
        {
            return $"PACKAGE:{candidate.PackageStatusCode}";
        }

        return $"RECORDING:{candidate.RecordingStatusCode}";
    }

    private static string ResolveOwner(
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

    private static string ResolveNextAction(
        EditorialInboxCandidate candidate,
        bool canDraft,
        bool canReview,
        bool canPublish,
        bool canCorrect)
    {
        if (candidate.PublicationStatusCode == "ACTIVE"
            && canCorrect)
        {
            return "Gestionar una corrección, reversión o sustitución cuando corresponda.";
        }

        if (candidate.SubmissionId is not null
            && canReview)
        {
            return "Revisar el paquete sometido y registrar una decisión.";
        }

        if (candidate.PackageStatusCode == "APPROVED"
            && canPublish)
        {
            return "Preparar la publicación del paquete aprobado.";
        }

        if (canDraft)
        {
            return "Continuar preparando el expediente editorial.";
        }

        if (canReview)
        {
            return "Esperar o abrir un paquete sometido a revisión.";
        }

        if (canPublish)
        {
            return "Esperar un paquete aprobado para publicación.";
        }

        return "Esperar una publicación activa para gestionar correcciones.";
    }

    private static bool TryActor(
        HttpContext context,
        out Guid actorId)
    {
        var value =
            context.User.FindFirstValue("account_id");

        return Guid.TryParse(value, out actorId)
            && actorId != Guid.Empty;
    }

    private static IResult Unavailable() =>
        Results.Problem(
            statusCode:
                StatusCodes.Status503ServiceUnavailable,
            title:
                "Bandeja editorial temporalmente no disponible",
            detail:
                "No se expuso información parcial. Vuelve a intentarlo más tarde.",
            extensions:
                new Dictionary<string, object?>
                {
                    ["code"] =
                        "editorial.inbox.unavailable"
                });
}
