using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;
using MusicaAprender.Api.Catalog;
using MusicaAprender.Api.Content;
using MusicaAprender.Api.Editorial;
using MusicaAprender.Api.Endpoints.Administration;
using MusicaAprender.Api.Endpoints.Editorial;
using MusicaAprender.Api.Endpoints.Identity;
using MusicaAprender.Api.Endpoints.Learning;
using MusicaAprender.Api.Endpoints.PublicCatalog;
using MusicaAprender.Api.Endpoints.Security;
using MusicaAprender.Api.Health;
using MusicaAprender.Api.Learning;
using MusicaAprender.Api.Observability;
using MusicaAprender.Api.Security;
using MusicaAprender.BuildingBlocks.Infrastructure.Configuration;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.BuildingBlocks.Infrastructure.Email.DependencyInjection;
using MusicaAprender.BuildingBlocks.Infrastructure.ObjectStorage.DependencyInjection;
using MusicaAprender.BuildingBlocks.Infrastructure.Observability;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.DependencyInjection;
using MusicaAprender.Modules.Catalog.Infrastructure.Administration;
using MusicaAprender.Modules.Catalog.Infrastructure.Search;
using MusicaAprender.Modules.Configuration.Infrastructure.Administration;
using MusicaAprender.Modules.Configuration.Infrastructure.Publication;
using MusicaAprender.Modules.Content.Infrastructure.Administration;
using MusicaAprender.Modules.Content.Infrastructure.PublicPlayback;
using MusicaAprender.Modules.Editorial.Infrastructure.Administration;
using MusicaAprender.Modules.Editorial.Infrastructure.PublicCatalog;
using MusicaAprender.Modules.Identity.Infrastructure.Preferences;
using MusicaAprender.Modules.Learning.Infrastructure.Administration;
using MusicaAprender.Modules.Learning.Infrastructure.Sessions;
using MusicaAprender.Modules.Security.Infrastructure.Administration;
using MusicaAprender.Modules.Security.Infrastructure.Authentication;
using MusicaAprender.Modules.Security.Infrastructure.Authorization;
using MusicaAprender.Modules.Security.Infrastructure.Credentials;
using MusicaAprender.Modules.Security.Infrastructure.Mfa;
using MusicaAprender.Modules.Security.Infrastructure.Registration;
using MusicaAprender.Modules.Security.Infrastructure.Verification;

var builder = WebApplication.CreateBuilder(args);

builder.Configuration.AddMusicaAprenderExternalConfiguration();

builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<IHttpDatabaseSessionContextFactory, HttpDatabaseSessionContextFactory>();
builder.Services.AddSingleton<IRlsTransactionExecutor, RlsTransactionExecutor>();
builder.Services.AddSingleton<BackofficeSecurityTransactionExecutor>();
builder.Services.AddSingleton<IPrivilegedSecurityTransactionExecutor>(
    static services =>
        services.GetRequiredService<BackofficeSecurityTransactionExecutor>());
builder.Services.AddSingleton<IConfigurationAdministrationTransactionExecutor>(
    static services =>
        new ConfigurationAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<IArtistAdministrationTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ISongDraftAdministrationTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ICreditProvenanceAdministrationTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<IEditorialInboxTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ISongEditorialDossierTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ILyricsStructureAdministrationTransactionExecutor>(
    static services =>
        new ContentAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ITimingAdministrationTransactionExecutor>(
    static services =>
        new ContentAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ITranslationAdministrationTransactionExecutor>(
    static services =>
        new ContentAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ILinguisticAnalysisAdministrationTransactionExecutor>(
    static services =>
        new ContentAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<IExerciseBankAdministrationTransactionExecutor>(
    static services =>
        new LearningAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<IRightsAdministrationTransactionExecutor>(
    static services =>
        new EditorialRightsAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ArtistAdministrationService>();
builder.Services.AddSingleton<SongDraftAdministrationService>();
builder.Services.AddSingleton<CreditProvenanceAdministrationService>();
builder.Services.AddSingleton<EditorialInboxService>();
builder.Services.AddSingleton<SongEditorialDossierService>();
builder.Services.AddSingleton<RecordingDraftAutosaveService>();
builder.Services.AddSingleton<LyricsStructureAdministrationService>();
builder.Services.AddSingleton<TimingRevisionAdministrationService>();
builder.Services.AddSingleton<EditorialKaraokePreviewService>();
builder.Services.AddSingleton<EditorialContextualAnalysisPreviewService>();
builder.Services.AddSingleton<TranslationRevisionAdministrationService>();
builder.Services.AddSingleton<LinguisticAnalysisRevisionAdministrationService>();
builder.Services.AddSingleton<LinguisticAnalysisEditorialWriter>();
builder.Services.AddSingleton<ExerciseBankAdministrationService>();
builder.Services.AddSingleton<FillBlankExerciseAuthoringService>();
builder.Services.AddSingleton<StudySessionStartService>();
builder.Services.AddSingleton<StudyExerciseFlowService>();
builder.Services.AddSingleton<PublicSongSynchronizationService>();
builder.Services.AddSingleton<PublicSongLearningLayersService>();
builder.Services.AddSingleton<PublicContextualAnalysisService>();
builder.Services.AddSingleton<PublicEducationalPackageService>();
builder.Services.AddSingleton<RightsAdministrationService>();
builder.Services.AddSingleton<PublicCatalogProjectionService>();
builder.Services.AddSingleton<PublicCatalogSearchService>();
builder.Services.AddSingleton<PublicSongDetailService>();
builder.Services.AddSingleton<ConfigurationAdministrationService>();
builder.Services.AddSingleton<RoleAssignmentAdministrationService>();
builder.Services.AddSingleton<PrimaryAuditRecorder>();
builder.Services.AddSingleton<PrivilegedMfaService>();
builder.Services.AddSingleton<SecuritySessionPersistence>();
builder.Services.AddSingleton<SecuritySessionTicketStore>();
builder.Services.AddSingleton<
    IPostConfigureOptions<CookieAuthenticationOptions>,
    SecuritySessionCookiePostConfigure>();
builder.Services
    .AddAuthentication(SessionAuthenticationDefaults.Scheme)
    .AddCookie(
        SessionAuthenticationDefaults.Scheme,
        options =>
        {
            options.Cookie.Name = SessionAuthenticationDefaults.CookieName;
            options.Cookie.HttpOnly = true;
            options.Cookie.IsEssential = true;
            options.Cookie.Path = "/";
            options.Cookie.SameSite = SameSiteMode.Strict;
            options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
            options.ExpireTimeSpan = SecuritySessionPolicy.AbsoluteLifetime;
            options.SlidingExpiration = false;
            options.Events.OnRedirectToLogin = context =>
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                return Task.CompletedTask;
            };
            options.Events.OnRedirectToAccessDenied = context =>
            {
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                return Task.CompletedTask;
            };
        });
builder.Services.AddAuthorization();
builder.Services.AddAntiforgery(options =>
{
    options.Cookie.Name = SessionAuthenticationDefaults.AntiforgeryCookieName;
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
    options.Cookie.Path = "/";
    options.Cookie.SameSite = SameSiteMode.Strict;
    options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
    options.HeaderName = SessionAuthenticationDefaults.AntiforgeryHeaderName;
});
builder.Services.AddMusicaAprenderReliableOperations();
builder.Services.AddMusicaAprenderEmailQueue();
builder.Services.AddMusicaAprenderPrivateObjectStore(builder.Configuration);
builder.Services.AddSingleton(
    PersonalEmailProtector.FromConfiguration(builder.Configuration));
builder.Services.AddSingleton(
    PasswordRequestFingerprintService.FromConfiguration(builder.Configuration));
builder.Services.AddSingleton(
    Argon2idPasswordHasher.FromConfiguration(builder.Configuration));
builder.Services.AddSingleton(
    AccountVerificationTokenService.FromConfiguration(builder.Configuration));
builder.Services.AddSingleton<PersonalAccountRegistrationService>();
builder.Services.AddSingleton<PersonalAccountVerificationService>();
builder.Services.AddSingleton(LoginAbusePolicy.FromConfiguration(builder.Configuration));
builder.Services.AddSingleton(
    LoginAbuseFingerprintService.FromConfiguration(builder.Configuration));
builder.Services.AddSingleton<PersonalAccountLoginService>();
builder.Services.AddSingleton<PersonalPreferenceService>();
builder.Services.AddSingleton<MinimumPublishedConfigurationReader>();
builder.Services.AddSingleton<MinimumRoleCatalogReader>();
builder.Services.AddSingleton<EffectiveAuthorizationService>();

builder.Services.AddMusicaAprenderOpenTelemetry(
    builder.Configuration,
    ApiTelemetry.ServiceName,
    ApiTelemetry.ServiceVersion,
    ApiTelemetry.ActivitySourceName,
    ApiTelemetry.MeterName,
    instrumentAspNetCore: true);

builder.Logging.AddMusicaAprenderOpenTelemetryLogging(
    builder.Configuration,
    ApiTelemetry.ServiceName,
    ApiTelemetry.ServiceVersion);

builder.Services.AddHttpClient(
    HealthConstants.HttpClientName,
    client => client.Timeout = HealthConstants.DependencyTimeout);

builder.Services
    .AddHealthChecks()
    .AddCheck(
        "self",
        () => HealthCheckResult.Healthy("Process is alive."),
        tags: HealthConstants.LiveTags)
    .AddCheck<PostgreSqlHealthCheck>(
        "postgresql",
        failureStatus: HealthStatus.Unhealthy,
        tags: HealthConstants.ReadyDependencyTags)
    .AddCheck<MinimumConfigurationHealthCheck>(
        "minimum-configuration",
        failureStatus: HealthStatus.Unhealthy,
        tags: HealthConstants.ReadyDependencyTags)
    .AddCheck<ObjectStoreHealthCheck>(
        "object-store",
        failureStatus: HealthStatus.Degraded,
        tags: HealthConstants.ReadyDependencyTags)
    .AddCheck<SmtpHealthCheck>(
        "smtp",
        failureStatus: HealthStatus.Degraded,
        tags: HealthConstants.ReadyDependencyTags)
    .AddCheck<OpenTelemetryCollectorHealthCheck>(
        "otel-collector",
        failureStatus: HealthStatus.Degraded,
        tags: HealthConstants.ReadyDependencyTags);

var app = builder.Build();

app.UseMiddleware<CorrelationMiddleware>();
app.UseAuthentication();
app.UseAuthorization();
app.UseAntiforgery();

using (var startupActivity = ApiTelemetry.ActivitySource.StartActivity("application.start"))
{
    startupActivity?.SetTag("app.operation.version", "v1");
}

app.MapGet("/", () => Results.Ok(new
{
    service = "MusicaAprender.Api",
    status = "scaffold",
    backlogItem = "BL-MVP-009"
}));

app.MapHealthChecks(
    "/health/live",
    HealthEndpointOptions.Create(HealthConstants.LiveTag));

app.MapHealthChecks(
    "/health/ready",
    HealthEndpointOptions.Create(HealthConstants.ReadyTag));

app.MapHealthChecks(
    "/health/dependencies",
    HealthEndpointOptions.Create(HealthConstants.DependencyTag));

app.MapPersonalAccountRegistration();
app.MapPersonalAccountVerification();
app.MapPersonalAccountLogin();
app.MapPersonalAccountLogout();
app.MapPersonalPreferences();
app.MapAuthorizationCatalog();
app.MapRoleAssignments();
app.MapPrivilegedMfa();
app.MapConfigurationAdministration();
app.MapArtistAdministration();
app.MapSongDraftAdministration();
app.MapEditorialInbox();
app.MapSongEditorialDossier();
app.MapRecordingDraftAutosave();
app.MapLyricsStructureAdministration();
app.MapTimingRevisionAdministration();
app.MapEditorialKaraokePreview();
app.MapEditorialContextualAnalysisPreview();
app.MapTranslationRevisionAdministration();
app.MapLinguisticAnalysisRevisionAdministration();
app.MapExerciseBankAdministration();
app.MapFillBlankExerciseAuthoring();
app.MapStudySessions();
app.MapStudyExerciseFlow();
app.MapCreditProvenanceAdministration();
app.MapRightsAdministration();
app.MapPublicCatalogProjection();
app.MapPublicCatalogSearch();
app.MapPublicSongDetail();
app.MapPublicSongSynchronization();
app.MapPublicSongLearningLayers();
app.MapPublicContextualAnalysis();
app.MapPublicEducationalPackage();

app.Run();

public partial class Program;
