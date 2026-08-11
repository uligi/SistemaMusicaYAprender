[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "51c49e039e5b244dd8b4f2b27254ed4899bdc1b4"
$ExpectedDotNet = "9.0.314"
$ExpectedNode = "v24.18.0"
$ExpectedNpm = "11.16.0"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

function Resolve-GitBash {
    $gitCommand = Get-Command "git.exe" -ErrorAction Stop
    $gitDirectory = Split-Path -Parent $gitCommand.Source
    $candidates = @(
        (Join-Path $gitDirectory "..\bin\bash.exe"),
        (Join-Path $gitDirectory "..\usr\bin\bash.exe"),
        (Join-Path $gitDirectory "bash.exe"),
        (Join-Path $gitDirectory "..\..\usr\bin\bash.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate -PathType Leaf) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Git Bash no esta disponible junto a git.exe."
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

    if (-not (Test-Path ".env" -PathType Leaf)) {
        return $DefaultValue
    }

    $match = Get-Content ".env" |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -Last 1

    if ($null -eq $match) {
        return $DefaultValue
    }

    return (($match -split "=", 2)[1]).Trim()
}

function Read-Normalized {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Falta $RelativePath."
    }

    $content = [System.IO.File]::ReadAllText(
        $path,
        [System.Text.Encoding]::UTF8)
    $content = $content.Replace("`r`n", "`n")
    return $content.Replace("`r", "`n")
}

function Write-Utf8NoBomLf {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $path = Join-Path $RepoRoot $RelativePath
    $normalized = $Content.Replace("`r`n", "`n")
    $normalized = $normalized.Replace("`r", "`n")
    [System.IO.File]::WriteAllText(
        $path,
        $normalized,
        [System.Text.UTF8Encoding]::new($false))
}

function Replace-ExactOnce {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [Parameter(Mandatory = $true)][string]$AlreadyMarker,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $content = Read-Normalized -RelativePath $RelativePath
    $old = $OldText.Replace("`r`n", "`n").Replace("`r", "`n")
    $new = $NewText.Replace("`r`n", "`n").Replace("`r", "`n")
    $marker = $AlreadyMarker.Replace("`r`n", "`n").Replace("`r", "`n")

    if ($content.Contains($marker)) {
        Write-Host "OK: $Description ya estaba aplicado."
        return
    }

    $first = $content.IndexOf($old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw "No se encontro el bloque esperado para $Description en $RelativePath."
    }

    $second = $content.IndexOf(
        $old,
        $first + $old.Length,
        [System.StringComparison]::Ordinal)

    if ($second -ge 0) {
        throw "El bloque para $Description aparece mas de una vez en $RelativePath."
    }

    $content = $content.Remove($first, $old.Length).Insert($first, $new)
    Write-Utf8NoBomLf -RelativePath $RelativePath -Content $content
    Write-Host "OK: $Description aplicado."
}

function Add-AfterOnce {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Anchor,
        [Parameter(Mandatory = $true)][string]$Addition,
        [Parameter(Mandatory = $true)][string]$AlreadyMarker,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $content = Read-Normalized -RelativePath $RelativePath
    if ($content.Contains($AlreadyMarker)) {
        Write-Host "OK: $Description ya estaba aplicado."
        return
    }

    $anchorNormalized = $Anchor.Replace("`r`n", "`n").Replace("`r", "`n")
    $index = $content.IndexOf(
        $anchorNormalized,
        [System.StringComparison]::Ordinal)

    if ($index -lt 0) {
        throw "No se encontro el ancla para $Description en $RelativePath."
    }

    if ($content.IndexOf(
        $anchorNormalized,
        $index + $anchorNormalized.Length,
        [System.StringComparison]::Ordinal) -ge 0) {
        throw "El ancla para $Description no es unica en $RelativePath."
    }

    $insertAt = $index + $anchorNormalized.Length
    $updated = $content.Insert(
        $insertAt,
        $Addition.Replace("`r`n", "`n").Replace("`r", "`n"))
    Write-Utf8NoBomLf -RelativePath $RelativePath -Content $updated
    Write-Host "OK: $Description aplicado."
}

function Restore-GeneratedTypeScriptState {
    $relativePath = "apps/web/tsconfig.app.tsbuildinfo"
    $stagedPaths = @(git diff --cached --name-only -- $relativePath)
    Assert-LastExitCode "Consulta del indice para tsconfig.app.tsbuildinfo"
    if ($stagedPaths.Count -gt 0) {
        throw "$relativePath contiene cambios staged."
    }

    $trackedPaths = @(git ls-files -- $relativePath)
    Assert-LastExitCode "Consulta de seguimiento de tsconfig.app.tsbuildinfo"
    if ($trackedPaths.Count -eq 0) {
        return
    }

    $generatedState = @(git status --porcelain=v1 -- $relativePath)
    Assert-LastExitCode "Consulta del archivo incremental TypeScript"
    if ($generatedState.Count -gt 0) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restauracion de tsconfig.app.tsbuildinfo"
        Write-Host "Restaurado $relativePath por ser salida incremental rastreada."
    }
}

function Get-UntrackedPaths {
    $result = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)

    foreach ($line in @(git status --porcelain=v1 --untracked-files=all)) {
        if ($line.StartsWith("?? ")) {
            [void]$result.Add(
                $line.Substring(3).Trim('"').Replace("\", "/"))
        }
    }

    return $result
}

Write-Host "BL-MVP-033: eventos de seguridad y auditoria primaria protegida..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-033 debe ejecutarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

# No se permiten modificaciones tracked previas. Los archivos no rastreados
# ajenos al paquete se preservan y se vuelven a comprobar al final.
git diff --quiet
Assert-LastExitCode "Comprobacion de working tree tracked limpio"

$packagePaths = @(
    "README/BL-MVP-033_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-033.md",
    "docs/engineering/security/primary-audit.md",
    "apps/api/Security/PrimaryAuditRecorder.cs",
    "src/Modules/Security/Infrastructure/Audit/PrimaryAuditWriter.cs",
    "tests/UnitTests/Modules/Security/PrimaryAuditCorrelationTests.cs",
    "scripts/ci/security/verify-primary-audit.sh",
    "scripts/apply-bl-mvp-033.ps1"
)

foreach ($relativePath in $packagePaths) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf)) {
        throw "Paquete incompleto: falta $relativePath."
    }
}

$packageSet = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
foreach ($path in $packagePaths) {
    [void]$packageSet.Add($path)
}

$baselineUntracked = Get-UntrackedPaths
$foreignUntracked = @(
    $baselineUntracked |
        Where-Object { -not $packageSet.Contains($_) }
)
if ($foreignUntracked.Count -gt 0) {
    Write-Host "INFO: se preservaran $($foreignUntracked.Count) rutas no rastreadas preexistentes fuera de BL-MVP-033."
}

# -------------------------------------------------------------------
# Program.cs: registrar PrimaryAuditRecorder.
# -------------------------------------------------------------------
Add-AfterOnce `
    -RelativePath "apps/api/Program.cs" `
    -Anchor "builder.Services.AddSingleton<RoleAssignmentAdministrationService>();`n" `
    -Addition "builder.Services.AddSingleton<PrimaryAuditRecorder>();`n" `
    -AlreadyMarker "builder.Services.AddSingleton<PrimaryAuditRecorder>();" `
    -Description "servicio de auditoria primaria"

# -------------------------------------------------------------------
# Registro: éxito + caso existente no enumerable.
# -------------------------------------------------------------------
Add-AfterOnce `
    -RelativePath "apps/api/Endpoints/Identity/PersonalAccountRegistrationService.cs" `
    -Anchor "using MusicaAprender.Modules.Identity.Infrastructure.Registration;`n" `
    -Addition "using MusicaAprender.Modules.Security.Infrastructure.Audit;`n" `
    -AlreadyMarker "using MusicaAprender.Modules.Security.Infrastructure.Audit;" `
    -Description "namespace de auditoria en registro"

Replace-ExactOnce `
    -RelativePath "apps/api/Endpoints/Identity/PersonalAccountRegistrationService.cs" `
    -OldText @'
                    await emailEnqueuer.EnqueueAsync(
                        connection,
                        transaction,
                        new EmailQueueRequest(
                            "SECURITY",
                            proposedAccountId,
                            verificationId,
                            AccountVerificationEmailTemplate.Code,
                            AccountVerificationEmailTemplate.Version,
                            AccountVerificationEmailTemplate.Language,
                            correlationGuid),
                        token);
                }

                return ReliableOperationResult.Create(
'@ `
    -NewText @'
                    await emailEnqueuer.EnqueueAsync(
                        connection,
                        transaction,
                        new EmailQueueRequest(
                            "SECURITY",
                            proposedAccountId,
                            verificationId,
                            AccountVerificationEmailTemplate.Code,
                            AccountVerificationEmailTemplate.Version,
                            AccountVerificationEmailTemplate.Language,
                            correlationGuid),
                        token);

                    await PrimaryAuditWriter.WriteSecurityEventAsync(
                        connection,
                        transaction,
                        proposedAccountId,
                        "ACCOUNT_REGISTRATION",
                        "SUCCEEDED",
                        correlationId,
                        cancellationToken: token);
                }
                else
                {
                    await PrimaryAuditWriter.WriteSecurityEventAsync(
                        connection,
                        transaction,
                        accountId: null,
                        eventType: "ACCOUNT_REGISTRATION",
                        resultCode: "RECEIVED_OR_EXISTING",
                        correlationId: correlationId,
                        clientFingerprint: protectedEmail.LookupHash,
                        cancellationToken: token);
                }

                return ReliableOperationResult.Create(
'@ `
    -AlreadyMarker '"RECEIVED_OR_EXISTING",' `
    -Description "eventos primarios del registro"

# -------------------------------------------------------------------
# Sesión: creación + revocación pseudonimizada.
# -------------------------------------------------------------------
Replace-ExactOnce `
    -RelativePath "src/Modules/Security/Infrastructure/Authentication/SecuritySessionPersistence.cs" `
    -OldText @'
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using Npgsql;
using NpgsqlTypes;
'@ `
    -NewText @'
using System.Security.Cryptography;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.Modules.Security.Infrastructure.Audit;
using Npgsql;
using NpgsqlTypes;
'@ `
    -AlreadyMarker "using MusicaAprender.Modules.Security.Infrastructure.Audit;" `
    -Description "namespace auditoria en sesion"

Replace-ExactOnce `
    -RelativePath "src/Modules/Security/Infrastructure/Authentication/SecuritySessionPersistence.cs" `
    -OldText @'
                if (await command.ExecuteNonQueryAsync(token) != 1)
                {
                    throw new InvalidOperationException(
                        "No se pudo crear exactamente una sesion de seguridad.");
                }
'@ `
    -NewText @'
                if (await command.ExecuteNonQueryAsync(token) != 1)
                {
                    throw new InvalidOperationException(
                        "No se pudo crear exactamente una sesion de seguridad.");
                }

                await PrimaryAuditWriter.WriteSecurityEventAsync(
                    connection,
                    transaction,
                    accountId,
                    "SESSION_CREATED",
                    "SUCCEEDED",
                    correlationId,
                    cancellationToken: token);
'@ `
    -AlreadyMarker '"SESSION_CREATED",' `
    -Description "evento de creacion de sesion"

Replace-ExactOnce `
    -RelativePath "src/Modules/Security/Infrastructure/Authentication/SecuritySessionPersistence.cs" `
    -OldText @'
                await using var command = new NpgsqlCommand(
                    "SELECT security.revoke_active_session(@session_hash);",
                    connection,
                    transaction);
                command.Parameters.AddWithValue(
                    "session_hash",
                    NpgsqlDbType.Bytea,
                    sessionHash.ToArray());
                await command.ExecuteScalarAsync(token);
'@ `
    -NewText @'
                await using var command = new NpgsqlCommand(
                    "SELECT security.revoke_active_session(@session_hash);",
                    connection,
                    transaction);
                command.Parameters.AddWithValue(
                    "session_hash",
                    NpgsqlDbType.Bytea,
                    sessionHash.ToArray());

                var revoked =
                    await command.ExecuteScalarAsync(token) is true;

                if (revoked)
                {
                    var fingerprint =
                        SHA256.HashData(sessionHash.Span);

                    try
                    {
                        await PrimaryAuditWriter.WriteSecurityEventAsync(
                            connection,
                            transaction,
                            accountId: null,
                            eventType: "SESSION_REVOKED",
                            resultCode: "SUCCEEDED",
                            correlationId: correlationId,
                            clientFingerprint: fingerprint,
                            cancellationToken: token);
                    }
                    finally
                    {
                        CryptographicOperations.ZeroMemory(fingerprint);
                    }
                }
'@ `
    -AlreadyMarker '"SESSION_REVOKED",' `
    -Description "evento pseudonimo de revocacion"

# -------------------------------------------------------------------
# Autorización: cada decisión permitida/denegada queda emparejada.
# -------------------------------------------------------------------
Replace-ExactOnce `
    -RelativePath "apps/api/Security/EffectivePermissionEndpointFilter.cs" `
    -OldText @'
            var decision = await authorization.AuthorizeAsync(
                accountId,
                permissionCode,
                requiredScope,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            if (!decision.Allowed)
            {
                return AuthorizationDenied();
            }

            return await next(context);
'@ `
    -NewText @'
            var decision = await authorization.AuthorizeAsync(
                accountId,
                permissionCode,
                requiredScope,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            var audit =
                httpContext.RequestServices
                    .GetRequiredService<PrimaryAuditRecorder>();

            await audit.RecordAuthorizationDecisionAsync(
                accountId,
                permissionCode,
                requiredScope,
                decision,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            if (!decision.Allowed)
            {
                return AuthorizationDenied();
            }

            return await next(context);
'@ `
    -AlreadyMarker "RecordAuthorizationDecisionAsync(" `
    -Description "auditoria de decisiones de autorizacion"

Replace-ExactOnce `
    -RelativePath "apps/api/Security/EffectivePermissionEndpointFilter.cs" `
    -OldText @'
        catch (NpgsqlException)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Autorización temporalmente no disponible",
                detail:
                    "La operación protegida se cerró de forma segura. "
                    + "Vuelve a intentarlo más tarde.",
                extensions: new Dictionary<string, object?>
                {
                    ["code"] = "security.authorization.unavailable"
                });
        }
'@ `
    -NewText @'
        catch (NpgsqlException)
        {
            return AuthorizationUnavailable();
        }
        catch (InvalidOperationException)
        {
            return AuthorizationUnavailable();
        }
'@ `
    -AlreadyMarker "catch (InvalidOperationException)" `
    -Description "falla cerrada si la auditoria primaria no persiste"

Replace-ExactOnce `
    -RelativePath "apps/api/Security/EffectivePermissionEndpointFilter.cs" `
    -OldText @'
    private static IResult AuthorizationDenied() =>
        Results.Problem(
'@ `
    -NewText @'
    private static IResult AuthorizationUnavailable() =>
        Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Autorización temporalmente no disponible",
            detail:
                "La operación protegida se cerró de forma segura. "
                + "Vuelve a intentarlo más tarde.",
            extensions: new Dictionary<string, object?>
            {
                ["code"] = "security.authorization.unavailable"
            });

    private static IResult AuthorizationDenied() =>
        Results.Problem(
'@ `
    -AlreadyMarker "private static IResult AuthorizationUnavailable()" `
    -Description "respuesta comun de autorizacion/auditoria no disponible"

# -------------------------------------------------------------------
# Assurance privilegiado: objeto = sesión, acción = assurance.
# -------------------------------------------------------------------
Replace-ExactOnce `
    -RelativePath "apps/api/Security/PrivilegedAssuranceEndpointFilter.cs" `
    -OldText @'
            var allowed =
                await service.HasRecentPrivilegedAssuranceAsync(
                    accountId,
                    sessionId,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            if (!allowed)
            {
                return StepUpRequired();
            }

            return await next(context);
'@ `
    -NewText @'
            var allowed =
                await service.HasRecentPrivilegedAssuranceAsync(
                    accountId,
                    sessionId,
                    httpContext.TraceIdentifier,
                    httpContext.RequestAborted);

            var audit =
                httpContext.RequestServices
                    .GetRequiredService<PrimaryAuditRecorder>();

            await audit.RecordPrivilegedAssuranceDecisionAsync(
                accountId,
                sessionId,
                allowed,
                httpContext.TraceIdentifier,
                httpContext.RequestAborted);

            if (!allowed)
            {
                return StepUpRequired();
            }

            return await next(context);
'@ `
    -AlreadyMarker "RecordPrivilegedAssuranceDecisionAsync(" `
    -Description "auditoria de assurance privilegiado"

# -------------------------------------------------------------------
# MFA: éxito/fallo de confirmación y emisión de retos.
# -------------------------------------------------------------------
Add-AfterOnce `
    -RelativePath "src/Modules/Security/Infrastructure/Mfa/PrivilegedMfaService.cs" `
    -Anchor "using MusicaAprender.BuildingBlocks.Infrastructure.Database;`n" `
    -Addition "using MusicaAprender.Modules.Security.Infrastructure.Audit;`n" `
    -AlreadyMarker "using MusicaAprender.Modules.Security.Infrastructure.Audit;" `
    -Description "namespace auditoria en MFA"

Replace-ExactOnce `
    -RelativePath "src/Modules/Security/Infrastructure/Mfa/PrivilegedMfaService.cs" `
    -OldText @'
                    return await InsertChallengeAsync(
                        connection,
                        transaction,
                        accountId,
                        sessionId,
                        EnrollmentOperation,
                        challengeId,
                        digest,
                        "ENROLL_TOTP",
                        EnrollmentChallengeLifetime,
                        token);
'@ `
    -NewText @'
                    var challengeExpiresAt =
                        await InsertChallengeAsync(
                            connection,
                            transaction,
                            accountId,
                            sessionId,
                            EnrollmentOperation,
                            challengeId,
                            digest,
                            "ENROLL_TOTP",
                            EnrollmentChallengeLifetime,
                            token);

                    await PrimaryAuditWriter.WriteSecurityEventAsync(
                        connection,
                        transaction,
                        accountId,
                        "MFA_ENROLLMENT_CHALLENGE",
                        "ISSUED",
                        correlationId,
                        cancellationToken: token);

                    return challengeExpiresAt;
'@ `
    -AlreadyMarker '"MFA_ENROLLMENT_CHALLENGE",' `
    -Description "evento de reto de inscripcion MFA"

# Los dos bloques de código inválido son deliberadamente iguales; se reemplazan
# ambos de una sola vez mediante Replace() controlado aquí.
$mfaPath = "src/Modules/Security/Infrastructure/Mfa/PrivilegedMfaService.cs"
$mfaContent = Read-Normalized -RelativePath $mfaPath
if (-not $mfaContent.Contains('"MFA_ENROLLMENT_CONFIRM",')) {
    $oldFailure = @'
                        var failure = await RegisterFailedAttemptAsync(
                            connection,
                            transaction,
                            challenge,
                            token);

                        return ConfirmationOutcome<MfaStatus>.FromError(
                            MfaAdministrationException.InvalidCode(failure.Exhausted));
'@.Replace("`r`n", "`n").Replace("`r", "`n")
    $newFailure = @'
                        var failure = await RegisterFailedAttemptAsync(
                            connection,
                            transaction,
                            challenge,
                            token);

                        await PrimaryAuditWriter.WriteSecurityEventAsync(
                            connection,
                            transaction,
                            accountId,
                            "MFA_ENROLLMENT_CONFIRM",
                            failure.Exhausted ? "THROTTLED" : "REJECTED",
                            correlationId,
                            cancellationToken: token);

                        return ConfirmationOutcome<MfaStatus>.FromError(
                            MfaAdministrationException.InvalidCode(failure.Exhausted));
'@.Replace("`r`n", "`n").Replace("`r", "`n")

    $occurrences = ([regex]::Matches(
        $mfaContent,
        [regex]::Escape($oldFailure))).Count

    if ($occurrences -lt 2) {
        throw "No se encontraron los dos fallos de confirmacion de inscripcion MFA."
    }

    # Solo los primeros dos pertenecen a ConfirmEnrollment antes de BeginStepUp.
    $confirmStepUpIndex = $mfaContent.IndexOf(
        "public async Task<MfaStatus> ConfirmStepUpAsync",
        [System.StringComparison]::Ordinal)
    $enrollmentSection = $mfaContent.Substring(0, $confirmStepUpIndex)
    $tailSection = $mfaContent.Substring($confirmStepUpIndex)
    $enrollmentMatches = ([regex]::Matches(
        $enrollmentSection,
        [regex]::Escape($oldFailure))).Count

    if ($enrollmentMatches -ne 2) {
        throw "La seccion ConfirmEnrollment no contiene exactamente dos fallos esperados."
    }

    $enrollmentSection = $enrollmentSection.Replace($oldFailure, $newFailure)
    $mfaContent = $enrollmentSection + $tailSection
    Write-Utf8NoBomLf -RelativePath $mfaPath -Content $mfaContent
    Write-Host "OK: fallos de confirmacion de inscripcion MFA auditados."
}
else {
    Write-Host "OK: fallos de confirmacion de inscripcion MFA ya auditados."
}

Replace-ExactOnce `
    -RelativePath "src/Modules/Security/Infrastructure/Mfa/PrivilegedMfaService.cs" `
    -OldText @'
                    await ConsumeChallengeAsync(
                        connection,
                        transaction,
                        challenge.IdempotencyId,
                        token);

                    return ConfirmationOutcome<MfaStatus>.FromValue(
                        new MfaStatus(
                            true,
                            false,
                            MethodType,
                            null));
'@ `
    -NewText @'
                    await ConsumeChallengeAsync(
                        connection,
                        transaction,
                        challenge.IdempotencyId,
                        token);

                    await PrimaryAuditWriter.WriteSecurityEventAsync(
                        connection,
                        transaction,
                        accountId,
                        "MFA_ENROLLMENT_CONFIRM",
                        "SUCCEEDED",
                        correlationId,
                        cancellationToken: token);

                    return ConfirmationOutcome<MfaStatus>.FromValue(
                        new MfaStatus(
                            true,
                            false,
                            MethodType,
                            null));
'@ `
    -AlreadyMarker '"MFA_ENROLLMENT_CONFIRM",`n                        "SUCCEEDED"' `
    -Description "exito de inscripcion MFA"

Replace-ExactOnce `
    -RelativePath "src/Modules/Security/Infrastructure/Mfa/PrivilegedMfaService.cs" `
    -OldText @'
                    return await InsertChallengeAsync(
                        connection,
                        transaction,
                        accountId,
                        sessionId,
                        StepUpOperation,
                        challengeId,
                        randomDigest,
                        "PRIVILEGED",
                        StepUpChallengeLifetime,
                        token);
'@ `
    -NewText @'
                    var challengeExpiresAt =
                        await InsertChallengeAsync(
                            connection,
                            transaction,
                            accountId,
                            sessionId,
                            StepUpOperation,
                            challengeId,
                            randomDigest,
                            "PRIVILEGED",
                            StepUpChallengeLifetime,
                            token);

                    await PrimaryAuditWriter.WriteSecurityEventAsync(
                        connection,
                        transaction,
                        accountId,
                        "MFA_STEP_UP_CHALLENGE",
                        "ISSUED",
                        correlationId,
                        cancellationToken: token);

                    return challengeExpiresAt;
'@ `
    -AlreadyMarker '"MFA_STEP_UP_CHALLENGE",' `
    -Description "evento de reto step-up"

# ConfirmStepUp tiene un único fallo de código.
$mfaContent = Read-Normalized -RelativePath $mfaPath
if (-not $mfaContent.Contains('"MFA_STEP_UP_CONFIRM",')) {
    $confirmIndex = $mfaContent.IndexOf(
        "public async Task<MfaStatus> ConfirmStepUpAsync",
        [System.StringComparison]::Ordinal)
    if ($confirmIndex -lt 0) {
        throw "No se encontro ConfirmStepUpAsync."
    }

    $head = $mfaContent.Substring(0, $confirmIndex)
    $section = $mfaContent.Substring($confirmIndex)

    $oldFailure = @'
                        var failure = await RegisterFailedAttemptAsync(
                            connection,
                            transaction,
                            challenge,
                            token);

                        return ConfirmationOutcome<MfaStatus>.FromError(
                            MfaAdministrationException.InvalidCode(failure.Exhausted));
'@.Replace("`r`n", "`n").Replace("`r", "`n")
    $newFailure = @'
                        var failure = await RegisterFailedAttemptAsync(
                            connection,
                            transaction,
                            challenge,
                            token);

                        await PrimaryAuditWriter.WriteSecurityEventAsync(
                            connection,
                            transaction,
                            accountId,
                            "MFA_STEP_UP_CONFIRM",
                            failure.Exhausted ? "THROTTLED" : "REJECTED",
                            correlationId,
                            cancellationToken: token);

                        return ConfirmationOutcome<MfaStatus>.FromError(
                            MfaAdministrationException.InvalidCode(failure.Exhausted));
'@.Replace("`r`n", "`n").Replace("`r", "`n")

    $matches = ([regex]::Matches(
        $section,
        [regex]::Escape($oldFailure))).Count
    if ($matches -ne 1) {
        throw "ConfirmStepUp no contiene exactamente un fallo esperado."
    }

    $section = $section.Replace($oldFailure, $newFailure)
    Write-Utf8NoBomLf -RelativePath $mfaPath -Content ($head + $section)
    Write-Host "OK: fallo de step-up MFA auditado."
}
else {
    Write-Host "OK: fallo de step-up MFA ya auditado."
}

Replace-ExactOnce `
    -RelativePath "src/Modules/Security/Infrastructure/Mfa/PrivilegedMfaService.cs" `
    -OldText @'
                    var expiresAt = await UpsertRecentAssuranceAsync(
                        connection,
                        transaction,
                        accountId,
                        sessionId,
                        token);

                    return ConfirmationOutcome<MfaStatus>.FromValue(
'@ `
    -NewText @'
                    var expiresAt = await UpsertRecentAssuranceAsync(
                        connection,
                        transaction,
                        accountId,
                        sessionId,
                        token);

                    await PrimaryAuditWriter.WriteSecurityEventAsync(
                        connection,
                        transaction,
                        accountId,
                        "MFA_STEP_UP_CONFIRM",
                        "SUCCEEDED",
                        correlationId,
                        cancellationToken: token);

                    return ConfirmationOutcome<MfaStatus>.FromValue(
'@ `
    -AlreadyMarker '"MFA_STEP_UP_CONFIRM",`n                        "SUCCEEDED"' `
    -Description "exito de step-up MFA"

# -------------------------------------------------------------------
# CI: smoke BL033 después de BL032.
# -------------------------------------------------------------------
Replace-ExactOnce `
    -RelativePath ".github/workflows/ci.yml" `
    -OldText @'
      - name: Verify privileged MFA and recent reauthentication
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL032_USE_DOCKER_PSQL: 'false'
          BL032_API_URL: https://localhost:5448
        run: bash scripts/ci/security/verify-privileged-mfa.sh

      - name: Verify encrypted private object storage
'@ `
    -NewText @'
      - name: Verify privileged MFA and recent reauthentication
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL032_USE_DOCKER_PSQL: 'false'
          BL032_API_URL: https://localhost:5448
        run: bash scripts/ci/security/verify-privileged-mfa.sh

      - name: Verify primary security and audit events
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL033_USE_DOCKER_PSQL: 'false'
          BL033_API_URL: https://localhost:5449
        run: bash scripts/ci/security/verify-primary-audit.sh

      - name: Verify encrypted private object storage
'@ `
    -AlreadyMarker "Verify primary security and audit events" `
    -Description "smoke BL033 en CI"

# -------------------------------------------------------------------
# Herramientas, formato y puertas.
# -------------------------------------------------------------------
& "$PSScriptRoot/check-toolchain.ps1"

$dotnetVersion = (& dotnet --version).Trim()
$nodeVersion = (& node --version).Trim()
$npmVersion = (& npm.cmd --version).Trim()

if (($dotnetVersion -ne $ExpectedDotNet) -or ($nodeVersion -ne $ExpectedNode) -or ($npmVersion -ne $ExpectedNpm)) {
    throw "Toolchain inesperada despues de check-toolchain."
}

& "$PSScriptRoot/local/ensure-local-secrets.ps1"

npm.cmd ci
Assert-LastExitCode "npm ci BL-MVP-033"

$prettier = Join-Path $RepoRoot "node_modules\.bin\prettier.cmd"
$formatTargets = @(
    ".github/workflows/ci.yml",
    "README/BL-MVP-033_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-033.md",
    "docs/engineering/security/primary-audit.md"
)

& $prettier --write @formatTargets
Assert-LastExitCode "Prettier BL-MVP-033"

& $prettier --check @formatTargets
Assert-LastExitCode "Prettier check BL-MVP-033"

$bashPath = Resolve-GitBash
& $bashPath -n "./scripts/ci/security/verify-primary-audit.sh"
Assert-LastExitCode "Sintaxis smoke BL-MVP-033"

npm.cmd run test:e2e:install
Assert-LastExitCode "Instalacion Chromium Playwright BL-MVP-033"

Write-Host "Ejecutando la puerta local completa de calidad..."
& "$PSScriptRoot/check-quality.ps1"

Write-Host "Iniciando el entorno local reproducible..."
& "$PSScriptRoot/local/start.ps1"
& "$PSScriptRoot/local/verify-running.ps1"

$dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
$dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
$dbPort = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"
$webPort = Get-DotEnvValue -Name "WEB_PORT" -DefaultValue "5173"

$passwordPath = Join-Path $RepoRoot "secrets\local\postgres_password"
if (-not (Test-Path $passwordPath -PathType Leaf)) {
    throw "Falta secrets/local/postgres_password."
}

$environmentNames = @(
    "PGHOST",
    "PGPORT",
    "PGUSER",
    "PGDATABASE",
    "PGPASSWORD",
    "BL030_USE_RUNNING_API",
    "BL030_USE_DOCKER_PSQL",
    "BL030_API_URL",
    "BL031_USE_RUNNING_API",
    "BL031_USE_DOCKER_PSQL",
    "BL031_API_URL",
    "BL032_USE_RUNNING_API",
    "BL032_USE_DOCKER_PSQL",
    "BL032_API_URL",
    "BL033_USE_RUNNING_API",
    "BL033_USE_DOCKER_PSQL",
    "BL033_API_URL"
)

$previous = @{}
foreach ($name in $environmentNames) {
    $previous[$name] =
        [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
    $env:PGHOST = "127.0.0.1"
    $env:PGPORT = $dbPort
    $env:PGUSER = $dbUser
    $env:PGDATABASE = $dbName
    $env:PGPASSWORD =
        [System.IO.File]::ReadAllText($passwordPath).Trim()

    $env:BL030_USE_RUNNING_API = "true"
    $env:BL030_USE_DOCKER_PSQL = "true"
    $env:BL030_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/security/verify-effective-authorization.sh"
    Assert-LastExitCode "Regresion BL-MVP-030"

    $env:BL031_USE_RUNNING_API = "true"
    $env:BL031_USE_DOCKER_PSQL = "true"
    $env:BL031_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/security/verify-role-assignments.sh"
    Assert-LastExitCode "Regresion BL-MVP-031"

    $env:BL032_USE_RUNNING_API = "true"
    $env:BL032_USE_DOCKER_PSQL = "true"
    $env:BL032_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/security/verify-privileged-mfa.sh"
    Assert-LastExitCode "Regresion BL-MVP-032"

    $env:BL033_USE_RUNNING_API = "true"
    $env:BL033_USE_DOCKER_PSQL = "true"
    $env:BL033_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/security/verify-primary-audit.sh"
    Assert-LastExitCode "Smoke BL-MVP-033"
}
finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable(
            $name,
            $previous[$name],
            "Process")
    }
}

Restore-GeneratedTypeScriptState

git diff --check
Assert-LastExitCode "git diff --check BL-MVP-033"

# El conjunto final puede contener únicamente las rutas propias de BL033,
# las rutas tracked parcheadas y los untracked que ya existían.
$allowedFinal = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)

foreach ($path in $packagePaths) {
    [void]$allowedFinal.Add($path)
}

@(
    ".github/workflows/ci.yml",
    "apps/api/Program.cs",
    "apps/api/Endpoints/Identity/PersonalAccountRegistrationService.cs",
    "apps/api/Security/EffectivePermissionEndpointFilter.cs",
    "apps/api/Security/PrivilegedAssuranceEndpointFilter.cs",
    "src/Modules/Security/Infrastructure/Authentication/SecuritySessionPersistence.cs",
    "src/Modules/Security/Infrastructure/Mfa/PrivilegedMfaService.cs"
) | ForEach-Object {
    [void]$allowedFinal.Add($_)
}

$unexpected = [System.Collections.Generic.List[string]]::new()
foreach ($line in @(git status --porcelain=v1 --untracked-files=all)) {
    if ($line.Length -lt 4) {
        [void]$unexpected.Add($line)
        continue
    }

    $path = $line.Substring(3).Trim('"').Replace("\", "/")
    if ($path.Contains(" -> ")) {
        $path = ($path -split " -> ", 2)[1]
    }

    if ($allowedFinal.Contains($path)) {
        continue
    }

    if ($line.StartsWith("?? ") -and $foreignUntracked -contains $path) {
        continue
    }

    [void]$unexpected.Add($path)
}

if ($unexpected.Count -gt 0) {
    throw "Inventario final BL-MVP-033 contiene rutas inesperadas: $($unexpected -join ', ')."
}

Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-only
Write-Host ""

Write-Host "OK: BL-MVP-033 instalado y validado localmente con auditoria primaria protegida."
Write-Host "No se ejecuto git add, commit ni push."
