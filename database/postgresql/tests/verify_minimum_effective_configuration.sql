\set ON_ERROR_STOP on

DO $verification$
BEGIN
    IF EXISTS (
        WITH expected(catalog_code, safe_entry_code) AS (
            VALUES
                ('ACCOUNT_STATUS', 'DISABLED'),
                ('REVISION_STATUS', 'DRAFT'),
                ('PUBLICATION_STATUS', 'WITHDRAWN'),
                ('PACKAGE_STATUS', 'DRAFT'),
                ('SESSION_STATUS', 'PAUSED'),
                ('INSTANCE_STATUS', 'CREATED'),
                ('JOB_STATUS', 'NEEDS_REVIEW'),
                ('PRIVACY_STATUS', 'RECEIVED'),
                ('LANGUAGE', 'ES'),
                ('PROVIDER', 'YOUTUBE'),
                ('JLPT_LEVEL', 'N5'),
                ('DATA_CLASS', 'RESTRICTED')
        )
        SELECT 1
        FROM expected x
        WHERE (
            SELECT count(*)
            FROM configuration.catalog_definition d
            JOIN configuration.catalog_entry e
              ON e.catalog_definition_id = d.catalog_definition_id
            WHERE d.catalog_code = x.catalog_code
              AND d.status_code = 'ACTIVE'
              AND d.version > 0
              AND e.entry_code = x.safe_entry_code
              AND e.status_code = 'ACTIVE'
              AND e.version > 0
              AND e.labels ? 'es'
              AND e.valid_from <= CURRENT_TIMESTAMP
              AND (e.valid_to IS NULL OR e.valid_to > CURRENT_TIMESTAMP)
        ) <> 1
    ) THEN
        RAISE EXCEPTION 'BL-MVP-035: falta un catalogo vigente o su sustituto seguro.';
    END IF;

    IF (
        SELECT count(*)
        FROM configuration.catalog_definition d
        JOIN configuration.catalog_entry e
          ON e.catalog_definition_id = d.catalog_definition_id
        WHERE d.catalog_code IN (
            'ACCOUNT_STATUS', 'REVISION_STATUS', 'PUBLICATION_STATUS',
            'PACKAGE_STATUS', 'SESSION_STATUS', 'INSTANCE_STATUS',
            'JOB_STATUS', 'PRIVACY_STATUS', 'LANGUAGE', 'PROVIDER',
            'JLPT_LEVEL', 'DATA_CLASS'
        )
          AND d.status_code = 'ACTIVE'
          AND d.version > 0
          AND e.status_code = 'ACTIVE'
          AND e.version > 0
          AND e.labels ? 'es'
          AND e.valid_from <= CURRENT_TIMESTAMP
          AND (e.valid_to IS NULL OR e.valid_to > CURRENT_TIMESTAMP)
    ) < 59 THEN
        RAISE EXCEPTION 'BL-MVP-035: no estan vigentes las 59 entradas catalogadas minimas.';
    END IF;

    IF EXISTS (
        WITH expected(parameter_key, safe_value, expected_json_type) AS (
            VALUES
                ('PLAYER_SYNC_TOLERANCE_MS', '120'::jsonb, 'number'),
                ('SESSION_IDLE_MINUTES', '30'::jsonb, 'number'),
                ('SESSION_ABSOLUTE_HOURS', '24'::jsonb, 'number'),
                ('EDITORIAL_LOCK_SECONDS', '300'::jsonb, 'number'),
                ('IDEMPOTENCY_RETENTION_HOURS', '24'::jsonb, 'number'),
                ('MAX_JOB_ATTEMPTS', '8'::jsonb, 'number'),
                ('SEARCH_MIN_QUERY_LENGTH', '2'::jsonb, 'number'),
                ('MFA_REQUIRED_PRIVILEGED', 'true'::jsonb, 'boolean'),
                ('PUBLICATION_DEFAULT_LANGUAGE', '"es"'::jsonb, 'string'),
                ('JOB_ATTEMPT_RETENTION_DAYS', '90'::jsonb, 'number')
        )
        SELECT 1
        FROM expected x
        WHERE (
            SELECT count(*)
            FROM configuration.parameter_definition d
            JOIN configuration.parameter_version v
              ON v.parameter_definition_id = d.parameter_definition_id
            JOIN configuration.effective_parameter e
              ON e.parameter_version_id = v.parameter_version_id
             AND e.parameter_key = d.parameter_key
            WHERE d.parameter_key = x.parameter_key
              AND d.status_code = 'ACTIVE'
              AND d.default_value = x.safe_value
              AND jsonb_typeof(d.default_value) = x.expected_json_type
              AND v.status_code = 'ACTIVE'
              AND v.version_no > 0
              AND v.scope_code = 'GLOBAL'
              AND v.scope_value IS NULL
              AND jsonb_typeof(v.typed_value) = x.expected_json_type
              AND v.valid_from <= CURRENT_TIMESTAMP
              AND (v.valid_to IS NULL OR v.valid_to > CURRENT_TIMESTAMP)
              AND octet_length(v.checksum) BETWEEN 16 AND 128
              AND e.scope_code = v.scope_code
              AND e.scope_value IS NOT DISTINCT FROM v.scope_value
              AND e.typed_value = v.typed_value
              AND e.effective_from <= CURRENT_TIMESTAMP
              AND e.projection_version > 0
        ) <> 1
    ) THEN
        RAISE EXCEPTION 'BL-MVP-035: falta un parametro efectivo, tipado, versionado o con sustituto seguro.';
    END IF;

    IF EXISTS (
        WITH expected(role_code) AS (
            VALUES ('STUDENT'), ('EDITOR'), ('REVIEWER'), ('ADMIN')
        )
        SELECT 1
        FROM expected x
        WHERE (
            SELECT count(*)
            FROM security.role r
            WHERE r.role_code = x.role_code
              AND r.status_code = 'ACTIVE'
              AND r.version > 0
        ) <> 1
    ) THEN
        RAISE EXCEPTION 'BL-MVP-035: falta un rol activo y versionado; STUDENT es el sustituto seguro.';
    END IF;

    IF EXISTS (
        WITH expected(data_class, purpose_code, retention_days, trigger_code) AS (
            VALUES
                ('INTERNAL', 'JOB_ATTEMPT', 90, 'FINISHED_AT'),
                ('RESTRICTED', 'SECURITY_EVENT', 365, 'OCCURRED_AT'),
                ('RESTRICTED', 'SECURITY_TOKEN', 7, 'EXPIRES_AT')
        )
        SELECT 1
        FROM expected x
        WHERE (
            SELECT count(*)
            FROM configuration.retention_policy p
            WHERE p.data_class = x.data_class
              AND p.purpose_code = x.purpose_code
              AND p.retention_days = x.retention_days
              AND p.trigger_code = x.trigger_code
              AND p.valid_from <= CURRENT_TIMESTAMP
              AND p.version > 0
        ) <> 1
    ) THEN
        RAISE EXCEPTION 'BL-MVP-035: falta una politica minima versionada o su valor seguro.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM configuration.parameter_definition d
        WHERE upper(d.parameter_key) ~ '(^|[._-])(PASSWORD|SECRET|CREDENTIAL|PRIVATE_KEY|ACCESS_KEY)([._-]|$)'
    ) THEN
        RAISE EXCEPTION 'BL-MVP-035: M19 contiene una clave con apariencia de secreto.';
    END IF;
END
$verification$;

SELECT
    'OK: BL-MVP-035 catalogos, parametros, roles, politicas, vigencia y sustitutos seguros verificados como '
    || current_user || '.' AS result;
