using System.Security.Cryptography;
using System.Text;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using Npgsql;
using NpgsqlTypes;

namespace MusicaAprender.Modules.Learning.Infrastructure.Sessions;

public sealed record StudySessionSummary(
    Guid StudySessionId,
    string StatusCode,
    DateTimeOffset StartedAt,
    long Version);

public sealed record StudySessionStartContext(
    bool Eligible,
    string? BlockingReason,
    int EligibleExerciseCount,
    int? PublicationNo,
    StudySessionSummary? ActiveSession);

public sealed record StudySessionStartResult(
    Guid StudySessionId,
    string StatusCode,
    DateTimeOffset StartedAt,
    long Version,
    int PublicationNo,
    bool ReusedExisting);

public sealed class StudySessionPublicationUnavailableException : Exception
{
    public StudySessionPublicationUnavailableException()
        : base("La canción no tiene una publicación elegible para iniciar estudio.")
    {
    }
}

public sealed class StudySessionNoEligibleActivityException : Exception
{
    public StudySessionNoEligibleActivityException()
        : base("La publicación no contiene actividades de ejercicio elegibles.")
    {
    }
}

public sealed class StudySessionPublicationAmbiguousException : Exception
{
    public StudySessionPublicationAmbiguousException()
        : base("La canción coincide con más de una publicación elegible.")
    {
    }
}

public sealed class StudySessionIdempotencyConflictException : Exception
{
    public StudySessionIdempotencyConflictException()
        : base("La clave de idempotencia ya fue usada para una solicitud diferente.")
    {
    }
}

public sealed class StudySessionStartService(
    IRlsTransactionExecutor transactionExecutor)
{
    private const string OperationCode = "LEARNING.STUDY_SESSION.START";
    private const int MinimumIdempotencyKeyLength = 8;
    private const int MaximumIdempotencyKeyLength = 128;

    public Task<StudySessionStartContext> ReadStartContextAsync(
        DatabaseSessionContext context,
        string slugKey,
        string territoryCode,
        string? languageTag,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);

        var normalizedSlugKey = NormalizeSlugKey(slugKey);
        var normalizedTerritory = NormalizeCode(
            territoryCode,
            nameof(territoryCode));
        var normalizedLanguage = NormalizeLanguageTag(languageTag);

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                var publication = await ResolvePublicationAsync(
                    connection,
                    transaction,
                    normalizedSlugKey,
                    normalizedTerritory,
                    normalizedLanguage,
                    token);

                if (publication is null)
                {
                    return new StudySessionStartContext(
                        false,
                        "Esta canción no tiene una publicación vigente disponible para estudiar.",
                        0,
                        null,
                        null);
                }

                if (publication.EligibleExerciseCount == 0)
                {
                    return new StudySessionStartContext(
                        false,
                        "Todavía no hay una práctica publicada para esta canción. Los borradores editoriales no crean sesiones de estudiante.",
                        0,
                        publication.PublicationNo,
                        null);
                }

                var activeSession = await ReadActiveSessionAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    publication.PublicationId,
                    token);

                return new StudySessionStartContext(
                    true,
                    null,
                    publication.EligibleExerciseCount,
                    publication.PublicationNo,
                    activeSession);
            },
            cancellationToken);
    }

    public Task<StudySessionStartResult> StartAsync(
        DatabaseSessionContext context,
        string slugKey,
        string territoryCode,
        string? languageTag,
        string idempotencyKey,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);

        var normalizedSlugKey = NormalizeSlugKey(slugKey);
        var normalizedTerritory = NormalizeCode(
            territoryCode,
            nameof(territoryCode));
        var normalizedLanguage = NormalizeLanguageTag(languageTag);
        var normalizedIdempotencyKey = NormalizeIdempotencyKey(idempotencyKey);
        var requestDigest = BuildRequestDigest(
            context.AccountId,
            normalizedSlugKey,
            normalizedTerritory,
            normalizedLanguage);

        return transactionExecutor.ExecuteAsync(
            context,
            async (connection, transaction, token) =>
            {
                await AcquireStartLockAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    token);

                var prior = await ReadIdempotencyAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    normalizedIdempotencyKey,
                    token);

                if (prior is not null)
                {
                    if (!CryptographicOperations.FixedTimeEquals(
                            requestDigest,
                            prior.RequestDigest))
                    {
                        throw new StudySessionIdempotencyConflictException();
                    }

                    var replay = await ReadSessionByIdAsync(
                        connection,
                        transaction,
                        context.AccountId,
                        prior.StudySessionId,
                        token);

                    if (replay is null)
                    {
                        throw new InvalidOperationException(
                            "La confirmación idempotente apunta a una sesión inexistente.");
                    }

                    return replay with { ReusedExisting = true };
                }

                var publication = await ResolvePublicationAsync(
                    connection,
                    transaction,
                    normalizedSlugKey,
                    normalizedTerritory,
                    normalizedLanguage,
                    token)
                    ?? throw new StudySessionPublicationUnavailableException();

                if (publication.EligibleExerciseCount == 0)
                {
                    throw new StudySessionNoEligibleActivityException();
                }

                var learnerProfileId = await EnsureLearnerProfileAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    token);

                var existing = await ReadActiveSessionAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    publication.PublicationId,
                    token);

                StudySessionStartResult result;

                if (existing is not null)
                {
                    result = new StudySessionStartResult(
                        existing.StudySessionId,
                        existing.StatusCode,
                        existing.StartedAt,
                        existing.Version,
                        publication.PublicationNo,
                        true);
                }
                else
                {
                    result = await InsertSessionAsync(
                        connection,
                        transaction,
                        learnerProfileId,
                        publication,
                        token);
                }

                await WriteIdempotencyAsync(
                    connection,
                    transaction,
                    context.AccountId,
                    normalizedIdempotencyKey,
                    requestDigest,
                    result,
                    token);

                return result;
            },
            cancellationToken);
    }

    private static async Task AcquireStartLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT pg_advisory_xact_lock(
                hashtextextended(@lock_key, 0)
            );
            """;

        await using var command = new NpgsqlCommand(
            sql,
            connection,
            transaction);

        command.Parameters.AddWithValue(
            "lock_key",
            NpgsqlDbType.Text,
            $"{OperationCode}:{accountId:N}");

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<PublicationCandidate?> ResolvePublicationAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string slugKey,
        string territoryCode,
        string? languageTag,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                publication.publication_id,
                publication.recording_id,
                publication.publication_no,
                (
                    SELECT COUNT(DISTINCT exercise.exercise_revision_id)
                    FROM editorial.publication_component AS published
                    INNER JOIN editorial.package_component AS package_component
                        ON package_component.package_component_id =
                           published.source_component_id
                       AND package_component.package_id =
                           publication.package_id
                       AND package_component.component_kind = 'EXERCISE'
                       AND package_component.exercise_revision_id IS NOT NULL
                    INNER JOIN learning.exercise_revision AS exercise
                        ON exercise.exercise_revision_id =
                           package_component.exercise_revision_id
                    INNER JOIN learning.exercise_definition AS definition
                        ON definition.exercise_id = exercise.exercise_id
                       AND definition.recording_id =
                           publication.recording_id
                    WHERE published.publication_id =
                          publication.publication_id
                      AND published.component_kind = 'EXERCISE'
                      AND published.component_checksum =
                          package_component.checksum
                      AND (
                          definition.line_id IS NULL
                          OR EXISTS (
                              SELECT 1
                              FROM editorial.package_component AS lyrics_component
                              INNER JOIN content.lyric_section AS section
                                  ON section.lyrics_revision_id =
                                     lyrics_component.lyrics_revision_id
                              INNER JOIN content.lyric_line AS line
                                  ON line.section_id = section.section_id
                              WHERE lyrics_component.package_id =
                                    publication.package_id
                                AND lyrics_component.component_kind = 'LYRICS'
                                AND line.line_id = definition.line_id
                          )
                      )
                ) AS eligible_exercise_count
            FROM editorial.publication AS publication
            INNER JOIN editorial.editorial_package AS package
                ON package.package_id = publication.package_id
               AND package.recording_id = publication.recording_id
               AND package.status_code = 'APPROVED'
               AND package.frozen_at IS NOT NULL
            INNER JOIN editorial.published_package_projection AS projection
                ON projection.publication_id = publication.publication_id
               AND projection.recording_id = publication.recording_id
            WHERE substring(
                      md5(publication.recording_id::text || ':public-song-v1')
                      from 1 for 20
                  ) = @slug_key
              AND publication.status_code = 'ACTIVE'
              AND publication.active_from <= CURRENT_TIMESTAMP
              AND (
                  publication.active_to IS NULL
                  OR publication.active_to > CURRENT_TIMESTAMP
              )
              AND EXISTS (
                  SELECT 1
                  FROM editorial.publication_availability AS availability
                  WHERE availability.publication_id =
                        publication.publication_id
                    AND availability.territory_code = @territory_code
                    AND availability.audience_code = 'PUBLIC'
                    AND availability.status_code = 'ACTIVE'
                    AND availability.valid_from <= CURRENT_TIMESTAMP
                    AND (
                        availability.valid_to IS NULL
                        OR availability.valid_to > CURRENT_TIMESTAMP
                    )
                    AND (
                        (
                            @language_tag IS NULL
                            AND availability.language_tag IS NULL
                        )
                        OR (
                            @language_tag IS NOT NULL
                            AND (
                                availability.language_tag IS NULL
                                OR lower(availability.language_tag) =
                                   lower(@language_tag)
                            )
                        )
                    )
              )
              AND EXISTS (
                  SELECT 1
                  FROM catalog.recording_source AS source
                  WHERE source.recording_id = publication.recording_id
                    AND source.provider_code = 'YOUTUBE'
                    AND source.status_code IN ('ACTIVE', 'PUBLISHED')
                    AND source.external_ref ~ '^[A-Za-z0-9_-]{11}$'
              )
            ORDER BY
                publication.active_from DESC,
                publication.publication_no DESC
            LIMIT 2;
            """;

        await using var command = new NpgsqlCommand(
            sql,
            connection,
            transaction);

        command.Parameters.AddWithValue(
            "slug_key",
            NpgsqlDbType.Varchar,
            slugKey);
        command.Parameters.AddWithValue(
            "territory_code",
            NpgsqlDbType.Varchar,
            territoryCode);
        command.Parameters.Add(
            new NpgsqlParameter("language_tag", NpgsqlDbType.Varchar)
            {
                Value = languageTag is null ? DBNull.Value : languageTag
            });

        var rows = new List<PublicationCandidate>(2);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(
                new PublicationCandidate(
                    reader.GetGuid(0),
                    reader.GetGuid(1),
                    reader.GetInt32(2),
                    checked((int)reader.GetInt64(3))));
        }

        return rows.Count switch
        {
            0 => null,
            1 => rows[0],
            _ => throw new StudySessionPublicationAmbiguousException()
        };
    }

    private static async Task<Guid> EnsureLearnerProfileAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        const string readSql = """
            SELECT learner_profile_id
            FROM learning.learner_profile
            WHERE account_id = @account_id
            ORDER BY created_at, learner_profile_id
            LIMIT 2;
            """;

        var profileIds = new List<Guid>(2);

        await using (var command = new NpgsqlCommand(
            readSql,
            connection,
            transaction))
        {
            command.Parameters.AddWithValue(
                "account_id",
                NpgsqlDbType.Uuid,
                accountId);

            await using var reader =
                await command.ExecuteReaderAsync(cancellationToken);

            while (await reader.ReadAsync(cancellationToken))
            {
                profileIds.Add(reader.GetGuid(0));
            }
        }

        if (profileIds.Count > 1)
        {
            throw new InvalidOperationException(
                "La cuenta tiene más de un learner_profile y viola la cardinalidad 1:1.");
        }

        if (profileIds.Count == 1)
        {
            return profileIds[0];
        }

        var learnerProfileId = Guid.CreateVersion7();

        const string insertSql = """
            INSERT INTO learning.learner_profile (
                learner_profile_id,
                account_id,
                level_code,
                created_at,
                version
            )
            VALUES (
                @learner_profile_id,
                @account_id,
                NULL,
                CURRENT_TIMESTAMP,
                1
            );
            """;

        await using var insert = new NpgsqlCommand(
            insertSql,
            connection,
            transaction);

        insert.Parameters.AddWithValue(
            "learner_profile_id",
            NpgsqlDbType.Uuid,
            learnerProfileId);
        insert.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);

        if (await insert.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new InvalidOperationException(
                "No se pudo crear el perfil privado de aprendizaje.");
        }

        return learnerProfileId;
    }

    private static async Task<StudySessionSummary?> ReadActiveSessionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid publicationId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                session.study_session_id,
                session.status_code,
                session.started_at,
                session.version
            FROM learning.study_session AS session
            INNER JOIN learning.learner_profile AS profile
                ON profile.learner_profile_id =
                   session.learner_profile_id
            WHERE profile.account_id = @account_id
              AND session.publication_id = @publication_id
              AND session.status_code IN ('ACTIVE', 'PAUSED')
              AND session.ended_at IS NULL
            ORDER BY session.started_at DESC, session.study_session_id
            LIMIT 2;
            """;

        var rows = new List<StudySessionSummary>(2);

        await using var command = new NpgsqlCommand(
            sql,
            connection,
            transaction);

        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);
        command.Parameters.AddWithValue(
            "publication_id",
            NpgsqlDbType.Uuid,
            publicationId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(
                new StudySessionSummary(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    ToUtcOffset(reader.GetDateTime(2)),
                    reader.GetInt64(3)));
        }

        return rows.Count switch
        {
            0 => null,
            1 => rows[0],
            _ => throw new InvalidOperationException(
                "Existen varias sesiones activas para la misma publicación.")
        };
    }

    private static async Task<StudySessionStartResult?> ReadSessionByIdAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        Guid studySessionId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                session.study_session_id,
                session.status_code,
                session.started_at,
                session.version,
                publication.publication_no
            FROM learning.study_session AS session
            INNER JOIN learning.learner_profile AS profile
                ON profile.learner_profile_id =
                   session.learner_profile_id
            INNER JOIN editorial.publication AS publication
                ON publication.publication_id =
                   session.publication_id
            WHERE session.study_session_id = @study_session_id
              AND profile.account_id = @account_id;
            """;

        await using var command = new NpgsqlCommand(
            sql,
            connection,
            transaction);

        command.Parameters.AddWithValue(
            "study_session_id",
            NpgsqlDbType.Uuid,
            studySessionId);
        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new StudySessionStartResult(
            reader.GetGuid(0),
            reader.GetString(1),
            ToUtcOffset(reader.GetDateTime(2)),
            reader.GetInt64(3),
            reader.GetInt32(4),
            true);
    }

    private static async Task<StudySessionStartResult> InsertSessionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid learnerProfileId,
        PublicationCandidate publication,
        CancellationToken cancellationToken)
    {
        var studySessionId = Guid.CreateVersion7();

        const string sql = """
            INSERT INTO learning.study_session (
                study_session_id,
                learner_profile_id,
                recording_id,
                publication_id,
                status_code,
                started_at,
                ended_at,
                version
            )
            VALUES (
                @study_session_id,
                @learner_profile_id,
                @recording_id,
                @publication_id,
                'ACTIVE',
                CURRENT_TIMESTAMP,
                NULL,
                1
            )
            RETURNING started_at, version;
            """;

        await using var command = new NpgsqlCommand(
            sql,
            connection,
            transaction);

        command.Parameters.AddWithValue(
            "study_session_id",
            NpgsqlDbType.Uuid,
            studySessionId);
        command.Parameters.AddWithValue(
            "learner_profile_id",
            NpgsqlDbType.Uuid,
            learnerProfileId);
        command.Parameters.AddWithValue(
            "recording_id",
            NpgsqlDbType.Uuid,
            publication.RecordingId);
        command.Parameters.AddWithValue(
            "publication_id",
            NpgsqlDbType.Uuid,
            publication.PublicationId);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "No se confirmó la creación de la sesión de estudio.");
        }

        return new StudySessionStartResult(
            studySessionId,
            "ACTIVE",
            ToUtcOffset(reader.GetDateTime(0)),
            reader.GetInt64(1),
            publication.PublicationNo,
            false);
    }

    private static async Task<IdempotencyRecord?> ReadIdempotencyAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        string idempotencyKey,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                request_digest,
                NULLIF(response_ref ->> 'studySessionId', '')::uuid,
                expires_at
            FROM ops.idempotency_record
            WHERE account_id = @account_id
              AND operation_code = @operation_code
              AND idempotency_key = @idempotency_key;
            """;

        await using var command = new NpgsqlCommand(
            sql,
            connection,
            transaction);

        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);
        command.Parameters.AddWithValue(
            "operation_code",
            NpgsqlDbType.Varchar,
            OperationCode);
        command.Parameters.AddWithValue(
            "idempotency_key",
            NpgsqlDbType.Text,
            idempotencyKey);

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        var expiresAt = ToUtcOffset(reader.GetDateTime(2));
        if (expiresAt <= DateTimeOffset.UtcNow || reader.IsDBNull(1))
        {
            return null;
        }

        return new IdempotencyRecord(
            reader.GetFieldValue<byte[]>(0),
            reader.GetGuid(1));
    }

    private static async Task WriteIdempotencyAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid accountId,
        string idempotencyKey,
        byte[] requestDigest,
        StudySessionStartResult result,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO ops.idempotency_record (
                idempotency_id,
                account_id,
                operation_code,
                idempotency_key,
                request_digest,
                response_code,
                response_ref,
                created_at,
                expires_at
            )
            VALUES (
                uuidv7(),
                @account_id,
                @operation_code,
                @idempotency_key,
                @request_digest,
                @response_code,
                jsonb_build_object(
                    'studySessionId',
                    CAST(@study_session_id AS text)
                ),
                CURRENT_TIMESTAMP,
                CURRENT_TIMESTAMP + interval '24 hours'
            )
            ON CONFLICT (
                account_id,
                operation_code,
                idempotency_key
            )
            DO UPDATE SET
                request_digest = EXCLUDED.request_digest,
                response_code = EXCLUDED.response_code,
                response_ref = EXCLUDED.response_ref,
                created_at = CURRENT_TIMESTAMP,
                expires_at = EXCLUDED.expires_at
            WHERE ops.idempotency_record.expires_at <= CURRENT_TIMESTAMP;
            """;

        await using var command = new NpgsqlCommand(
            sql,
            connection,
            transaction);

        command.Parameters.AddWithValue(
            "account_id",
            NpgsqlDbType.Uuid,
            accountId);
        command.Parameters.AddWithValue(
            "operation_code",
            NpgsqlDbType.Varchar,
            OperationCode);
        command.Parameters.AddWithValue(
            "idempotency_key",
            NpgsqlDbType.Text,
            idempotencyKey);
        command.Parameters.AddWithValue(
            "request_digest",
            NpgsqlDbType.Bytea,
            requestDigest);
        command.Parameters.AddWithValue(
            "response_code",
            NpgsqlDbType.Integer,
            result.ReusedExisting ? 200 : 201);
        command.Parameters.AddWithValue(
            "study_session_id",
            NpgsqlDbType.Uuid,
            result.StudySessionId);

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            var existing = await ReadIdempotencyAsync(
                connection,
                transaction,
                accountId,
                idempotencyKey,
                cancellationToken);

            if (existing is null
                || !CryptographicOperations.FixedTimeEquals(
                    requestDigest,
                    existing.RequestDigest))
            {
                throw new StudySessionIdempotencyConflictException();
            }
        }
    }

    private static byte[] BuildRequestDigest(
        Guid accountId,
        string slugKey,
        string territoryCode,
        string? languageTag)
    {
        var canonical = string.Join(
            '|',
            OperationCode,
            accountId.ToString("N"),
            slugKey,
            territoryCode,
            languageTag ?? "-");

        return SHA256.HashData(Encoding.UTF8.GetBytes(canonical));
    }

    private static string NormalizeIdempotencyKey(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);

        var normalized = value.Trim();
        if (normalized.Length is < MinimumIdempotencyKeyLength
            or > MaximumIdempotencyKeyLength
            || normalized.Any(char.IsControl))
        {
            throw new ArgumentException(
                $"Idempotency-Key debe tener entre {MinimumIdempotencyKeyLength} y {MaximumIdempotencyKeyLength} caracteres sin controles.",
                nameof(value));
        }

        return normalized;
    }

    private static string NormalizeSlugKey(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);

        var normalized = value.Trim().ToLowerInvariant();
        if (normalized.Length != 20
            || normalized.Any(static character =>
                character is not (>= '0' and <= '9')
                && character is not (>= 'a' and <= 'f')))
        {
            throw new ArgumentException(
                "La clave pública de canción es inválida.",
                nameof(value));
        }

        return normalized;
    }

    private static string NormalizeCode(
        string value,
        string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(
            value,
            parameterName);

        var normalized = value.Trim().ToUpperInvariant();
        if (normalized.Length is < 1 or > 64
            || !IsUpperCodeCharacter(normalized[0], first: true)
            || normalized.Skip(1).Any(static character =>
                !IsUpperCodeCharacter(character, first: false)))
        {
            throw new ArgumentException(
                "El código debe usar formato [A-Z0-9][A-Z0-9._-]*.",
                parameterName);
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
        if (normalized.Length > 35
            || normalized.Any(static character =>
                !(char.IsAsciiLetterOrDigit(character)
                  || character == '-')))
        {
            throw new ArgumentException(
                "La etiqueta de idioma es inválida.",
                nameof(value));
        }

        return normalized;
    }

    private static bool IsUpperCodeCharacter(
        char character,
        bool first)
    {
        var alphanumeric =
            character is >= 'A' and <= 'Z'
            || character is >= '0' and <= '9';

        return alphanumeric
            || (!first && character is '.' or '_' or '-');
    }

    private static DateTimeOffset ToUtcOffset(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private sealed record PublicationCandidate(
        Guid PublicationId,
        Guid RecordingId,
        int PublicationNo,
        int EligibleExerciseCount);

    private sealed record IdempotencyRecord(
        byte[] RequestDigest,
        Guid StudySessionId);
}
