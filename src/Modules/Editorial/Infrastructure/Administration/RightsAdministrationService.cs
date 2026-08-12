using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using MusicaAprender.BuildingBlocks.Contracts.ObjectStorage;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Editorial.Infrastructure.Administration;

public sealed record RightsScopeInput(
    string TerritoryCode,
    string? LanguageTag,
    string ChannelCode,
    string UseCode);

public sealed record RightsAdministrationInput(
    string HolderType,
    string HolderDisplayName,
    string BasisCode,
    DateTime? ValidFrom,
    DateTime? ValidTo,
    string EvidenceFileName,
    string EvidenceMediaType,
    string EvidenceBase64,
    IReadOnlyList<RightsScopeInput> Scopes,
    string Reason,
    Guid? SupersedesRightsRecordId);

public sealed record RightsScopeEntry(
    Guid RightsScopeId,
    string TerritoryCode,
    string? LanguageTag,
    string ChannelCode,
    string UseCode);

public sealed record RightsEntry(
    Guid RightsRecordId,
    Guid RightsHolderId,
    string HolderType,
    string HolderDisplayName,
    string ObjectType,
    Guid ObjectId,
    string BasisCode,
    string StatusCode,
    DateTime? ValidFrom,
    DateTime? ValidTo,
    Guid EvidenceObjectId,
    string EvidenceMediaType,
    long EvidenceSizeBytes,
    string EvidenceChecksumSha256,
    DateTime? RecordedAt,
    Guid? RecordedBy,
    IReadOnlyList<RightsScopeEntry> Scopes);

public sealed record RightsCreateResult(
    RightsEntry Rights,
    bool AlreadyApplied);

public sealed record RightsAvailabilityResult(
    bool Allowed,
    string Code,
    string Description,
    Guid? RightsRecordId,
    string TerritoryCode,
    string ChannelCode,
    string UseCode,
    string? LanguageTag,
    DateTime EvaluatedAt);

public sealed class RightsAdministrationException(
    string code,
    string message) : InvalidOperationException(message)
{
    public string Code { get; } = code;
}

public sealed partial class RightsAdministrationService(
    IRightsAdministrationTransactionExecutor transactionExecutor,
    IObjectStore objectStore)
{
    private const int MaxHolderNameLength = 512;
    private const int MaxReasonLength = 2000;
    private const int MaxEvidenceBytes = 2 * 1024 * 1024;
    private const string ActiveStatus = "ACTIVE";
    private const string EvidenceOwnerModule = "M15";
    private const string EvidencePurposeCode = "RIGHTS_EVIDENCE";

    private static readonly HashSet<string> AllowedEvidenceMediaTypes =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "application/pdf",
            "text/plain",
            "image/png",
            "image/jpeg"
        };

    [GeneratedRegex(
        "^[A-Z0-9][A-Z0-9._-]{0,63}$",
        RegexOptions.CultureInvariant)]
    private static partial Regex StableCodePattern();

    [GeneratedRegex(
        "^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$",
        RegexOptions.CultureInvariant)]
    private static partial Regex LanguageTagPattern();

    [GeneratedRegex(
        "\\s+",
        RegexOptions.CultureInvariant)]
    private static partial Regex WhitespacePattern();

    public Task<IReadOnlyList<RightsEntry>> ReadAsync(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateRecordingId(recordingId);

        return transactionExecutor.ExecuteAsync<IReadOnlyList<RightsEntry>>(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                await EnsureRecordingExistsAsync(
                    connection,
                    transaction,
                    recordingId,
                    requireDraft: false,
                    token);

                return await ReadRightsAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);
            },
            cancellationToken);
    }

    public async Task<RightsCreateResult> CreateAsync(
        Guid actorAccountId,
        Guid recordingId,
        RightsAdministrationInput input,
        string idempotencyKey,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateRecordingId(recordingId);
        ArgumentNullException.ThrowIfNull(input);

        if (string.IsNullOrWhiteSpace(idempotencyKey)
            || idempotencyKey.Trim().Length > 128)
        {
            throw new RightsAdministrationException(
                "editorial.rights.idempotency-key.invalid",
                "La operación requiere una clave de idempotencia válida.");
        }

        var prepared = Prepare(input);
        var key = idempotencyKey.Trim();
        var rightsRecordId = CreateDeterministicId(
            actorAccountId,
            recordingId,
            key,
            "RIGHTS-RECORD");

        var replay = await transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                await EnsureRecordingExistsAsync(
                    connection,
                    transaction,
                    recordingId,
                    requireDraft: true,
                    token);

                var existing = await ReadRightByIdAsync(
                    connection,
                    transaction,
                    rightsRecordId,
                    token);

                if (existing is null)
                {
                    return (RightsCreateResult?)null;
                }

                await EnsureReplayMatchesAsync(
                    connection,
                    transaction,
                    rightsRecordId,
                    prepared,
                    token);

                return new RightsCreateResult(existing, AlreadyApplied: true);
            },
            cancellationToken);

        if (replay is not null)
        {
            return replay;
        }

        StoredObjectDescriptor? storedEvidence = null;

        try
        {
            await using var evidenceStream =
                new MemoryStream(prepared.EvidenceBytes, writable: false);

            storedEvidence = await objectStore.StoreAsync(
                new ObjectStoreWriteRequest(
                    EvidenceOwnerModule,
                    EvidencePurposeCode,
                    prepared.EvidenceMediaType,
                    evidenceStream),
                cancellationToken);

            var persistence = await transactionExecutor.ExecuteAsync(
                actorAccountId,
                correlationId,
                (connection, transaction, token) =>
                    PersistAsync(
                        connection,
                        transaction,
                        actorAccountId,
                        recordingId,
                        prepared,
                        key,
                        rightsRecordId,
                        storedEvidence,
                        correlationId,
                        token),
                cancellationToken);

            if (!persistence.EvidenceUsed)
            {
                await DeleteEvidenceAsync(
                    storedEvidence,
                    cancellationToken);
            }

            return persistence.Result;
        }
        catch (RightsAdministrationException)
        {
            if (storedEvidence is not null)
            {
                await DeleteEvidenceAsync(storedEvidence, CancellationToken.None);
            }

            throw;
        }
        catch (NpgsqlException)
        {
            if (storedEvidence is not null)
            {
                await DeleteEvidenceAsync(storedEvidence, CancellationToken.None);
            }

            throw;
        }
        catch (OperationCanceledException)
        {
            if (storedEvidence is not null)
            {
                await DeleteEvidenceAsync(storedEvidence, CancellationToken.None);
            }

            throw;
        }
    }

    public Task<RightsAvailabilityResult> EvaluateAsync(
        Guid actorAccountId,
        Guid recordingId,
        string territoryCode,
        string channelCode,
        string useCode,
        string? languageTag,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateRecordingId(recordingId);

        var territory = NormalizeCode(territoryCode, "Territorio");
        var channel = NormalizeCode(channelCode, "Canal");
        var use = NormalizeCode(useCode, "Uso");
        var language = NormalizeLanguageTag(languageTag);

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            async (connection, transaction, token) =>
            {
                await EnsureRecordingExistsAsync(
                    connection,
                    transaction,
                    recordingId,
                    requireDraft: false,
                    token);

                var evaluatedAt = DateTime.UtcNow;

                if (!await HasProvenanceAsync(
                        connection,
                        transaction,
                        recordingId,
                        token))
                {
                    return new RightsAvailabilityResult(
                        false,
                        "MISSING_PROVENANCE",
                        "La grabación todavía no conserva procedencia editorial suficiente.",
                        null,
                        territory,
                        channel,
                        use,
                        language,
                        evaluatedAt);
                }

                var matchingRightsId = await FindMatchingCurrentRightAsync(
                    connection,
                    transaction,
                    recordingId,
                    territory,
                    channel,
                    use,
                    language,
                    evaluatedAt,
                    token);

                if (matchingRightsId is { } rightId)
                {
                    return new RightsAvailabilityResult(
                        true,
                        "ALLOWED",
                        "Existe autorización vigente, con evidencia privada y alcance exacto para el territorio solicitado.",
                        rightId,
                        territory,
                        channel,
                        use,
                        language,
                        evaluatedAt);
                }

                var currentCount = await CountCurrentRightsAsync(
                    connection,
                    transaction,
                    recordingId,
                    evaluatedAt,
                    token);

                if (currentCount == 0)
                {
                    var anyCount = await CountAnyRightsAsync(
                        connection,
                        transaction,
                        recordingId,
                        token);

                    return new RightsAvailabilityResult(
                        false,
                        anyCount == 0 ? "MISSING_RIGHTS" : "RIGHTS_EXPIRED_OR_INACTIVE",
                        anyCount == 0
                            ? "No existe un expediente de derechos vigente para la grabación."
                            : "Las autorizaciones existentes están vencidas, sustituidas o fuera de vigencia.",
                        null,
                        territory,
                        channel,
                        use,
                        language,
                        evaluatedAt);
                }

                return new RightsAvailabilityResult(
                    false,
                    "TERRITORY_OR_USE_NOT_AUTHORIZED",
                    "El alcance vigente no autoriza esta combinación de territorio, canal, uso e idioma. Una preferencia del usuario no amplía los derechos.",
                    null,
                    territory,
                    channel,
                    use,
                    language,
                    evaluatedAt);
            },
            cancellationToken);
    }

    private Task DeleteEvidenceAsync(
        StoredObjectDescriptor descriptor,
        CancellationToken cancellationToken) =>
        objectStore.DeleteAsync(
            descriptor,
            new ObjectStoreAccessContext(
                EvidenceOwnerModule,
                EvidencePurposeCode),
            cancellationToken);

    private static async Task<PersistenceResult> PersistAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid recordingId,
        PreparedRights prepared,
        string idempotencyKey,
        Guid rightsRecordId,
        StoredObjectDescriptor evidence,
        string correlationId,
        CancellationToken cancellationToken)
    {
        await AcquireLockAsync(
            connection,
            transaction,
            $"EDITORIAL-RIGHTS:{actorAccountId:D}:{recordingId:D}:{idempotencyKey}",
            cancellationToken);

        await EnsureRecordingExistsAsync(
            connection,
            transaction,
            recordingId,
            requireDraft: true,
            cancellationToken);

        var existing = await ReadRightByIdAsync(
            connection,
            transaction,
            rightsRecordId,
            cancellationToken);

        if (existing is not null)
        {
            await EnsureReplayMatchesAsync(
                connection,
                transaction,
                rightsRecordId,
                prepared,
                cancellationToken);

            return new PersistenceResult(
                new RightsCreateResult(existing, AlreadyApplied: true),
                EvidenceUsed: false);
        }

        if (prepared.SupersedesRightsRecordId is { } supersededId)
        {
            await SupersedePreviousAsync(
                connection,
                transaction,
                recordingId,
                supersededId,
                cancellationToken);
        }

        var holderId = CreateDeterministicId(
            actorAccountId,
            recordingId,
            idempotencyKey,
            "RIGHTS-HOLDER");

        await InsertStoredObjectAsync(
            connection,
            transaction,
            evidence,
            cancellationToken);

        await InsertHolderAsync(
            connection,
            transaction,
            holderId,
            prepared,
            cancellationToken);

        await InsertRightsRecordAsync(
            connection,
            transaction,
            rightsRecordId,
            holderId,
            recordingId,
            prepared,
            evidence.ObjectId,
            cancellationToken);

        for (var index = 0; index < prepared.Scopes.Count; index++)
        {
            var scopeId = CreateDeterministicId(
                actorAccountId,
                recordingId,
                idempotencyKey,
                $"RIGHTS-SCOPE-{index}");

            await InsertScopeAsync(
                connection,
                transaction,
                scopeId,
                rightsRecordId,
                prepared.Scopes[index],
                cancellationToken);
        }

        await WriteAuditAsync(
            connection,
            transaction,
            actorAccountId,
            rightsRecordId,
            prepared,
            correlationId,
            cancellationToken);

        var created = await ReadRightByIdAsync(
            connection,
            transaction,
            rightsRecordId,
            cancellationToken)
            ?? throw new InvalidOperationException(
                "El expediente de derechos confirmado no pudo releerse.");

        return new PersistenceResult(
            new RightsCreateResult(created, AlreadyApplied: false),
            EvidenceUsed: true);
    }

    private static PreparedRights Prepare(RightsAdministrationInput input)
    {
        var holderType = NormalizeCode(input.HolderType, "Tipo de titular");
        var holderName = NormalizeText(
            input.HolderDisplayName,
            MaxHolderNameLength,
            "Titular declarado");
        var basis = NormalizeCode(input.BasisCode, "Base de autorización");
        var reason = NormalizeText(input.Reason, MaxReasonLength, "Motivo");

        if (input.ValidFrom is { Kind: DateTimeKind.Local }
            || input.ValidTo is { Kind: DateTimeKind.Local })
        {
            throw new RightsAdministrationException(
                "editorial.rights.validity.local-time",
                "La vigencia debe expresarse como UTC o como instante sin zona interpretado en UTC.");
        }

        var validFrom = NormalizeUtc(input.ValidFrom);
        var validTo = NormalizeUtc(input.ValidTo);

        if (validFrom is not null
            && validTo is not null
            && validTo <= validFrom)
        {
            throw new RightsAdministrationException(
                "editorial.rights.validity.invalid",
                "El vencimiento debe ser posterior al inicio de vigencia.");
        }

        if (string.IsNullOrWhiteSpace(input.EvidenceFileName)
            || input.EvidenceFileName.Trim().Length > 255)
        {
            throw new RightsAdministrationException(
                "editorial.rights.evidence-name.invalid",
                "La evidencia requiere un nombre de archivo válido.");
        }

        var mediaType = input.EvidenceMediaType?.Trim().ToLowerInvariant()
            ?? string.Empty;

        if (!AllowedEvidenceMediaTypes.Contains(mediaType))
        {
            throw new RightsAdministrationException(
                "editorial.rights.evidence-media.invalid",
                "La evidencia debe ser PDF, texto, PNG o JPEG.");
        }

        byte[] evidenceBytes;
        try
        {
            evidenceBytes = Convert.FromBase64String(
                input.EvidenceBase64?.Trim() ?? string.Empty);
        }
        catch (FormatException)
        {
            throw new RightsAdministrationException(
                "editorial.rights.evidence.invalid",
                "La evidencia no tiene una codificación Base64 válida.");
        }

        if (evidenceBytes.Length == 0 || evidenceBytes.Length > MaxEvidenceBytes)
        {
            throw new RightsAdministrationException(
                "editorial.rights.evidence-size.invalid",
                $"La evidencia debe contener entre 1 byte y {MaxEvidenceBytes} bytes.");
        }

        if (input.Scopes is null || input.Scopes.Count == 0)
        {
            throw new RightsAdministrationException(
                "editorial.rights.scope.required",
                "Debe registrarse al menos un territorio, canal y uso autorizados.");
        }

        if (input.Scopes.Count > 64)
        {
            throw new RightsAdministrationException(
                "editorial.rights.scope.too-many",
                "Una autorización no puede registrar más de 64 combinaciones de alcance.");
        }

        var scopes = input.Scopes.Select(PrepareScope).ToArray();
        var duplicates = scopes
            .GroupBy(
                static scope => string.Join(
                    "\u001f",
                    scope.TerritoryCode,
                    scope.LanguageTag ?? string.Empty,
                    scope.ChannelCode,
                    scope.UseCode),
                StringComparer.Ordinal)
            .Any(static group => group.Count() > 1);

        if (duplicates)
        {
            throw new RightsAdministrationException(
                "editorial.rights.scope.duplicate",
                "El mismo territorio, idioma, canal y uso no puede repetirse dentro de la autorización.");
        }

        if (input.SupersedesRightsRecordId == Guid.Empty)
        {
            throw new RightsAdministrationException(
                "editorial.rights.supersedes.invalid",
                "La autorización sustituida no es válida.");
        }

        return new PreparedRights(
            holderType,
            holderName,
            basis,
            validFrom,
            validTo,
            input.EvidenceFileName.Trim(),
            mediaType,
            evidenceBytes,
            Convert.ToHexString(SHA256.HashData(evidenceBytes)).ToLowerInvariant(),
            scopes,
            reason,
            input.SupersedesRightsRecordId);
    }

    private static PreparedScope PrepareScope(RightsScopeInput scope)
    {
        ArgumentNullException.ThrowIfNull(scope);

        return new PreparedScope(
            NormalizeCode(scope.TerritoryCode, "Territorio"),
            NormalizeLanguageTag(scope.LanguageTag),
            NormalizeCode(scope.ChannelCode, "Canal"),
            NormalizeCode(scope.UseCode, "Uso"));
    }

    private static DateTime? NormalizeUtc(DateTime? value)
    {
        if (value is null)
        {
            return null;
        }

        return value.Value.Kind switch
        {
            DateTimeKind.Utc => value.Value,
            DateTimeKind.Unspecified => DateTime.SpecifyKind(value.Value, DateTimeKind.Utc),
            _ => value.Value.ToUniversalTime()
        };
    }

    private static async Task EnsureReplayMatchesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid rightsRecordId,
        PreparedRights prepared,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT after_digest
            FROM security.audit_event
            WHERE object_type = 'RIGHTS_RECORD'
              AND object_id = @rights_record_id
              AND action_code IN ('EDITORIAL.RIGHTS.CREATE', 'EDITORIAL.RIGHTS.REPLACE')
            ORDER BY occurred_at DESC, audit_id DESC
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "rights_record_id",
            NpgsqlDbType.Uuid,
            rightsRecordId);

        var value = await command.ExecuteScalarAsync(cancellationToken);
        if (value is not byte[] existingDigest
            || !CryptographicOperations.FixedTimeEquals(
                existingDigest,
                FingerprintDigest(prepared)))
        {
            throw new RightsAdministrationException(
                "editorial.rights.idempotency-conflict",
                "La clave de idempotencia ya fue utilizada con otro expediente de derechos.");
        }
    }

    private static async Task EnsureRecordingExistsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        bool requireDraft,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT status_code
            FROM catalog.recording
            WHERE recording_id = @recording_id;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);

        var value = await command.ExecuteScalarAsync(cancellationToken);
        if (value is not string status)
        {
            throw new RightsAdministrationException(
                "editorial.rights.recording.not-found",
                "La grabación indicada no existe.");
        }

        if (requireDraft && !string.Equals(status, "DRAFT", StringComparison.Ordinal))
        {
            throw new RightsAdministrationException(
                "editorial.rights.recording.not-draft",
                "Los derechos solo se modifican mientras la grabación está en borrador.");
        }
    }

    private static async Task<bool> HasProvenanceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM catalog.recording_credit c
                JOIN editorial.provenance_record p
                  ON p.object_type = 'RECORDING_CREDIT'
                 AND p.object_id = c.credit_id
                WHERE c.recording_id = @recording_id
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);

        return (bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false);
    }

    private static async Task<Guid?> FindMatchingCurrentRightAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        string territoryCode,
        string channelCode,
        string useCode,
        string? languageTag,
        DateTime evaluatedAt,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT r.rights_record_id
            FROM editorial.rights_record r
            JOIN editorial.rights_scope s
              ON s.rights_record_id = r.rights_record_id
            JOIN ops.stored_object e
              ON e.object_id = r.evidence_object_id
            WHERE r.object_type = 'RECORDING'
              AND r.object_id = @recording_id
              AND r.status_code = 'ACTIVE'
              AND (r.valid_from IS NULL OR r.valid_from <= @evaluated_at)
              AND (r.valid_to IS NULL OR r.valid_to > @evaluated_at)
              AND e.owner_module = 'M15'
              AND e.purpose_code = 'RIGHTS_EVIDENCE'
              AND e.status_code = 'ACTIVE'
              AND s.territory_code = @territory_code
              AND s.channel_code = @channel_code
              AND s.use_code = @use_code
              AND (
                    s.language_tag IS NULL
                    OR (@language_tag IS NOT NULL AND s.language_tag = @language_tag)
                  )
            ORDER BY r.rights_record_id
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        command.Parameters.AddWithValue("evaluated_at", NpgsqlDbType.TimestampTz, evaluatedAt);
        command.Parameters.AddWithValue("territory_code", territoryCode);
        command.Parameters.AddWithValue("channel_code", channelCode);
        command.Parameters.AddWithValue("use_code", useCode);
        command.Parameters.Add(
            new NpgsqlParameter("language_tag", NpgsqlDbType.Varchar)
            {
                Value = languageTag is null ? DBNull.Value : languageTag
            });

        var value = await command.ExecuteScalarAsync(cancellationToken);
        return value is Guid id ? id : null;
    }

    private static async Task<int> CountCurrentRightsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        DateTime evaluatedAt,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT count(*)
            FROM editorial.rights_record r
            JOIN ops.stored_object e
              ON e.object_id = r.evidence_object_id
            WHERE r.object_type = 'RECORDING'
              AND r.object_id = @recording_id
              AND r.status_code = 'ACTIVE'
              AND (r.valid_from IS NULL OR r.valid_from <= @evaluated_at)
              AND (r.valid_to IS NULL OR r.valid_to > @evaluated_at)
              AND e.status_code = 'ACTIVE';
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        command.Parameters.AddWithValue("evaluated_at", NpgsqlDbType.TimestampTz, evaluatedAt);

        return Convert.ToInt32(
            await command.ExecuteScalarAsync(cancellationToken),
            CultureInfo.InvariantCulture);
    }

    private static async Task<int> CountAnyRightsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT count(*)
            FROM editorial.rights_record
            WHERE object_type = 'RECORDING'
              AND object_id = @recording_id;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);

        return Convert.ToInt32(
            await command.ExecuteScalarAsync(cancellationToken),
            CultureInfo.InvariantCulture);
    }

    private static async Task SupersedePreviousAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        Guid rightsRecordId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE editorial.rights_record
            SET status_code = 'SUPERSEDED'
            WHERE rights_record_id = @rights_record_id
              AND object_type = 'RECORDING'
              AND object_id = @recording_id
              AND status_code = 'ACTIVE';
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("rights_record_id", NpgsqlDbType.Uuid, rightsRecordId);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new RightsAdministrationException(
                "editorial.rights.supersedes.not-active",
                "La autorización sustituida no existe, no pertenece a la grabación o ya no está activa.");
        }
    }

    private static async Task InsertStoredObjectAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        StoredObjectDescriptor evidence,
        CancellationToken cancellationToken)
    {
        if (!string.Equals(
                evidence.OwnerModule,
                EvidenceOwnerModule,
                StringComparison.Ordinal)
            || !string.Equals(
                evidence.PurposeCode,
                EvidencePurposeCode,
                StringComparison.Ordinal)
            || !string.Equals(
                evidence.StatusCode,
                ActiveStatus,
                StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "El descriptor de evidencia no cumple el contrato restringido M15.");
        }

        const string sql = """
            SELECT ops.register_rights_evidence_object(
                @object_id,
                @storage_key,
                @media_type,
                @size_bytes,
                @checksum,
                @encryption_key_ref,
                @created_at,
                @retention_until,
                @status_code
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "object_id",
            NpgsqlDbType.Uuid,
            evidence.ObjectId);
        command.Parameters.AddWithValue("storage_key", evidence.StorageKey);
        command.Parameters.AddWithValue("media_type", evidence.MediaType);
        command.Parameters.AddWithValue("size_bytes", evidence.SizeBytes);
        command.Parameters.AddWithValue(
            "checksum",
            NpgsqlDbType.Bytea,
            evidence.Checksum);
        command.Parameters.AddWithValue(
            "encryption_key_ref",
            evidence.EncryptionKeyReference);
        command.Parameters.AddWithValue(
            "created_at",
            NpgsqlDbType.TimestampTz,
            evidence.CreatedAt.UtcDateTime);
        command.Parameters.Add(
            new NpgsqlParameter(
                "retention_until",
                NpgsqlDbType.TimestampTz)
            {
                Value = evidence.RetentionUntil is null
                    ? DBNull.Value
                    : evidence.RetentionUntil.Value.UtcDateTime
            });
        command.Parameters.AddWithValue("status_code", evidence.StatusCode);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }
    private static async Task InsertHolderAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid holderId,
        PreparedRights prepared,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO editorial.rights_holder (
                rights_holder_id,
                holder_type,
                display_name,
                contact_ref,
                status_code
            )
            VALUES (
                @rights_holder_id,
                @holder_type,
                @display_name,
                NULL,
                'ACTIVE'
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("rights_holder_id", NpgsqlDbType.Uuid, holderId);
        command.Parameters.AddWithValue("holder_type", prepared.HolderType);
        command.Parameters.AddWithValue("display_name", prepared.HolderDisplayName);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task InsertRightsRecordAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid rightsRecordId,
        Guid holderId,
        Guid recordingId,
        PreparedRights prepared,
        Guid evidenceObjectId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO editorial.rights_record (
                rights_record_id,
                rights_holder_id,
                object_type,
                object_id,
                basis_code,
                status_code,
                valid_from,
                valid_to,
                evidence_object_id
            )
            VALUES (
                @rights_record_id,
                @rights_holder_id,
                'RECORDING',
                @recording_id,
                @basis_code,
                'ACTIVE',
                @valid_from,
                @valid_to,
                @evidence_object_id
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("rights_record_id", NpgsqlDbType.Uuid, rightsRecordId);
        command.Parameters.AddWithValue("rights_holder_id", NpgsqlDbType.Uuid, holderId);
        command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
        command.Parameters.AddWithValue("basis_code", prepared.BasisCode);
        command.Parameters.Add(
            new NpgsqlParameter("valid_from", NpgsqlDbType.TimestampTz)
            {
                Value = prepared.ValidFrom is null ? DBNull.Value : prepared.ValidFrom.Value
            });
        command.Parameters.Add(
            new NpgsqlParameter("valid_to", NpgsqlDbType.TimestampTz)
            {
                Value = prepared.ValidTo is null ? DBNull.Value : prepared.ValidTo.Value
            });
        command.Parameters.AddWithValue("evidence_object_id", NpgsqlDbType.Uuid, evidenceObjectId);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task InsertScopeAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid scopeId,
        Guid rightsRecordId,
        PreparedScope scope,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO editorial.rights_scope (
                rights_scope_id,
                rights_record_id,
                territory_code,
                language_tag,
                channel_code,
                use_code
            )
            VALUES (
                @rights_scope_id,
                @rights_record_id,
                @territory_code,
                @language_tag,
                @channel_code,
                @use_code
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("rights_scope_id", NpgsqlDbType.Uuid, scopeId);
        command.Parameters.AddWithValue("rights_record_id", NpgsqlDbType.Uuid, rightsRecordId);
        command.Parameters.AddWithValue("territory_code", scope.TerritoryCode);
        command.Parameters.Add(
            new NpgsqlParameter("language_tag", NpgsqlDbType.Varchar)
            {
                Value = scope.LanguageTag is null ? DBNull.Value : scope.LanguageTag
            });
        command.Parameters.AddWithValue("channel_code", scope.ChannelCode);
        command.Parameters.AddWithValue("use_code", scope.UseCode);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<IReadOnlyList<RightsEntry>> ReadRightsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                r.rights_record_id,
                r.rights_holder_id,
                h.holder_type,
                h.display_name,
                r.object_type,
                r.object_id,
                r.basis_code,
                r.status_code,
                r.valid_from,
                r.valid_to,
                r.evidence_object_id,
                e.media_type,
                e.size_bytes,
                encode(e.checksum, 'hex'),
                a.occurred_at,
                a.actor_id
            FROM editorial.rights_record r
            JOIN editorial.rights_holder h
              ON h.rights_holder_id = r.rights_holder_id
            JOIN ops.stored_object e
              ON e.object_id = r.evidence_object_id
            LEFT JOIN LATERAL (
                SELECT occurred_at, actor_id
                FROM security.audit_event
                WHERE object_type = 'RIGHTS_RECORD'
                  AND object_id = r.rights_record_id
                  AND action_code IN ('EDITORIAL.RIGHTS.CREATE', 'EDITORIAL.RIGHTS.REPLACE')
                ORDER BY occurred_at DESC, audit_id DESC
                LIMIT 1
            ) a ON true
            WHERE r.object_type = 'RECORDING'
              AND r.object_id = @recording_id
            ORDER BY a.occurred_at DESC NULLS LAST, r.rights_record_id DESC;
            """;

        var rows = new List<RawRightsRow>();

        await using (var command = new NpgsqlCommand(sql, connection, transaction))
        {
            command.Parameters.AddWithValue("recording_id", NpgsqlDbType.Uuid, recordingId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);

            while (await reader.ReadAsync(cancellationToken))
            {
                rows.Add(ReadRawRow(reader));
            }
        }

        var results = new List<RightsEntry>(rows.Count);
        foreach (var row in rows)
        {
            var scopes = await ReadScopesAsync(
                connection,
                transaction,
                row.RightsRecordId,
                cancellationToken);
            results.Add(row.ToEntry(scopes));
        }

        return results;
    }

    private static async Task<RightsEntry?> ReadRightByIdAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid rightsRecordId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                r.rights_record_id,
                r.rights_holder_id,
                h.holder_type,
                h.display_name,
                r.object_type,
                r.object_id,
                r.basis_code,
                r.status_code,
                r.valid_from,
                r.valid_to,
                r.evidence_object_id,
                e.media_type,
                e.size_bytes,
                encode(e.checksum, 'hex'),
                a.occurred_at,
                a.actor_id
            FROM editorial.rights_record r
            JOIN editorial.rights_holder h
              ON h.rights_holder_id = r.rights_holder_id
            JOIN ops.stored_object e
              ON e.object_id = r.evidence_object_id
            LEFT JOIN LATERAL (
                SELECT occurred_at, actor_id
                FROM security.audit_event
                WHERE object_type = 'RIGHTS_RECORD'
                  AND object_id = r.rights_record_id
                  AND action_code IN ('EDITORIAL.RIGHTS.CREATE', 'EDITORIAL.RIGHTS.REPLACE')
                ORDER BY occurred_at DESC, audit_id DESC
                LIMIT 1
            ) a ON true
            WHERE r.rights_record_id = @rights_record_id
            LIMIT 1;
            """;

        RawRightsRow? row = null;
        await using (var command = new NpgsqlCommand(sql, connection, transaction))
        {
            command.Parameters.AddWithValue("rights_record_id", NpgsqlDbType.Uuid, rightsRecordId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                row = ReadRawRow(reader);
            }
        }

        if (row is null)
        {
            return null;
        }

        var scopes = await ReadScopesAsync(
            connection,
            transaction,
            rightsRecordId,
            cancellationToken);
        return row.ToEntry(scopes);
    }

    private static RawRightsRow ReadRawRow(NpgsqlDataReader reader) =>
        new(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetString(4),
            reader.GetGuid(5),
            reader.GetString(6),
            reader.GetString(7),
            reader.IsDBNull(8) ? null : reader.GetDateTime(8),
            reader.IsDBNull(9) ? null : reader.GetDateTime(9),
            reader.GetGuid(10),
            reader.GetString(11),
            reader.GetInt64(12),
            reader.GetString(13),
            reader.IsDBNull(14) ? null : reader.GetDateTime(14),
            reader.IsDBNull(15) ? null : reader.GetGuid(15));

    private static async Task<IReadOnlyList<RightsScopeEntry>> ReadScopesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid rightsRecordId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT rights_scope_id, territory_code, language_tag, channel_code, use_code
            FROM editorial.rights_scope
            WHERE rights_record_id = @rights_record_id
            ORDER BY territory_code, language_tag NULLS FIRST, channel_code, use_code;
            """;

        var results = new List<RightsScopeEntry>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("rights_record_id", NpgsqlDbType.Uuid, rightsRecordId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(new RightsScopeEntry(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.IsDBNull(2) ? null : reader.GetString(2),
                reader.GetString(3),
                reader.GetString(4)));
        }

        return results;
    }

    private static async Task AcquireLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string lockKey,
        CancellationToken cancellationToken)
    {
        const string sql =
            "SELECT pg_advisory_xact_lock(hashtextextended(@lock_key, 0));";

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("lock_key", lockKey);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task WriteAuditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid rightsRecordId,
        PreparedRights prepared,
        string correlationId,
        CancellationToken cancellationToken)
    {
        var roleCode = await ReadAuditRoleCodeAsync(
            connection,
            transaction,
            actorAccountId,
            cancellationToken);

        var actionCode = prepared.SupersedesRightsRecordId is null
            ? "EDITORIAL.RIGHTS.CREATE"
            : "EDITORIAL.RIGHTS.REPLACE";

        var beforeDigest = prepared.SupersedesRightsRecordId is null
            ? null
            : SHA256.HashData(
                Encoding.UTF8.GetBytes(
                    prepared.SupersedesRightsRecordId.Value.ToString("D")));

        const string sql = """
            INSERT INTO security.audit_event (
                actor_id,
                role_code,
                object_type,
                object_id,
                action_code,
                before_digest,
                after_digest,
                reason,
                occurred_at,
                correlation_id
            )
            VALUES (
                @actor_id,
                @role_code,
                'RIGHTS_RECORD',
                @rights_record_id,
                @action_code,
                @before_digest,
                @after_digest,
                @reason,
                CURRENT_TIMESTAMP,
                @correlation_id
            );
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("actor_id", NpgsqlDbType.Uuid, actorAccountId);
        command.Parameters.AddWithValue("role_code", roleCode);
        command.Parameters.AddWithValue("rights_record_id", NpgsqlDbType.Uuid, rightsRecordId);
        command.Parameters.AddWithValue("action_code", actionCode);
        command.Parameters.Add(
            new NpgsqlParameter("before_digest", NpgsqlDbType.Bytea)
            {
                Value = beforeDigest is null ? DBNull.Value : beforeDigest
            });
        command.Parameters.AddWithValue(
            "after_digest",
            NpgsqlDbType.Bytea,
            FingerprintDigest(prepared));
        command.Parameters.AddWithValue(
            "reason",
            prepared.SupersedesRightsRecordId is null
                ? prepared.Reason
                : $"Sustituye rights_record {prepared.SupersedesRightsRecordId:D}. {prepared.Reason}");
        command.Parameters.AddWithValue(
            "correlation_id",
            NpgsqlDbType.Uuid,
            CorrelationGuid(correlationId));

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<string> ReadAuditRoleCodeAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT r.role_code
            FROM security.role_assignment a
            JOIN security.role r
              ON r.role_id = a.role_id
            JOIN security.role_permission rp
              ON rp.role_id = r.role_id
            JOIN security.permission p
              ON p.permission_id = rp.permission_id
            WHERE a.account_id = @actor_id
              AND p.permission_code = 'EDITORIAL.DRAFT'
              AND r.status_code = 'ACTIVE'
              AND a.valid_from <= CURRENT_TIMESTAMP
              AND (a.valid_to IS NULL OR a.valid_to > CURRENT_TIMESTAMP)
              AND rp.valid_from <= CURRENT_TIMESTAMP
              AND (rp.valid_to IS NULL OR rp.valid_to > CURRENT_TIMESTAMP)
            ORDER BY r.role_code
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("actor_id", NpgsqlDbType.Uuid, actorAccountId);

        var value = await command.ExecuteScalarAsync(cancellationToken);
        if (value is not string roleCode || string.IsNullOrWhiteSpace(roleCode))
        {
            throw new RightsAdministrationException(
                "editorial.rights.audit-role.missing",
                "No se pudo resolver la función editorial vigente para la auditoría.");
        }

        return roleCode;
    }

    private static byte[] FingerprintDigest(PreparedRights prepared) =>
        SHA256.HashData(Encoding.UTF8.GetBytes(Fingerprint(prepared)));

    private static string Fingerprint(PreparedRights prepared) =>
        string.Join(
            "\n",
            prepared.HolderType,
            prepared.HolderDisplayName,
            prepared.BasisCode,
            prepared.ValidFrom?.ToString("O", CultureInfo.InvariantCulture) ?? string.Empty,
            prepared.ValidTo?.ToString("O", CultureInfo.InvariantCulture) ?? string.Empty,
            prepared.EvidenceFileName,
            prepared.EvidenceMediaType,
            prepared.EvidenceChecksumSha256,
            string.Join(
                "|",
                prepared.Scopes.Select(
                    static scope => string.Join(
                        ":",
                        scope.TerritoryCode,
                        scope.LanguageTag ?? string.Empty,
                        scope.ChannelCode,
                        scope.UseCode))),
            prepared.Reason,
            prepared.SupersedesRightsRecordId?.ToString("D") ?? string.Empty);

    private static Guid CreateDeterministicId(
        Guid actorAccountId,
        Guid recordingId,
        string idempotencyKey,
        string kind)
    {
        var material =
            $"{actorAccountId:D}\nEDITORIAL.RIGHTS.CREATE\n{recordingId:D}\n{idempotencyKey}\n{kind}";
        var digest = SHA256.HashData(Encoding.UTF8.GetBytes(material));

        Span<byte> bytes = stackalloc byte[16];
        digest.AsSpan(0, 16).CopyTo(bytes);
        bytes[6] = (byte)((bytes[6] & 0x0f) | 0x50);
        bytes[8] = (byte)((bytes[8] & 0x3f) | 0x80);

        var id = new Guid(bytes);
        return id != Guid.Empty
            ? id
            : throw new InvalidOperationException(
                "No se pudo derivar una identidad estable.");
    }

    private static Guid CorrelationGuid(string correlationId)
    {
        if (Guid.TryParse(correlationId, out var parsed) && parsed != Guid.Empty)
        {
            return parsed;
        }

        var digest = SHA256.HashData(Encoding.UTF8.GetBytes(correlationId));
        Span<byte> bytes = stackalloc byte[16];
        digest.AsSpan(0, 16).CopyTo(bytes);
        return new Guid(bytes);
    }

    private static string NormalizeText(string value, int maxLength, string label)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new RightsAdministrationException(
                "editorial.rights.text.required",
                $"{label} es obligatorio.");
        }

        var normalized = WhitespacePattern().Replace(
            value.Normalize(NormalizationForm.FormC).Trim(),
            " ");

        if (normalized.Length > maxLength)
        {
            throw new RightsAdministrationException(
                "editorial.rights.text.too-long",
                $"{label} supera {maxLength} caracteres.");
        }

        return normalized;
    }

    private static string NormalizeCode(string value, string label)
    {
        var normalized = value?.Trim().ToUpperInvariant() ?? string.Empty;

        if (!StableCodePattern().IsMatch(normalized))
        {
            throw new RightsAdministrationException(
                "editorial.rights.code.invalid",
                $"{label} no cumple el formato estable esperado.");
        }

        return normalized;
    }

    private static string? NormalizeLanguageTag(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var normalized = value.Trim();
        if (!LanguageTagPattern().IsMatch(normalized))
        {
            throw new RightsAdministrationException(
                "editorial.rights.language.invalid",
                "La etiqueta de idioma no tiene formato BCP-47 válido.");
        }

        return normalized;
    }

    private static void ValidateRecordingId(Guid recordingId)
    {
        if (recordingId == Guid.Empty)
        {
            throw new RightsAdministrationException(
                "editorial.rights.recording.invalid",
                "La grabación indicada no es válida.");
        }
    }

    private sealed record PreparedScope(
        string TerritoryCode,
        string? LanguageTag,
        string ChannelCode,
        string UseCode);

    private sealed record PreparedRights(
        string HolderType,
        string HolderDisplayName,
        string BasisCode,
        DateTime? ValidFrom,
        DateTime? ValidTo,
        string EvidenceFileName,
        string EvidenceMediaType,
        byte[] EvidenceBytes,
        string EvidenceChecksumSha256,
        IReadOnlyList<PreparedScope> Scopes,
        string Reason,
        Guid? SupersedesRightsRecordId);

    private sealed record PersistenceResult(
        RightsCreateResult Result,
        bool EvidenceUsed);

    private sealed record RawRightsRow(
        Guid RightsRecordId,
        Guid RightsHolderId,
        string HolderType,
        string HolderDisplayName,
        string ObjectType,
        Guid ObjectId,
        string BasisCode,
        string StatusCode,
        DateTime? ValidFrom,
        DateTime? ValidTo,
        Guid EvidenceObjectId,
        string EvidenceMediaType,
        long EvidenceSizeBytes,
        string EvidenceChecksumSha256,
        DateTime? RecordedAt,
        Guid? RecordedBy)
    {
        public RightsEntry ToEntry(IReadOnlyList<RightsScopeEntry> scopes) =>
            new(
                RightsRecordId,
                RightsHolderId,
                HolderType,
                HolderDisplayName,
                ObjectType,
                ObjectId,
                BasisCode,
                StatusCode,
                ValidFrom,
                ValidTo,
                EvidenceObjectId,
                EvidenceMediaType,
                EvidenceSizeBytes,
                EvidenceChecksumSha256,
                RecordedAt,
                RecordedBy,
                scopes);
    }
}
