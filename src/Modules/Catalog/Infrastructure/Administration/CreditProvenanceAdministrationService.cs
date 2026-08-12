using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Catalog.Infrastructure.Administration;

public sealed record CreditProvenanceInput(
    Guid? ArtistId,
    string DisplayName,
    string RoleCode,
    int DisplayOrder,
    string SourceType,
    string Citation,
    string? Locator,
    string VerificationCode);

public sealed record CreditProvenanceEntry(
    Guid CreditId,
    Guid RecordingId,
    Guid? ArtistId,
    string DisplayName,
    string RoleCode,
    int DisplayOrder,
    Guid SourceReferenceId,
    string SourceType,
    string Citation,
    string? Locator,
    DateTime? RetrievedAt,
    Guid ProvenanceId,
    string VerificationCode,
    bool PendingIdentity);

public sealed record CreditProvenanceCreatedResult(
    CreditProvenanceEntry Credit,
    bool AlreadyApplied);

public sealed class CreditProvenanceAdministrationException(
    string code,
    string message) : InvalidOperationException(message)
{
    public string Code { get; } = code;
}

public sealed partial class CreditProvenanceAdministrationService(
    ICreditProvenanceAdministrationTransactionExecutor transactionExecutor)
{
    private const int MaxDisplayNameLength = 512;
    private const int MaxCitationLength = 2048;
    private const int MaxLocatorLength = 2048;
    private const string DraftStatus = "DRAFT";
    private const string Verified = "VERIFIED";
    private const string Unverified = "UNVERIFIED";
    private const string PendingIdentity = "PENDING_IDENTITY";

    [GeneratedRegex(
        "^[A-Z0-9][A-Z0-9._-]{0,63}$",
        RegexOptions.CultureInvariant)]
    private static partial Regex StableCodePattern();

    [GeneratedRegex(
        "\\s+",
        RegexOptions.CultureInvariant)]
    private static partial Regex WhitespacePattern();

    public Task<IReadOnlyList<CreditProvenanceEntry>> ReadAsync(
        Guid actorAccountId,
        Guid recordingId,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateRecordingId(recordingId);

        return transactionExecutor.ExecuteAsync<IReadOnlyList<CreditProvenanceEntry>>(
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

                return await ReadCreditsAsync(
                    connection,
                    transaction,
                    recordingId,
                    token);
            },
            cancellationToken);
    }

    public Task<CreditProvenanceCreatedResult> CreateAsync(
        Guid actorAccountId,
        Guid recordingId,
        CreditProvenanceInput input,
        string idempotencyKey,
        string correlationId,
        CancellationToken cancellationToken = default)
    {
        ValidateRecordingId(recordingId);
        ArgumentNullException.ThrowIfNull(input);

        if (string.IsNullOrWhiteSpace(idempotencyKey)
            || idempotencyKey.Trim().Length > 128)
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.idempotency-key.invalid",
                "La creación requiere una clave de idempotencia válida.");
        }

        return transactionExecutor.ExecuteAsync(
            actorAccountId,
            correlationId,
            (connection, transaction, token) =>
                CreateCoreAsync(
                    connection,
                    transaction,
                    actorAccountId,
                    recordingId,
                    input,
                    idempotencyKey.Trim(),
                    correlationId,
                    token),
            cancellationToken);
    }

    private static async Task<CreditProvenanceCreatedResult> CreateCoreAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid recordingId,
        CreditProvenanceInput input,
        string idempotencyKey,
        string correlationId,
        CancellationToken cancellationToken)
    {
        var prepared = Prepare(input);

        await AcquireLockAsync(
            connection,
            transaction,
            $"RECORDING-CREDIT:IDEMPOTENCY:{actorAccountId:D}:{recordingId:D}:{idempotencyKey}",
            cancellationToken);
        await AcquireLockAsync(
            connection,
            transaction,
            $"RECORDING-CREDIT:ORDER:{recordingId:D}:{prepared.DisplayOrder}",
            cancellationToken);

        await EnsureRecordingExistsAsync(
            connection,
            transaction,
            recordingId,
            requireDraft: true,
            cancellationToken);

        if (prepared.ArtistId is { } artistId)
        {
            await EnsureArtistExistsAsync(
                connection,
                transaction,
                artistId,
                cancellationToken);
        }

        var creditId = CreateDeterministicId(
            actorAccountId,
            recordingId,
            idempotencyKey,
            "CREDIT");
        var sourceReferenceId = CreateDeterministicId(
            actorAccountId,
            recordingId,
            idempotencyKey,
            "SOURCE-REFERENCE");
        var provenanceId = CreateDeterministicId(
            actorAccountId,
            recordingId,
            idempotencyKey,
            "PROVENANCE");

        var existing = await ReadCreditByIdAsync(
            connection,
            transaction,
            creditId,
            cancellationToken);

        if (existing is not null)
        {
            if (!Matches(existing, prepared))
            {
                throw new CreditProvenanceAdministrationException(
                    "catalog.credit.idempotency-conflict",
                    "La clave de idempotencia ya fue utilizada para un crédito diferente.");
            }

            return new CreditProvenanceCreatedResult(
                existing,
                AlreadyApplied: true);
        }

        await EnsureOrderAvailableAsync(
            connection,
            transaction,
            recordingId,
            prepared.DisplayOrder,
            cancellationToken);

        await EnsureNotDuplicateAsync(
            connection,
            transaction,
            recordingId,
            prepared,
            cancellationToken);

        await InsertSourceReferenceAsync(
            connection,
            transaction,
            sourceReferenceId,
            prepared,
            cancellationToken);
        await InsertCreditAsync(
            connection,
            transaction,
            creditId,
            recordingId,
            prepared,
            cancellationToken);
        await InsertProvenanceAsync(
            connection,
            transaction,
            provenanceId,
            creditId,
            sourceReferenceId,
            actorAccountId,
            prepared,
            cancellationToken);
        await WriteAuditAsync(
            connection,
            transaction,
            actorAccountId,
            creditId,
            prepared,
            correlationId,
            cancellationToken);

        var created = await ReadCreditByIdAsync(
            connection,
            transaction,
            creditId,
            cancellationToken)
            ?? throw new InvalidOperationException(
                "El crédito confirmado no pudo releerse dentro de la transacción.");

        return new CreditProvenanceCreatedResult(
            created,
            AlreadyApplied: false);
    }

    private static PreparedCredit Prepare(CreditProvenanceInput input)
    {
        var displayName = NormalizeText(
            input.DisplayName,
            MaxDisplayNameLength,
            "Nombre visible del participante");
        var roleCode = NormalizeCode(
            input.RoleCode,
            "Rol del crédito");
        var sourceType = NormalizeCode(
            input.SourceType,
            "Tipo de fuente");
        var citation = NormalizeText(
            input.Citation,
            MaxCitationLength,
            "Cita o referencia de procedencia");
        var locator = NormalizeOptionalText(
            input.Locator,
            MaxLocatorLength,
            "Localizador de la fuente");
        var verificationCode = NormalizeCode(
            input.VerificationCode,
            "Estado de verificación");

        if (input.DisplayOrder < 0)
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.display-order.invalid",
                "El orden de presentación no puede ser negativo.");
        }

        if (input.ArtistId is { } artistId && artistId == Guid.Empty)
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.artist.invalid",
                "La identidad de artista seleccionada no es válida.");
        }

        if (input.ArtistId is null)
        {
            if (!string.Equals(
                    verificationCode,
                    PendingIdentity,
                    StringComparison.Ordinal))
            {
                throw new CreditProvenanceAdministrationException(
                    "catalog.credit.pending-identity.required",
                    "Un participante sin identidad canónica debe quedar explícitamente como PENDING_IDENTITY.");
            }
        }
        else if (string.Equals(
                     verificationCode,
                     PendingIdentity,
                     StringComparison.Ordinal))
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.verification.invalid",
                "PENDING_IDENTITY solo se usa cuando todavía no existe una identidad canónica enlazada.");
        }

        if (!string.Equals(verificationCode, Verified, StringComparison.Ordinal)
            && !string.Equals(verificationCode, Unverified, StringComparison.Ordinal)
            && !string.Equals(verificationCode, PendingIdentity, StringComparison.Ordinal))
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.verification.invalid",
                "La verificación debe ser VERIFIED, UNVERIFIED o PENDING_IDENTITY.");
        }

        return new PreparedCredit(
            input.ArtistId,
            displayName,
            roleCode,
            input.DisplayOrder,
            sourceType,
            citation,
            locator,
            verificationCode);
    }

    private static async Task AcquireLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string lockKey,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT pg_catalog.pg_advisory_xact_lock(
                pg_catalog.hashtextextended(@lock_key, 0)
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("lock_key", lockKey);
        await command.ExecuteNonQueryAsync(cancellationToken);
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
            WHERE recording_id = @recording_id
            FOR SHARE;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        var value = await command.ExecuteScalarAsync(cancellationToken);
        if (value is not string statusCode)
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.recording.not-found",
                "La grabación indicada no existe.");
        }

        if (requireDraft
            && !string.Equals(
                statusCode,
                DraftStatus,
                StringComparison.Ordinal))
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.recording.not-draft",
                "Los créditos solo se modifican mientras la grabación está en DRAFT.");
        }
    }

    private static async Task EnsureArtistExistsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid artistId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM catalog.artist
                WHERE artist_id = @artist_id
                  AND status_code = 'ACTIVE'
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "artist_id",
            NpgsqlDbType.Uuid,
            artistId);

        var exists = (bool)(await command.ExecuteScalarAsync(cancellationToken)
            ?? false);

        if (!exists)
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.artist.not-found",
                "La identidad de artista seleccionada no existe o no está activa.");
        }
    }

    private static async Task EnsureOrderAvailableAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        int displayOrder,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM catalog.recording_credit
                WHERE recording_id = @recording_id
                  AND display_order = @display_order
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);
        command.Parameters.AddWithValue(
            "display_order",
            NpgsqlDbType.Integer,
            displayOrder);

        var exists = (bool)(await command.ExecuteScalarAsync(cancellationToken)
            ?? false);

        if (exists)
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.display-order.conflict",
                "Ese orden de presentación ya está ocupado en la grabación.");
        }
    }

    private static async Task EnsureNotDuplicateAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        PreparedCredit prepared,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS (
                SELECT 1
                FROM catalog.recording_credit
                WHERE recording_id = @recording_id
                  AND role_code = @role_code
                  AND (
                      (
                          @artist_id IS NOT NULL
                          AND artist_id = @artist_id
                      )
                      OR (
                          @artist_id IS NULL
                          AND artist_id IS NULL
                          AND upper(btrim(display_name))
                              = upper(btrim(@display_name))
                      )
                  )
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);
        command.Parameters.AddWithValue(
            "role_code",
            prepared.RoleCode);
        var artist = command.Parameters.Add(
            "artist_id",
            NpgsqlDbType.Uuid);
        artist.Value = prepared.ArtistId is { } artistId
            ? artistId
            : DBNull.Value;
        command.Parameters.AddWithValue(
            "display_name",
            prepared.DisplayName);

        var exists = (bool)(await command.ExecuteScalarAsync(cancellationToken)
            ?? false);

        if (exists)
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.duplicate",
                "Ya existe un crédito con el mismo participante y rol para esta grabación.");
        }
    }

    private static async Task InsertSourceReferenceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid sourceReferenceId,
        PreparedCredit prepared,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO catalog.source_reference (
                source_reference_id,
                source_type,
                citation,
                locator,
                retrieved_at,
                checksum
            )
            VALUES (
                @source_reference_id,
                @source_type,
                @citation,
                @locator,
                CURRENT_TIMESTAMP,
                NULL
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "source_reference_id",
            NpgsqlDbType.Uuid,
            sourceReferenceId);
        command.Parameters.AddWithValue(
            "source_type",
            prepared.SourceType);
        command.Parameters.AddWithValue(
            "citation",
            prepared.Citation);
        var locator = command.Parameters.Add(
            "locator",
            NpgsqlDbType.Text);
        locator.Value = prepared.Locator is { } value
            ? value
            : DBNull.Value;

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task InsertCreditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid creditId,
        Guid recordingId,
        PreparedCredit prepared,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO catalog.recording_credit (
                credit_id,
                recording_id,
                artist_id,
                display_name,
                role_code,
                display_order
            )
            VALUES (
                @credit_id,
                @recording_id,
                @artist_id,
                @display_name,
                @role_code,
                @display_order
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "credit_id",
            NpgsqlDbType.Uuid,
            creditId);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);
        var artist = command.Parameters.Add(
            "artist_id",
            NpgsqlDbType.Uuid);
        artist.Value = prepared.ArtistId is { } artistId
            ? artistId
            : DBNull.Value;
        command.Parameters.AddWithValue(
            "display_name",
            prepared.DisplayName);
        command.Parameters.AddWithValue(
            "role_code",
            prepared.RoleCode);
        command.Parameters.AddWithValue(
            "display_order",
            NpgsqlDbType.Integer,
            prepared.DisplayOrder);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task InsertProvenanceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid provenanceId,
        Guid creditId,
        Guid sourceReferenceId,
        Guid actorAccountId,
        PreparedCredit prepared,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO editorial.provenance_record (
                provenance_id,
                object_type,
                object_id,
                source_reference_id,
                contribution_type,
                recorded_by,
                recorded_at
            )
            VALUES (
                @provenance_id,
                'RECORDING_CREDIT',
                @credit_id,
                @source_reference_id,
                @contribution_type,
                @recorded_by,
                CURRENT_TIMESTAMP
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "provenance_id",
            NpgsqlDbType.Uuid,
            provenanceId);
        command.Parameters.AddWithValue(
            "credit_id",
            NpgsqlDbType.Uuid,
            creditId);
        command.Parameters.AddWithValue(
            "source_reference_id",
            NpgsqlDbType.Uuid,
            sourceReferenceId);
        command.Parameters.AddWithValue(
            "contribution_type",
            ToContributionType(prepared.VerificationCode));
        command.Parameters.AddWithValue(
            "recorded_by",
            NpgsqlDbType.Uuid,
            actorAccountId);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<List<CreditProvenanceEntry>> ReadCreditsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid recordingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                c.credit_id,
                c.recording_id,
                c.artist_id,
                c.display_name,
                c.role_code,
                c.display_order,
                sr.source_reference_id,
                sr.source_type,
                sr.citation,
                sr.locator,
                sr.retrieved_at,
                pr.provenance_id,
                pr.contribution_type
            FROM catalog.recording_credit c
            JOIN LATERAL (
                SELECT p.provenance_id,
                       p.source_reference_id,
                       p.contribution_type,
                       p.recorded_at
                FROM editorial.provenance_record p
                WHERE p.object_type = 'RECORDING_CREDIT'
                  AND p.object_id = c.credit_id
                ORDER BY p.recorded_at DESC, p.provenance_id DESC
                LIMIT 1
            ) pr ON true
            JOIN catalog.source_reference sr
              ON sr.source_reference_id = pr.source_reference_id
            WHERE c.recording_id = @recording_id
            ORDER BY c.display_order, c.credit_id;
            """;

        var results = new List<CreditProvenanceEntry>();
        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            recordingId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(ReadEntry(reader));
        }

        return results;
    }

    private static async Task<CreditProvenanceEntry?> ReadCreditByIdAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid creditId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                c.credit_id,
                c.recording_id,
                c.artist_id,
                c.display_name,
                c.role_code,
                c.display_order,
                sr.source_reference_id,
                sr.source_type,
                sr.citation,
                sr.locator,
                sr.retrieved_at,
                pr.provenance_id,
                pr.contribution_type
            FROM catalog.recording_credit c
            JOIN editorial.provenance_record pr
              ON pr.object_type = 'RECORDING_CREDIT'
             AND pr.object_id = c.credit_id
            JOIN catalog.source_reference sr
              ON sr.source_reference_id = pr.source_reference_id
            WHERE c.credit_id = @credit_id
            ORDER BY pr.recorded_at DESC, pr.provenance_id DESC
            LIMIT 1;
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue(
            "credit_id",
            NpgsqlDbType.Uuid,
            creditId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        return await reader.ReadAsync(cancellationToken)
            ? ReadEntry(reader)
            : null;
    }

    private static CreditProvenanceEntry ReadEntry(NpgsqlDataReader reader)
    {
        var verificationCode =
            FromContributionType(reader.GetString(12));

        return new CreditProvenanceEntry(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.IsDBNull(2) ? null : reader.GetGuid(2),
            reader.GetString(3),
            reader.GetString(4),
            reader.GetInt32(5),
            reader.GetGuid(6),
            reader.GetString(7),
            reader.GetString(8),
            reader.IsDBNull(9) ? null : reader.GetString(9),
            reader.IsDBNull(10) ? null : reader.GetDateTime(10),
            reader.GetGuid(11),
            verificationCode,
            string.Equals(
                verificationCode,
                PendingIdentity,
                StringComparison.Ordinal));
    }

    private static bool Matches(
        CreditProvenanceEntry existing,
        PreparedCredit prepared)
    {
        return existing.ArtistId == prepared.ArtistId
            && string.Equals(existing.DisplayName, prepared.DisplayName, StringComparison.Ordinal)
            && string.Equals(existing.RoleCode, prepared.RoleCode, StringComparison.Ordinal)
            && existing.DisplayOrder == prepared.DisplayOrder
            && string.Equals(existing.SourceType, prepared.SourceType, StringComparison.Ordinal)
            && string.Equals(existing.Citation, prepared.Citation, StringComparison.Ordinal)
            && string.Equals(existing.Locator, prepared.Locator, StringComparison.Ordinal)
            && string.Equals(existing.VerificationCode, prepared.VerificationCode, StringComparison.Ordinal);
    }

    private static string NormalizeText(
        string value,
        int maxLength,
        string label)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.text.required",
                $"{label} es obligatorio.");
        }

        var normalized = WhitespacePattern().Replace(
            value.Normalize(NormalizationForm.FormC).Trim(),
            " ");

        if (normalized.Length > maxLength)
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.text.too-long",
                $"{label} supera {maxLength} caracteres.");
        }

        return normalized;
    }

    private static string? NormalizeOptionalText(
        string? value,
        int maxLength,
        string label)
    {
        return string.IsNullOrWhiteSpace(value)
            ? null
            : NormalizeText(value, maxLength, label);
    }

    private static string NormalizeCode(
        string value,
        string label)
    {
        var normalized = value?.Trim().ToUpperInvariant()
            ?? string.Empty;

        if (!StableCodePattern().IsMatch(normalized))
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.code.invalid",
                $"{label} no cumple el formato estable esperado.");
        }

        return normalized;
    }

    private static string ToContributionType(
        string verificationCode) => verificationCode switch
        {
            Verified => "CREDIT_VERIFIED",
            Unverified => "CREDIT_UNVERIFIED",
            PendingIdentity => "CREDIT_PENDING_IDENTITY",
            _ => throw new ArgumentOutOfRangeException(nameof(verificationCode))
        };

    private static string FromContributionType(
        string contributionType) => contributionType switch
        {
            "CREDIT_VERIFIED" => Verified,
            "CREDIT_UNVERIFIED" => Unverified,
            "CREDIT_PENDING_IDENTITY" => PendingIdentity,
            _ => Unverified
        };

    private static Guid CreateDeterministicId(
        Guid actorAccountId,
        Guid recordingId,
        string idempotencyKey,
        string kind)
    {
        var material =
            $"{actorAccountId:D}\nCATALOG.RECORDING_CREDIT.CREATE\n{recordingId:D}\n{idempotencyKey}\n{kind}";
        var digest = SHA256.HashData(
            Encoding.UTF8.GetBytes(material));

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

    private static async Task WriteAuditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorAccountId,
        Guid creditId,
        PreparedCredit prepared,
        string correlationId,
        CancellationToken cancellationToken)
    {
        var roleCode = await ReadAuditRoleCodeAsync(
            connection,
            transaction,
            actorAccountId,
            cancellationToken);
        var digest = SHA256.HashData(
            Encoding.UTF8.GetBytes(Fingerprint(prepared)));

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
                'RECORDING_CREDIT',
                @credit_id,
                'CATALOG.RECORDING_CREDIT.CREATE',
                NULL,
                @after_digest,
                @reason,
                CURRENT_TIMESTAMP,
                @correlation_id
            );
            """;

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("actor_id", NpgsqlDbType.Uuid, actorAccountId);
        command.Parameters.AddWithValue("role_code", roleCode);
        command.Parameters.AddWithValue("credit_id", NpgsqlDbType.Uuid, creditId);
        command.Parameters.AddWithValue("after_digest", NpgsqlDbType.Bytea, digest);
        command.Parameters.AddWithValue(
            "reason",
            prepared.VerificationCode == PendingIdentity
                ? "Crédito registrado con identidad explícitamente pendiente y procedencia trazable."
                : "Crédito registrado con identidad canónica, orden, procedencia y verificación.");
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

        await using var command =
            new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("actor_id", NpgsqlDbType.Uuid, actorAccountId);

        var value = await command.ExecuteScalarAsync(cancellationToken);
        if (value is not string roleCode
            || string.IsNullOrWhiteSpace(roleCode))
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.audit-role.missing",
                "No se pudo resolver la función editorial vigente para la auditoría.");
        }

        return roleCode;
    }

    private static string Fingerprint(
        PreparedCredit prepared) =>
        string.Join(
            "\n",
            prepared.ArtistId?.ToString("D") ?? string.Empty,
            prepared.DisplayName,
            prepared.RoleCode,
            prepared.DisplayOrder.ToString(
                System.Globalization.CultureInfo.InvariantCulture),
            prepared.SourceType,
            prepared.Citation,
            prepared.Locator ?? string.Empty,
            prepared.VerificationCode);

    private static Guid CorrelationGuid(string correlationId)
    {
        if (Guid.TryParse(correlationId, out var parsed)
            && parsed != Guid.Empty)
        {
            return parsed;
        }

        var digest = SHA256.HashData(
            Encoding.UTF8.GetBytes(correlationId));
        Span<byte> bytes = stackalloc byte[16];
        digest.AsSpan(0, 16).CopyTo(bytes);
        return new Guid(bytes);
    }

    private static void ValidateRecordingId(Guid recordingId)
    {
        if (recordingId == Guid.Empty)
        {
            throw new CreditProvenanceAdministrationException(
                "catalog.credit.recording.invalid",
                "La grabación indicada no es válida.");
        }
    }

    private sealed record PreparedCredit(
        Guid? ArtistId,
        string DisplayName,
        string RoleCode,
        int DisplayOrder,
        string SourceType,
        string Citation,
        string? Locator,
        string VerificationCode);
}
