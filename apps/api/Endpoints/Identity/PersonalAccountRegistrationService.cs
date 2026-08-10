using System.Text.Json;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.Idempotency;
using MusicaAprender.Modules.Identity.Infrastructure.Registration;
using MusicaAprender.Modules.Security.Infrastructure.Registration;

namespace MusicaAprender.Api.Endpoints.Identity;

public sealed class PersonalAccountRegistrationService(
    IReliableOperationExecutor reliableOperationExecutor,
    PersonalEmailProtector emailProtector)
{
    private const string OperationCode = "IDENTITY.PERSONAL_ACCOUNT.REGISTER";
    private const string AnonymousRole = "ANONYMOUS";
    private static readonly TimeSpan IdempotencyRetention = TimeSpan.FromHours(24);
    private static readonly JsonSerializerOptions ResponseJsonOptions =
        new(JsonSerializerDefaults.Web);
    private static readonly PersonalAccountRegistrationResponse AcceptedResponse = new(
        "RECEIVED",
        "La solicitud fue recibida. El resultado no confirma si el correo ya estaba registrado.");

    public async Task<PersonalAccountRegistrationResponse?> RegisterAsync(
        string? email,
        string idempotencyKey,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        if (!emailProtector.TryProtect(email, out var protectedEmail)
            || protectedEmail is null)
        {
            return null;
        }

        var proposedAccountId = Guid.CreateVersion7();
        var provisionalContext = DatabaseSessionContext.Create(
            proposedAccountId,
            AnonymousRole,
            correlationId);
        var reliableRequest = ReliableOperationRequest.Create(
            OperationCode,
            idempotencyKey,
            protectedEmail.LookupHash.Span,
            IdempotencyRetention);
        var responseJson = JsonSerializer.Serialize(AcceptedResponse, ResponseJsonOptions);

        var outcome = await reliableOperationExecutor.ExecuteAnonymousAsync(
            provisionalContext,
            reliableRequest,
            async (connection, transaction, token) =>
            {
                var created = await SecurityAccountRegistrationWriter.TryCreatePendingAsync(
                    connection,
                    transaction,
                    proposedAccountId,
                    protectedEmail,
                    token);

                if (created)
                {
                    await IdentityProfileRegistrationWriter.CreateMinimalAsync(
                        connection,
                        transaction,
                        proposedAccountId,
                        token);
                }

                return ReliableOperationResult.Create(
                    StatusCodes.Status202Accepted,
                    responseJson);
            },
            cancellationToken);

        return JsonSerializer.Deserialize<PersonalAccountRegistrationResponse>(
                   outcome.ResponseReferenceJson,
                   ResponseJsonOptions)
               ?? throw new InvalidOperationException(
                   "La respuesta idempotente de registro no contiene un contrato valido.");
    }
}
