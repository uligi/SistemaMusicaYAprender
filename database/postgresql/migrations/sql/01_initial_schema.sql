-- PostgreSQL 18 - esquema físico inicial del MVP
-- Requiere ejecutar 00_bootstrap_roles_extensions.sql una vez por base.
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '15min';
SET LOCAL ROLE jp_owner;

-- 1. Esquemas propietarios
CREATE SCHEMA IF NOT EXISTS identity AUTHORIZATION jp_owner;
CREATE SCHEMA IF NOT EXISTS security AUTHORIZATION jp_owner;
CREATE SCHEMA IF NOT EXISTS catalog AUTHORIZATION jp_owner;
CREATE SCHEMA IF NOT EXISTS content AUTHORIZATION jp_owner;
CREATE SCHEMA IF NOT EXISTS learning AUTHORIZATION jp_owner;
CREATE SCHEMA IF NOT EXISTS progress AUTHORIZATION jp_owner;
CREATE SCHEMA IF NOT EXISTS editorial AUTHORIZATION jp_owner;
CREATE SCHEMA IF NOT EXISTS configuration AUTHORIZATION jp_owner;
CREATE SCHEMA IF NOT EXISTS ops AUTHORIZATION jp_owner;

-- 2. Funciones compartidas de integridad
CREATE OR REPLACE FUNCTION ops.bump_version()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $fn$
BEGIN
    NEW.version := OLD.version + 1;
    RETURN NEW;
END;
$fn$;

CREATE OR REPLACE FUNCTION ops.prevent_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $fn$
BEGIN
    IF current_setting('app.maintenance_mode', true) = 'on' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    RAISE EXCEPTION 'La tabla %.% es append-only', TG_TABLE_SCHEMA, TG_TABLE_NAME
        USING ERRCODE = '55000';
END;
$fn$;

CREATE OR REPLACE FUNCTION ops.guard_terminal_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $fn$
BEGIN
    IF current_setting('app.maintenance_mode', true) = 'on' THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'No se permite eliminar una revisión o agregado versionado %.%.',
            TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = '55000';
    END IF;
    IF OLD.status_code IN ('PUBLISHED','SUPERSEDED','WITHDRAWN','REJECTED') THEN
        RAISE EXCEPTION 'No se puede modificar un objeto terminal %.% (%).',
            TG_TABLE_SCHEMA, TG_TABLE_NAME, OLD.status_code USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$fn$;

CREATE OR REPLACE FUNCTION ops.guard_evidence_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $fn$
BEGIN
    IF current_setting('app.maintenance_mode', true) = 'on' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'learning_evidence no se elimina; se corrige por reemplazo.' USING ERRCODE = '55000';
    END IF;
    IF OLD.superseded_by IS NULL
       AND NEW.superseded_by IS NOT NULL
       AND (to_jsonb(NEW) - 'superseded_by') = (to_jsonb(OLD) - 'superseded_by') THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'learning_evidence solo permite enlazar superseded_by una vez.' USING ERRCODE = '55000';
END;
$fn$;

CREATE OR REPLACE FUNCTION editorial.guard_package_component_mutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $fn$
DECLARE
    v_package_id uuid;
    v_status varchar(64);
BEGIN
    IF current_setting('app.maintenance_mode', true) = 'on' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    v_package_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.package_id ELSE NEW.package_id END;
    SELECT p.status_code INTO v_status
    FROM editorial.editorial_package p
    WHERE p.package_id = v_package_id;
    IF v_status IS DISTINCT FROM 'DRAFT' THEN
        RAISE EXCEPTION 'Los componentes solo se modifican mientras el paquete está en DRAFT.'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$fn$;

CREATE OR REPLACE FUNCTION security.current_account_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $fn$
    SELECT nullif(current_setting('app.account_id', true), '')::uuid
$fn$;

-- 3. Tablas físicas (109)

-- Esquema identity
CREATE TABLE identity.user_profile (
    account_id uuid NOT NULL,
    display_name text,
    ui_language varchar(35) NOT NULL,
    time_zone varchar(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_identity_user_profile PRIMARY KEY (account_id),
    CONSTRAINT ck_identity_user_profile_ui_language_1 CHECK (ui_language ~ '^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$'),
    CONSTRAINT ck_identity_user_profile_time_zone_1 CHECK (length(time_zone) BETWEEN 1 AND 64),
    CONSTRAINT ck_identity_user_profile_version_1 CHECK (version > 0)
);
COMMENT ON TABLE identity.user_profile IS 'Perfil de producto separado de la identidad de seguridad.';

CREATE TABLE identity.preference_set (
    preference_set_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid NOT NULL,
    current_revision_id uuid NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_identity_preference_set PRIMARY KEY (preference_set_id),
    CONSTRAINT ck_identity_preference_set_version_1 CHECK (version > 0)
);
COMMENT ON TABLE identity.preference_set IS 'Cabeza estable de las preferencias confirmadas del usuario.';

CREATE TABLE identity.preference_revision (
    revision_id uuid NOT NULL DEFAULT uuidv7(),
    preference_set_id uuid NOT NULL,
    revision_no integer NOT NULL,
    values jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by uuid NOT NULL,
    CONSTRAINT pk_identity_preference_revision PRIMARY KEY (revision_id),
    CONSTRAINT ck_identity_preference_revision_revision_no_1 CHECK (revision_no > 0)
);
COMMENT ON TABLE identity.preference_revision IS 'Historial versionado de idioma, ayudas, accesibilidad y privacidad.';

CREATE TABLE identity.consent_record (
    consent_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid NOT NULL,
    purpose_code varchar(64) NOT NULL,
    notice_version text NOT NULL,
    decision boolean NOT NULL,
    decided_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_identity_consent_record PRIMARY KEY (consent_id),
    CONSTRAINT ck_identity_consent_record_purpose_code_1 CHECK (purpose_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_identity_consent_record_notice_version_1 CHECK (length(notice_version) > 0)
);
COMMENT ON TABLE identity.consent_record IS 'Evidencia de aceptación o retiro de una finalidad y versión legal.';

CREATE TABLE identity.privacy_request (
    request_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid NOT NULL,
    request_type varchar(64) NOT NULL,
    status_code varchar(64) NOT NULL,
    requested_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    due_at timestamptz,
    closed_at timestamptz,
    CONSTRAINT pk_identity_privacy_request PRIMARY KEY (request_id),
    CONSTRAINT ck_identity_privacy_request_request_type_1 CHECK (request_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_identity_privacy_request_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE identity.privacy_request IS 'Solicitud verificable de acceso, portabilidad, rectificación o eliminación.';


-- Esquema security
CREATE TABLE security.account (
    account_id uuid NOT NULL DEFAULT uuidv7(),
    email_lookup_hash bytea NOT NULL,
    email_cipher bytea NOT NULL,
    status_code varchar(64) NOT NULL,
    verified_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_security_account PRIMARY KEY (account_id),
    CONSTRAINT ck_security_account_email_lookup_hash_1 CHECK (octet_length(email_lookup_hash) = 32),
    CONSTRAINT ck_security_account_email_cipher_1 CHECK (octet_length(email_cipher) >= 16),
    CONSTRAINT ck_security_account_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_account_version_1 CHECK (version > 0)
);
COMMENT ON TABLE security.account IS 'Identidad local autenticable y estado de acceso.';

CREATE TABLE security.credential (
    credential_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid NOT NULL,
    hash text NOT NULL,
    algorithm varchar(64) NOT NULL,
    parameters text NOT NULL,
    changed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    active boolean NOT NULL DEFAULT true,
    CONSTRAINT pk_security_credential PRIMARY KEY (credential_id),
    CONSTRAINT ck_security_credential_algorithm_1 CHECK (algorithm ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_credential_parameters_1 CHECK (length(parameters) > 0)
);
COMMENT ON TABLE security.credential IS 'Derivado no reversible de la credencial de una cuenta.';

CREATE TABLE security.account_verification (
    verification_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid NOT NULL,
    token_hash bytea NOT NULL,
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_security_account_verification PRIMARY KEY (verification_id),
    CONSTRAINT ck_security_account_verification_token_hash_1 CHECK (octet_length(token_hash) BETWEEN 16 AND 128),
    CONSTRAINT ck_security_account_verification_table_1 CHECK (expires_at > created_at),
    CONSTRAINT ck_security_account_verification_table_2 CHECK (consumed_at IS NULL OR consumed_at >= created_at)
);
COMMENT ON TABLE security.account_verification IS 'Token de verificación de correo almacenado como hash.';

CREATE TABLE security.recovery_token (
    recovery_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid NOT NULL,
    token_hash bytea NOT NULL,
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz,
    revoked_at timestamptz,
    CONSTRAINT pk_security_recovery_token PRIMARY KEY (recovery_id),
    CONSTRAINT ck_security_recovery_token_token_hash_1 CHECK (octet_length(token_hash) BETWEEN 16 AND 128),
    CONSTRAINT ck_security_recovery_token_table_1 CHECK (consumed_at IS NULL OR consumed_at <= expires_at),
    CONSTRAINT ck_security_recovery_token_table_2 CHECK (revoked_at IS NULL OR revoked_at <= expires_at)
);
COMMENT ON TABLE security.recovery_token IS 'Recuperación de cuenta segura, breve y revocable.';

CREATE TABLE security.session (
    session_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid NOT NULL,
    session_hash bytea NOT NULL,
    assurance_level varchar(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    idle_expires_at timestamptz NOT NULL,
    absolute_expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    CONSTRAINT pk_security_session PRIMARY KEY (session_id),
    CONSTRAINT ck_security_session_session_hash_1 CHECK (octet_length(session_hash) BETWEEN 16 AND 128),
    CONSTRAINT ck_security_session_assurance_level_1 CHECK (assurance_level ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_session_table_1 CHECK (idle_expires_at > created_at),
    CONSTRAINT ck_security_session_table_2 CHECK (absolute_expires_at >= idle_expires_at),
    CONSTRAINT ck_security_session_table_3 CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
COMMENT ON TABLE security.session IS 'Sesión revocable del navegador o actor privilegiado.';

CREATE TABLE security.mfa_method (
    mfa_method_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid NOT NULL,
    method_type varchar(64) NOT NULL,
    secret_ref varchar(512) NOT NULL,
    enrolled_at timestamptz NOT NULL,
    disabled_at timestamptz,
    CONSTRAINT pk_security_mfa_method PRIMARY KEY (mfa_method_id),
    CONSTRAINT ck_security_mfa_method_method_type_1 CHECK (method_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_mfa_method_secret_ref_1 CHECK (length(secret_ref) > 0)
);
COMMENT ON TABLE security.mfa_method IS 'Autenticador adicional de un actor privilegiado.';

CREATE TABLE security.role (
    role_id uuid NOT NULL DEFAULT uuidv7(),
    role_code varchar(64) NOT NULL,
    name text NOT NULL,
    status_code varchar(64) NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_security_role PRIMARY KEY (role_id),
    CONSTRAINT ck_security_role_role_code_1 CHECK (role_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_role_name_1 CHECK (length(name) > 0),
    CONSTRAINT ck_security_role_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_role_version_1 CHECK (version > 0)
);
COMMENT ON TABLE security.role IS 'Rol versionado que agrupa permisos.';

CREATE TABLE security.permission (
    permission_id uuid NOT NULL DEFAULT uuidv7(),
    permission_code varchar(64) NOT NULL,
    resource_code varchar(64) NOT NULL,
    action_code varchar(64) NOT NULL,
    description text NOT NULL,
    CONSTRAINT pk_security_permission PRIMARY KEY (permission_id),
    CONSTRAINT ck_security_permission_permission_code_1 CHECK (permission_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_permission_resource_code_1 CHECK (resource_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_permission_action_code_1 CHECK (action_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_permission_description_1 CHECK (length(description) > 0)
);
COMMENT ON TABLE security.permission IS 'Acción estable autorizable por servidor.';

CREATE TABLE security.role_permission (
    role_id uuid NOT NULL,
    permission_id uuid NOT NULL,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    granted_by uuid NOT NULL,
    CONSTRAINT pk_security_role_permission PRIMARY KEY (role_id, permission_id, valid_from),
    CONSTRAINT ck_security_role_permission_table_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
);
COMMENT ON TABLE security.role_permission IS 'Vincula rol y permiso con vigencia.';

CREATE TABLE security.access_scope (
    scope_id uuid NOT NULL DEFAULT uuidv7(),
    scope_type varchar(64) NOT NULL,
    module_code varchar(64),
    object_id uuid,
    definition jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT pk_security_access_scope PRIMARY KEY (scope_id),
    CONSTRAINT ck_security_access_scope_scope_type_1 CHECK (scope_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_access_scope_module_code_1 CHECK (module_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE security.access_scope IS 'Ámbito explícito para permisos restringidos por objeto o módulo.';

CREATE TABLE security.role_assignment (
    assignment_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid NOT NULL,
    role_id uuid NOT NULL,
    scope_id uuid,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    reason text NOT NULL,
    CONSTRAINT pk_security_role_assignment PRIMARY KEY (assignment_id),
    CONSTRAINT ck_security_role_assignment_reason_1 CHECK (length(reason) > 0),
    CONSTRAINT ck_security_role_assignment_table_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
);
COMMENT ON TABLE security.role_assignment IS 'Asignación temporal de rol y alcance a una cuenta.';

CREATE TABLE security.security_event (
    event_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid,
    event_type varchar(64) NOT NULL,
    result_code varchar(64) NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    correlation_id uuid NOT NULL,
    client_fingerprint bytea,
    CONSTRAINT pk_security_security_event PRIMARY KEY (event_id),
    CONSTRAINT ck_security_security_event_event_type_1 CHECK (event_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_security_event_result_code_1 CHECK (result_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE security.security_event IS 'Evento de autenticación, abuso, sesión o privilegio.';

CREATE TABLE security.audit_event (
    audit_id uuid NOT NULL DEFAULT uuidv7(),
    actor_id uuid,
    role_code varchar(64) NOT NULL,
    object_type varchar(64) NOT NULL,
    object_id uuid NOT NULL,
    action_code varchar(64) NOT NULL,
    before_digest bytea,
    after_digest bytea,
    reason text,
    occurred_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    correlation_id uuid NOT NULL,
    CONSTRAINT pk_security_audit_event PRIMARY KEY (audit_id),
    CONSTRAINT ck_security_audit_event_role_code_1 CHECK (role_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_audit_event_object_type_1 CHECK (object_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_audit_event_action_code_1 CHECK (action_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_security_audit_event_before_digest_1 CHECK (octet_length(before_digest) BETWEEN 16 AND 128),
    CONSTRAINT ck_security_audit_event_after_digest_1 CHECK (octet_length(after_digest) BETWEEN 16 AND 128)
);
COMMENT ON TABLE security.audit_event IS 'Evidencia transversal de acciones privilegiadas y decisiones críticas.';

CREATE TABLE security.audit_seal (
    seal_id uuid NOT NULL DEFAULT uuidv7(),
    range_start timestamptz NOT NULL,
    range_end timestamptz NOT NULL,
    event_count integer NOT NULL,
    root_hash bytea NOT NULL,
    sealed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    object_id uuid,
    CONSTRAINT pk_security_audit_seal PRIMARY KEY (seal_id),
    CONSTRAINT ck_security_audit_seal_event_count_1 CHECK (event_count > 0),
    CONSTRAINT ck_security_audit_seal_root_hash_1 CHECK (octet_length(root_hash) BETWEEN 16 AND 128),
    CONSTRAINT ck_security_audit_seal_table_1 CHECK (range_end > range_start),
    CONSTRAINT ck_security_audit_seal_table_2 CHECK (sealed_at >= range_end),
    CONSTRAINT ck_security_audit_seal_table_3 CHECK (event_count > 0)
);
COMMENT ON TABLE security.audit_seal IS 'Sello por lote para detectar alteración del historial.';


-- Esquema catalog
CREATE TABLE catalog.artist (
    artist_id uuid NOT NULL DEFAULT uuidv7(),
    canonical_name text NOT NULL,
    sort_name text NOT NULL,
    artist_type varchar(64) NOT NULL,
    status_code varchar(64) NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_catalog_artist PRIMARY KEY (artist_id),
    CONSTRAINT ck_catalog_artist_canonical_name_1 CHECK (length(canonical_name) > 0),
    CONSTRAINT ck_catalog_artist_sort_name_1 CHECK (length(sort_name) > 0),
    CONSTRAINT ck_catalog_artist_artist_type_1 CHECK (artist_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_catalog_artist_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_catalog_artist_version_1 CHECK (version > 0)
);
COMMENT ON TABLE catalog.artist IS 'Identidad canónica de artista o agrupación.';

CREATE TABLE catalog.artist_alias (
    alias_id uuid NOT NULL DEFAULT uuidv7(),
    artist_id uuid NOT NULL,
    alias_text text NOT NULL,
    normalized_text text NOT NULL,
    language_tag varchar(35) NOT NULL,
    script_code varchar(64) NOT NULL,
    preferred boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_catalog_artist_alias PRIMARY KEY (alias_id),
    CONSTRAINT ck_catalog_artist_alias_alias_text_1 CHECK (length(alias_text) > 0),
    CONSTRAINT ck_catalog_artist_alias_normalized_text_1 CHECK (length(normalized_text) > 0),
    CONSTRAINT ck_catalog_artist_alias_language_tag_1 CHECK (language_tag ~ '^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$'),
    CONSTRAINT ck_catalog_artist_alias_script_code_1 CHECK (script_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE catalog.artist_alias IS 'Alias buscable con idioma, escritura y vigencia.';

CREATE TABLE catalog.musical_work (
    work_id uuid NOT NULL DEFAULT uuidv7(),
    canonical_title text NOT NULL,
    language_tag varchar(35) NOT NULL,
    release_date date,
    status_code varchar(64) NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_catalog_musical_work PRIMARY KEY (work_id),
    CONSTRAINT ck_catalog_musical_work_canonical_title_1 CHECK (length(canonical_title) > 0),
    CONSTRAINT ck_catalog_musical_work_language_tag_1 CHECK (language_tag ~ '^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$'),
    CONSTRAINT ck_catalog_musical_work_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_catalog_musical_work_version_1 CHECK (version > 0)
);
COMMENT ON TABLE catalog.musical_work IS 'Obra musical abstracta separada de sus grabaciones.';

CREATE TABLE catalog.work_title (
    work_title_id uuid NOT NULL DEFAULT uuidv7(),
    work_id uuid NOT NULL,
    title_text text NOT NULL,
    normalized_text text NOT NULL,
    language_tag varchar(35) NOT NULL,
    title_type varchar(64) NOT NULL,
    preferred boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_catalog_work_title PRIMARY KEY (work_title_id),
    CONSTRAINT ck_catalog_work_title_title_text_1 CHECK (length(title_text) > 0),
    CONSTRAINT ck_catalog_work_title_normalized_text_1 CHECK (length(normalized_text) > 0),
    CONSTRAINT ck_catalog_work_title_language_tag_1 CHECK (language_tag ~ '^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$'),
    CONSTRAINT ck_catalog_work_title_title_type_1 CHECK (title_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE catalog.work_title IS 'Título alterno o localizado de una obra.';

CREATE TABLE catalog.work_artist (
    work_id uuid NOT NULL,
    artist_id uuid NOT NULL,
    role_code varchar(64) NOT NULL,
    display_order integer NOT NULL,
    CONSTRAINT pk_catalog_work_artist PRIMARY KEY (work_id, artist_id, role_code),
    CONSTRAINT ck_catalog_work_artist_role_code_1 CHECK (role_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_catalog_work_artist_display_order_1 CHECK (display_order >= 0)
);
COMMENT ON TABLE catalog.work_artist IS 'Relación artista-obra con rol y orden.';

CREATE TABLE catalog.recording (
    recording_id uuid NOT NULL DEFAULT uuidv7(),
    work_id uuid NOT NULL,
    recording_title text,
    duration_ms bigint,
    release_date date,
    status_code varchar(64) NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_catalog_recording PRIMARY KEY (recording_id),
    CONSTRAINT ck_catalog_recording_duration_ms_1 CHECK (duration_ms >= 0),
    CONSTRAINT ck_catalog_recording_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_catalog_recording_version_1 CHECK (version > 0),
    CONSTRAINT ck_catalog_recording_table_1 CHECK (duration_ms IS NULL OR duration_ms > 0)
);
COMMENT ON TABLE catalog.recording IS 'Grabación/version concreta que contextualiza reproducción y aprendizaje.';

CREATE TABLE catalog.recording_source (
    source_id uuid NOT NULL DEFAULT uuidv7(),
    recording_id uuid NOT NULL,
    provider_code varchar(64) NOT NULL,
    external_ref varchar(32) NOT NULL,
    duration_ms bigint,
    offset_ms bigint NOT NULL DEFAULT 0,
    status_code varchar(64) NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_catalog_recording_source PRIMARY KEY (source_id),
    CONSTRAINT ck_catalog_recording_source_provider_code_1 CHECK (provider_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_catalog_recording_source_external_ref_1 CHECK (external_ref ~ '^[A-Za-z0-9_-]{6,32}$'),
    CONSTRAINT ck_catalog_recording_source_duration_ms_1 CHECK (duration_ms >= 0),
    CONSTRAINT ck_catalog_recording_source_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_catalog_recording_source_version_1 CHECK (version > 0),
    CONSTRAINT ck_catalog_recording_source_table_1 CHECK (duration_ms IS NULL OR duration_ms > 0),
    CONSTRAINT ck_catalog_recording_source_table_2 CHECK (provider_code = 'YOUTUBE')
);
COMMENT ON TABLE catalog.recording_source IS 'Referencia propia al reproductor autorizado.';

CREATE TABLE catalog.recording_credit (
    credit_id uuid NOT NULL DEFAULT uuidv7(),
    recording_id uuid NOT NULL,
    artist_id uuid,
    display_name text NOT NULL,
    role_code varchar(64) NOT NULL,
    display_order integer NOT NULL,
    CONSTRAINT pk_catalog_recording_credit PRIMARY KEY (credit_id),
    CONSTRAINT ck_catalog_recording_credit_display_name_1 CHECK (length(display_name) > 0),
    CONSTRAINT ck_catalog_recording_credit_role_code_1 CHECK (role_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_catalog_recording_credit_display_order_1 CHECK (display_order >= 0)
);
COMMENT ON TABLE catalog.recording_credit IS 'Crédito ordenado de la grabación.';

CREATE TABLE catalog.source_reference (
    source_reference_id uuid NOT NULL DEFAULT uuidv7(),
    source_type varchar(64) NOT NULL,
    citation text NOT NULL,
    locator text,
    retrieved_at timestamptz,
    checksum bytea,
    CONSTRAINT pk_catalog_source_reference PRIMARY KEY (source_reference_id),
    CONSTRAINT ck_catalog_source_reference_source_type_1 CHECK (source_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_catalog_source_reference_citation_1 CHECK (length(citation) > 0),
    CONSTRAINT ck_catalog_source_reference_checksum_1 CHECK (octet_length(checksum) BETWEEN 16 AND 128)
);
COMMENT ON TABLE catalog.source_reference IS 'Procedencia bibliográfica o evidencia de metadatos.';

CREATE TABLE catalog.recording_status_history (
    history_id uuid NOT NULL DEFAULT uuidv7(),
    recording_id uuid NOT NULL,
    from_status varchar(64),
    to_status varchar(64) NOT NULL,
    changed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by uuid NOT NULL,
    reason text NOT NULL,
    CONSTRAINT pk_catalog_recording_status_history PRIMARY KEY (history_id),
    CONSTRAINT ck_catalog_recording_status_history_from_status_1 CHECK (from_status ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_catalog_recording_status_history_to_status_1 CHECK (to_status ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_catalog_recording_status_history_reason_1 CHECK (length(reason) > 0)
);
COMMENT ON TABLE catalog.recording_status_history IS 'Historial explicable del estado de catálogo.';

CREATE TABLE catalog.song_search_document (
    recording_id uuid NOT NULL,
    publication_id uuid NOT NULL,
    normalized_terms text NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS (to_tsvector('simple', normalized_terms)) STORED,
    eligibility_version bigint NOT NULL DEFAULT 1,
    indexed_at timestamptz NOT NULL,
    CONSTRAINT pk_catalog_song_search_document PRIMARY KEY (recording_id),
    CONSTRAINT ck_catalog_song_search_document_normalized_terms_1 CHECK (length(normalized_terms) > 0),
    CONSTRAINT ck_catalog_song_search_document_eligibility_version_1 CHECK (eligibility_version > 0)
);
COMMENT ON TABLE catalog.song_search_document IS 'Proyección interna para búsqueda por títulos, artistas, alias, kana y romaji.';


-- Esquema content
CREATE TABLE content.lyrics_revision (
    lyrics_revision_id uuid NOT NULL DEFAULT uuidv7(),
    recording_id uuid NOT NULL,
    revision_no integer NOT NULL,
    parent_revision_id uuid,
    status_code varchar(64) NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    checksum bytea NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_content_lyrics_revision PRIMARY KEY (lyrics_revision_id),
    CONSTRAINT ck_content_lyrics_revision_revision_no_1 CHECK (revision_no > 0),
    CONSTRAINT ck_content_lyrics_revision_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_lyrics_revision_checksum_1 CHECK (octet_length(checksum) BETWEEN 16 AND 128),
    CONSTRAINT ck_content_lyrics_revision_version_1 CHECK (version > 0)
);
COMMENT ON TABLE content.lyrics_revision IS 'Revisión inmutable de la letra japonesa de una grabación.';

CREATE TABLE content.lyric_section (
    section_id uuid NOT NULL DEFAULT uuidv7(),
    lyrics_revision_id uuid NOT NULL,
    section_type varchar(64) NOT NULL,
    label text,
    display_order integer NOT NULL,
    CONSTRAINT pk_content_lyric_section PRIMARY KEY (section_id),
    CONSTRAINT ck_content_lyric_section_section_type_1 CHECK (section_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_lyric_section_display_order_1 CHECK (display_order >= 0)
);
COMMENT ON TABLE content.lyric_section IS 'Sección ordenada de una revisión de letra.';

CREATE TABLE content.lyric_line (
    line_id uuid NOT NULL DEFAULT uuidv7(),
    section_id uuid NOT NULL,
    line_no integer NOT NULL,
    japanese_text text NOT NULL,
    normalized_text text NOT NULL,
    speaker_label text,
    CONSTRAINT pk_content_lyric_line PRIMARY KEY (line_id),
    CONSTRAINT ck_content_lyric_line_line_no_1 CHECK (line_no > 0),
    CONSTRAINT ck_content_lyric_line_japanese_text_1 CHECK (length(japanese_text) > 0),
    CONSTRAINT ck_content_lyric_line_normalized_text_1 CHECK (length(normalized_text) > 0)
);
COMMENT ON TABLE content.lyric_line IS 'Línea japonesa con identidad estable dentro de una revisión.';

CREATE TABLE content.lyric_token (
    token_id uuid NOT NULL DEFAULT uuidv7(),
    line_id uuid NOT NULL,
    token_no integer NOT NULL,
    surface text NOT NULL,
    normalized_surface text NOT NULL,
    start_offset integer NOT NULL,
    end_offset integer NOT NULL,
    CONSTRAINT pk_content_lyric_token PRIMARY KEY (token_id),
    CONSTRAINT ck_content_lyric_token_token_no_1 CHECK (token_no > 0),
    CONSTRAINT ck_content_lyric_token_surface_1 CHECK (length(surface) > 0),
    CONSTRAINT ck_content_lyric_token_normalized_surface_1 CHECK (length(normalized_surface) > 0),
    CONSTRAINT ck_content_lyric_token_start_offset_1 CHECK (start_offset >= 0),
    CONSTRAINT ck_content_lyric_token_end_offset_1 CHECK (end_offset >= 0),
    CONSTRAINT ck_content_lyric_token_table_1 CHECK (end_offset > start_offset)
);
COMMENT ON TABLE content.lyric_token IS 'Token editorial que permite alineación y análisis contextual.';

CREATE TABLE content.timing_revision (
    timing_revision_id uuid NOT NULL DEFAULT uuidv7(),
    lyrics_revision_id uuid NOT NULL,
    source_id uuid NOT NULL,
    revision_no integer NOT NULL,
    offset_ms bigint NOT NULL,
    status_code varchar(64) NOT NULL,
    checksum bytea NOT NULL,
    CONSTRAINT pk_content_timing_revision PRIMARY KEY (timing_revision_id),
    CONSTRAINT ck_content_timing_revision_revision_no_1 CHECK (revision_no > 0),
    CONSTRAINT ck_content_timing_revision_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_timing_revision_checksum_1 CHECK (octet_length(checksum) BETWEEN 16 AND 128)
);
COMMENT ON TABLE content.timing_revision IS 'Sincronización versionada de una letra con una fuente exacta.';

CREATE TABLE content.timing_segment (
    segment_id uuid NOT NULL DEFAULT uuidv7(),
    timing_revision_id uuid NOT NULL,
    line_id uuid NOT NULL,
    start_ms bigint NOT NULL,
    end_ms bigint NOT NULL,
    display_order integer NOT NULL,
    CONSTRAINT pk_content_timing_segment PRIMARY KEY (segment_id),
    CONSTRAINT ck_content_timing_segment_start_ms_1 CHECK (start_ms >= 0),
    CONSTRAINT ck_content_timing_segment_end_ms_1 CHECK (end_ms >= 0),
    CONSTRAINT ck_content_timing_segment_display_order_1 CHECK (display_order >= 0),
    CONSTRAINT ck_content_timing_segment_table_1 CHECK (end_ms > start_ms)
);
COMMENT ON TABLE content.timing_segment IS 'Intervalo [inicio, fin) asociado a una línea.';

CREATE TABLE content.translation_revision (
    translation_revision_id uuid NOT NULL DEFAULT uuidv7(),
    lyrics_revision_id uuid NOT NULL,
    target_language varchar(35) NOT NULL,
    translation_type varchar(64) NOT NULL,
    revision_no integer NOT NULL,
    parent_revision_id uuid,
    status_code varchar(64) NOT NULL,
    checksum bytea NOT NULL,
    CONSTRAINT pk_content_translation_revision PRIMARY KEY (translation_revision_id),
    CONSTRAINT ck_content_translation_revision_target_language_1 CHECK (target_language ~ '^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$'),
    CONSTRAINT ck_content_translation_revision_translation_type_1 CHECK (translation_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_translation_revision_revision_no_1 CHECK (revision_no > 0),
    CONSTRAINT ck_content_translation_revision_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_translation_revision_checksum_1 CHECK (octet_length(checksum) BETWEEN 16 AND 128)
);
COMMENT ON TABLE content.translation_revision IS 'Traducción versionada para un idioma objetivo.';

CREATE TABLE content.translation_line (
    translation_line_id uuid NOT NULL DEFAULT uuidv7(),
    translation_revision_id uuid NOT NULL,
    line_id uuid NOT NULL,
    translated_text text NOT NULL,
    variant_code varchar(64) NOT NULL,
    display_order integer NOT NULL,
    CONSTRAINT pk_content_translation_line PRIMARY KEY (translation_line_id),
    CONSTRAINT ck_content_translation_line_translated_text_1 CHECK (length(translated_text) > 0),
    CONSTRAINT ck_content_translation_line_variant_code_1 CHECK (variant_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_translation_line_display_order_1 CHECK (display_order >= 0)
);
COMMENT ON TABLE content.translation_line IS 'Traducción de una línea con variantes literal y natural separables.';

CREATE TABLE content.token_alignment (
    alignment_id uuid NOT NULL DEFAULT uuidv7(),
    translation_line_id uuid NOT NULL,
    token_id uuid NOT NULL,
    target_start integer,
    target_end integer,
    alignment_type varchar(64) NOT NULL,
    CONSTRAINT pk_content_token_alignment PRIMARY KEY (alignment_id),
    CONSTRAINT ck_content_token_alignment_target_start_1 CHECK (target_start >= 0),
    CONSTRAINT ck_content_token_alignment_target_end_1 CHECK (target_end >= 0),
    CONSTRAINT ck_content_token_alignment_alignment_type_1 CHECK (alignment_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_token_alignment_table_1 CHECK ((target_start IS NULL AND target_end IS NULL) OR (target_start IS NOT NULL AND target_end > target_start))
);
COMMENT ON TABLE content.token_alignment IS 'Alineación explicable entre token japonés y tramo traducido.';

CREATE TABLE content.translation_note (
    note_id uuid NOT NULL DEFAULT uuidv7(),
    translation_revision_id uuid NOT NULL,
    line_id uuid,
    token_id uuid,
    note_type varchar(64) NOT NULL,
    note_text text NOT NULL,
    source_reference_id uuid,
    CONSTRAINT pk_content_translation_note PRIMARY KEY (note_id),
    CONSTRAINT ck_content_translation_note_note_type_1 CHECK (note_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_translation_note_note_text_1 CHECK (length(note_text) > 0)
);
COMMENT ON TABLE content.translation_note IS 'Nota contextual o decisión del traductor.';

CREATE TABLE content.linguistic_analysis_revision (
    analysis_revision_id uuid NOT NULL DEFAULT uuidv7(),
    lyrics_revision_id uuid NOT NULL,
    revision_no integer NOT NULL,
    parent_revision_id uuid,
    status_code varchar(64) NOT NULL,
    checksum bytea NOT NULL,
    CONSTRAINT pk_content_linguistic_analysis_revision PRIMARY KEY (analysis_revision_id),
    CONSTRAINT ck_content_linguistic_analysis_revision_revision_no_1 CHECK (revision_no > 0),
    CONSTRAINT ck_content_linguistic_analysis_revision_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_linguistic_analysis_revision_checksum_1 CHECK (octet_length(checksum) BETWEEN 16 AND 128)
);
COMMENT ON TABLE content.linguistic_analysis_revision IS 'Conjunto versionado de análisis lingüístico para una letra.';

CREATE TABLE content.token_reading (
    token_reading_id uuid NOT NULL DEFAULT uuidv7(),
    analysis_revision_id uuid NOT NULL,
    token_id uuid NOT NULL,
    reading_kana text NOT NULL,
    furigana text,
    romaji text,
    reading_type varchar(64) NOT NULL,
    CONSTRAINT pk_content_token_reading PRIMARY KEY (token_reading_id),
    CONSTRAINT ck_content_token_reading_reading_kana_1 CHECK (length(reading_kana) > 0),
    CONSTRAINT ck_content_token_reading_reading_type_1 CHECK (reading_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE content.token_reading IS 'Lectura editorial, furigana y romanización de un token.';

CREATE TABLE content.vocabulary_entry (
    vocabulary_id uuid NOT NULL DEFAULT uuidv7(),
    lemma text NOT NULL,
    reading text NOT NULL,
    part_of_speech varchar(64) NOT NULL,
    sense_key text NOT NULL,
    status_code varchar(64) NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_content_vocabulary_entry PRIMARY KEY (vocabulary_id),
    CONSTRAINT ck_content_vocabulary_entry_lemma_1 CHECK (length(lemma) > 0),
    CONSTRAINT ck_content_vocabulary_entry_reading_1 CHECK (length(reading) > 0),
    CONSTRAINT ck_content_vocabulary_entry_part_of_speech_1 CHECK (part_of_speech ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_vocabulary_entry_sense_key_1 CHECK (length(sense_key) > 0),
    CONSTRAINT ck_content_vocabulary_entry_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_vocabulary_entry_version_1 CHECK (version > 0)
);
COMMENT ON TABLE content.vocabulary_entry IS 'Entrada canónica interna de vocabulario.';

CREATE TABLE content.vocabulary_sense (
    sense_id uuid NOT NULL DEFAULT uuidv7(),
    vocabulary_id uuid NOT NULL,
    language_tag varchar(35) NOT NULL,
    definition text NOT NULL,
    usage_note text,
    display_order integer NOT NULL,
    CONSTRAINT pk_content_vocabulary_sense PRIMARY KEY (sense_id),
    CONSTRAINT ck_content_vocabulary_sense_language_tag_1 CHECK (language_tag ~ '^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$'),
    CONSTRAINT ck_content_vocabulary_sense_definition_1 CHECK (length(definition) > 0),
    CONSTRAINT ck_content_vocabulary_sense_display_order_1 CHECK (display_order >= 0)
);
COMMENT ON TABLE content.vocabulary_sense IS 'Definición interna multilingüe de una entrada.';

CREATE TABLE content.vocabulary_occurrence (
    occurrence_id uuid NOT NULL DEFAULT uuidv7(),
    analysis_revision_id uuid NOT NULL,
    token_id uuid NOT NULL,
    vocabulary_id uuid NOT NULL,
    inflection text,
    confidence_code varchar(64) NOT NULL,
    CONSTRAINT pk_content_vocabulary_occurrence PRIMARY KEY (occurrence_id),
    CONSTRAINT ck_content_vocabulary_occurrence_confidence_code_1 CHECK (confidence_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE content.vocabulary_occurrence IS 'Uso contextual de vocabulario en un token.';

CREATE TABLE content.kanji_entry (
    kanji_id uuid NOT NULL DEFAULT uuidv7(),
    character text NOT NULL,
    grade_code varchar(64),
    jlpt_code varchar(64),
    status_code varchar(64) NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_content_kanji_entry PRIMARY KEY (kanji_id),
    CONSTRAINT ck_content_kanji_entry_character_1 CHECK (length(character) > 0),
    CONSTRAINT ck_content_kanji_entry_grade_code_1 CHECK (grade_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_kanji_entry_jlpt_code_1 CHECK (jlpt_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_kanji_entry_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_kanji_entry_version_1 CHECK (version > 0)
);
COMMENT ON TABLE content.kanji_entry IS 'Entrada interna de kanji y significado educativo.';

CREATE TABLE content.kanji_reading (
    kanji_reading_id uuid NOT NULL DEFAULT uuidv7(),
    kanji_id uuid NOT NULL,
    reading text NOT NULL,
    reading_type varchar(64) NOT NULL,
    language_tag varchar(35) NOT NULL,
    meaning text NOT NULL,
    display_order integer NOT NULL,
    CONSTRAINT pk_content_kanji_reading PRIMARY KEY (kanji_reading_id),
    CONSTRAINT ck_content_kanji_reading_reading_1 CHECK (length(reading) > 0),
    CONSTRAINT ck_content_kanji_reading_reading_type_1 CHECK (reading_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_kanji_reading_language_tag_1 CHECK (language_tag ~ '^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$'),
    CONSTRAINT ck_content_kanji_reading_meaning_1 CHECK (length(meaning) > 0),
    CONSTRAINT ck_content_kanji_reading_display_order_1 CHECK (display_order >= 0)
);
COMMENT ON TABLE content.kanji_reading IS 'Lectura y significado multilingüe de un kanji.';

CREATE TABLE content.kanji_occurrence (
    occurrence_id uuid NOT NULL DEFAULT uuidv7(),
    analysis_revision_id uuid NOT NULL,
    token_id uuid NOT NULL,
    kanji_id uuid NOT NULL,
    char_offset integer NOT NULL,
    CONSTRAINT pk_content_kanji_occurrence PRIMARY KEY (occurrence_id),
    CONSTRAINT ck_content_kanji_occurrence_char_offset_1 CHECK (char_offset >= 0)
);
COMMENT ON TABLE content.kanji_occurrence IS 'Aparición contextual de un kanji dentro de un token.';

CREATE TABLE content.grammar_point (
    grammar_point_id uuid NOT NULL DEFAULT uuidv7(),
    grammar_code varchar(64) NOT NULL,
    title text NOT NULL,
    level_code varchar(64),
    status_code varchar(64) NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_content_grammar_point PRIMARY KEY (grammar_point_id),
    CONSTRAINT ck_content_grammar_point_grammar_code_1 CHECK (grammar_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_grammar_point_title_1 CHECK (length(title) > 0),
    CONSTRAINT ck_content_grammar_point_level_code_1 CHECK (level_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_grammar_point_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_grammar_point_version_1 CHECK (version > 0)
);
COMMENT ON TABLE content.grammar_point IS 'Concepto gramatical interno con explicación multilingüe.';

CREATE TABLE content.grammar_explanation (
    explanation_id uuid NOT NULL DEFAULT uuidv7(),
    grammar_point_id uuid NOT NULL,
    language_tag varchar(35) NOT NULL,
    explanation text NOT NULL,
    examples text,
    revision_no integer NOT NULL,
    CONSTRAINT pk_content_grammar_explanation PRIMARY KEY (explanation_id),
    CONSTRAINT ck_content_grammar_explanation_language_tag_1 CHECK (language_tag ~ '^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$'),
    CONSTRAINT ck_content_grammar_explanation_explanation_1 CHECK (length(explanation) > 0),
    CONSTRAINT ck_content_grammar_explanation_revision_no_1 CHECK (revision_no > 0)
);
COMMENT ON TABLE content.grammar_explanation IS 'Explicación localizada de un punto gramatical.';

CREATE TABLE content.grammar_occurrence (
    occurrence_id uuid NOT NULL DEFAULT uuidv7(),
    analysis_revision_id uuid NOT NULL,
    grammar_point_id uuid NOT NULL,
    line_id uuid NOT NULL,
    start_token_id uuid,
    end_token_id uuid,
    note text,
    CONSTRAINT pk_content_grammar_occurrence PRIMARY KEY (occurrence_id),
    CONSTRAINT ck_content_grammar_occurrence_table_1 CHECK ((start_token_id IS NULL) = (end_token_id IS NULL))
);
COMMENT ON TABLE content.grammar_occurrence IS 'Aplicación contextual de gramática en una línea o rango de tokens.';

CREATE TABLE content.morphology_annotation (
    annotation_id uuid NOT NULL DEFAULT uuidv7(),
    analysis_revision_id uuid NOT NULL,
    token_id uuid NOT NULL,
    lemma text NOT NULL,
    pos_code varchar(64) NOT NULL,
    conjugation_code varchar(64),
    features jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT pk_content_morphology_annotation PRIMARY KEY (annotation_id),
    CONSTRAINT ck_content_morphology_annotation_lemma_1 CHECK (length(lemma) > 0),
    CONSTRAINT ck_content_morphology_annotation_pos_code_1 CHECK (pos_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_content_morphology_annotation_conjugation_code_1 CHECK (conjugation_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE content.morphology_annotation IS 'Morfología contextual por token.';


-- Esquema learning
CREATE TABLE learning.learner_profile (
    learner_profile_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid NOT NULL,
    level_code varchar(64),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_learning_learner_profile PRIMARY KEY (learner_profile_id),
    CONSTRAINT ck_learning_learner_profile_level_code_1 CHECK (level_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_learner_profile_version_1 CHECK (version > 0)
);
COMMENT ON TABLE learning.learner_profile IS 'Estado educativo general no derivado de una canción específica.';

CREATE TABLE learning.competency (
    competency_id uuid NOT NULL DEFAULT uuidv7(),
    competency_code varchar(64) NOT NULL,
    domain_code varchar(64) NOT NULL,
    title text NOT NULL,
    definition text NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_learning_competency PRIMARY KEY (competency_id),
    CONSTRAINT ck_learning_competency_competency_code_1 CHECK (competency_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_competency_domain_code_1 CHECK (domain_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_competency_title_1 CHECK (length(title) > 0),
    CONSTRAINT ck_learning_competency_definition_1 CHECK (length(definition) > 0),
    CONSTRAINT ck_learning_competency_version_1 CHECK (version > 0)
);
COMMENT ON TABLE learning.competency IS 'Competencia estable sobre la que se acumula evidencia.';

CREATE TABLE learning.study_session (
    study_session_id uuid NOT NULL DEFAULT uuidv7(),
    learner_profile_id uuid NOT NULL,
    recording_id uuid NOT NULL,
    publication_id uuid NOT NULL,
    status_code varchar(64) NOT NULL,
    started_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at timestamptz,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_learning_study_session PRIMARY KEY (study_session_id),
    CONSTRAINT ck_learning_study_session_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_study_session_version_1 CHECK (version > 0),
    CONSTRAINT ck_learning_study_session_table_1 CHECK (ended_at IS NULL OR ended_at >= started_at)
);
COMMENT ON TABLE learning.study_session IS 'Sesión confirmada de estudio de una cuenta y grabación.';

CREATE TABLE learning.study_activity (
    activity_id uuid NOT NULL DEFAULT uuidv7(),
    study_session_id uuid NOT NULL,
    activity_type varchar(64) NOT NULL,
    object_type varchar(64) NOT NULL,
    object_id uuid,
    occurred_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sequence_no integer NOT NULL,
    CONSTRAINT pk_learning_study_activity PRIMARY KEY (activity_id),
    CONSTRAINT ck_learning_study_activity_activity_type_1 CHECK (activity_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_study_activity_object_type_1 CHECK (object_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_study_activity_sequence_no_1 CHECK (sequence_no >= 0)
);
COMMENT ON TABLE learning.study_activity IS 'Paso confirmado dentro de una sesión.';

CREATE TABLE learning.exercise_definition (
    exercise_id uuid NOT NULL DEFAULT uuidv7(),
    recording_id uuid NOT NULL,
    line_id uuid,
    exercise_type varchar(64) NOT NULL,
    competency_id uuid NOT NULL,
    status_code varchar(64) NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_learning_exercise_definition PRIMARY KEY (exercise_id),
    CONSTRAINT ck_learning_exercise_definition_exercise_type_1 CHECK (exercise_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_exercise_definition_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_exercise_definition_version_1 CHECK (version > 0)
);
COMMENT ON TABLE learning.exercise_definition IS 'Identidad estable de un ejercicio contextual.';

CREATE TABLE learning.exercise_revision (
    exercise_revision_id uuid NOT NULL DEFAULT uuidv7(),
    exercise_id uuid NOT NULL,
    revision_no integer NOT NULL,
    prompt text NOT NULL,
    solution_spec jsonb NOT NULL DEFAULT '{}'::jsonb,
    status_code varchar(64) NOT NULL,
    checksum bytea NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_learning_exercise_revision PRIMARY KEY (exercise_revision_id),
    CONSTRAINT ck_learning_exercise_revision_revision_no_1 CHECK (revision_no > 0),
    CONSTRAINT ck_learning_exercise_revision_prompt_1 CHECK (length(prompt) > 0),
    CONSTRAINT ck_learning_exercise_revision_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_exercise_revision_checksum_1 CHECK (octet_length(checksum) BETWEEN 16 AND 128),
    CONSTRAINT ck_learning_exercise_revision_version_1 CHECK (version > 0)
);
COMMENT ON TABLE learning.exercise_revision IS 'Versión editorial congelable de consigna, solución y retroalimentación.';

CREATE TABLE learning.exercise_item (
    exercise_item_id uuid NOT NULL DEFAULT uuidv7(),
    exercise_revision_id uuid NOT NULL,
    item_type varchar(64) NOT NULL,
    item_order integer NOT NULL,
    prompt_fragment text,
    expected_value jsonb,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT pk_learning_exercise_item PRIMARY KEY (exercise_item_id),
    CONSTRAINT ck_learning_exercise_item_item_type_1 CHECK (item_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_exercise_item_item_order_1 CHECK (item_order >= 0)
);
COMMENT ON TABLE learning.exercise_item IS 'Elemento ordenado: hueco, opción, pista o unidad evaluable.';

CREATE TABLE learning.exercise_instance (
    instance_id uuid NOT NULL DEFAULT uuidv7(),
    study_session_id uuid NOT NULL,
    exercise_revision_id uuid NOT NULL,
    instance_no integer NOT NULL DEFAULT 1,
    state_code varchar(64) NOT NULL,
    seed text,
    delivered_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamptz,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_learning_exercise_instance PRIMARY KEY (instance_id),
    CONSTRAINT ck_learning_exercise_instance_instance_no_1 CHECK (instance_no > 0),
    CONSTRAINT ck_learning_exercise_instance_state_code_1 CHECK (state_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_exercise_instance_version_1 CHECK (version > 0),
    CONSTRAINT ck_learning_exercise_instance_table_1 CHECK (expires_at IS NULL OR expires_at > delivered_at)
);
COMMENT ON TABLE learning.exercise_instance IS 'Instancia privada y congelada entregada al estudiante.';

CREATE TABLE learning.exercise_instance_item (
    instance_item_id uuid NOT NULL DEFAULT uuidv7(),
    instance_id uuid NOT NULL,
    source_item_id uuid NOT NULL,
    display_order integer NOT NULL,
    presented_value jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT pk_learning_exercise_instance_item PRIMARY KEY (instance_item_id),
    CONSTRAINT ck_learning_exercise_instance_item_display_order_1 CHECK (display_order >= 0)
);
COMMENT ON TABLE learning.exercise_instance_item IS 'Copia lógica ordenada de los elementos visibles de una instancia.';

CREATE TABLE learning.answer_submission (
    submission_id uuid NOT NULL DEFAULT uuidv7(),
    instance_id uuid NOT NULL,
    submission_no integer NOT NULL DEFAULT 1,
    idempotency_key text NOT NULL,
    submitted_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status_code varchar(64) NOT NULL,
    answer_digest bytea NOT NULL,
    CONSTRAINT pk_learning_answer_submission PRIMARY KEY (submission_id),
    CONSTRAINT ck_learning_answer_submission_submission_no_1 CHECK (submission_no > 0),
    CONSTRAINT ck_learning_answer_submission_idempotency_key_1 CHECK (length(idempotency_key) > 0),
    CONSTRAINT ck_learning_answer_submission_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_answer_submission_answer_digest_1 CHECK (octet_length(answer_digest) BETWEEN 16 AND 128)
);
COMMENT ON TABLE learning.answer_submission IS 'Confirmación idempotente de una respuesta.';

CREATE TABLE learning.answer_value (
    answer_value_id uuid NOT NULL DEFAULT uuidv7(),
    submission_id uuid NOT NULL,
    instance_item_id uuid NOT NULL,
    value_type varchar(64) NOT NULL,
    value_text text,
    value_number numeric(18,6),
    selected_item_id uuid,
    CONSTRAINT pk_learning_answer_value PRIMARY KEY (answer_value_id),
    CONSTRAINT ck_learning_answer_value_value_type_1 CHECK (value_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_answer_value_table_1 CHECK (num_nonnulls(value_text, value_number, selected_item_id) = 1)
);
COMMENT ON TABLE learning.answer_value IS 'Valor respondido por elemento sin mezclar tipos.';

CREATE TABLE learning.evaluation_result (
    evaluation_id uuid NOT NULL DEFAULT uuidv7(),
    submission_id uuid NOT NULL,
    evaluator_version text NOT NULL,
    score numeric(7,6) NOT NULL,
    correct boolean NOT NULL,
    evaluated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    result_digest bytea NOT NULL,
    CONSTRAINT pk_learning_evaluation_result PRIMARY KEY (evaluation_id),
    CONSTRAINT ck_learning_evaluation_result_evaluator_version_1 CHECK (length(evaluator_version) > 0),
    CONSTRAINT ck_learning_evaluation_result_score_1 CHECK (score BETWEEN 0 AND 1),
    CONSTRAINT ck_learning_evaluation_result_result_digest_1 CHECK (octet_length(result_digest) BETWEEN 16 AND 128)
);
COMMENT ON TABLE learning.evaluation_result IS 'Resultado determinista y versionado de evaluar una entrega.';

CREATE TABLE learning.feedback_item (
    feedback_id uuid NOT NULL DEFAULT uuidv7(),
    evaluation_id uuid NOT NULL,
    item_id uuid,
    feedback_code varchar(64) NOT NULL,
    language_tag varchar(35) NOT NULL,
    message text NOT NULL,
    display_order integer NOT NULL,
    CONSTRAINT pk_learning_feedback_item PRIMARY KEY (feedback_id),
    CONSTRAINT ck_learning_feedback_item_feedback_code_1 CHECK (feedback_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_feedback_item_language_tag_1 CHECK (language_tag ~ '^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$'),
    CONSTRAINT ck_learning_feedback_item_message_1 CHECK (length(message) > 0),
    CONSTRAINT ck_learning_feedback_item_display_order_1 CHECK (display_order >= 0)
);
COMMENT ON TABLE learning.feedback_item IS 'Retroalimentación explicable y localizada.';

CREATE TABLE learning.learning_evidence (
    evidence_id uuid NOT NULL DEFAULT uuidv7(),
    learner_profile_id uuid NOT NULL,
    evaluation_id uuid NOT NULL,
    competency_id uuid NOT NULL,
    recording_id uuid NOT NULL,
    outcome numeric(7,6) NOT NULL DEFAULT 0,
    evidence_version integer NOT NULL,
    confirmed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    superseded_by uuid,
    CONSTRAINT pk_learning_learning_evidence PRIMARY KEY (evidence_id),
    CONSTRAINT ck_learning_learning_evidence_outcome_1 CHECK (outcome BETWEEN 0 AND 1),
    CONSTRAINT ck_learning_learning_evidence_evidence_version_1 CHECK (evidence_version > 0)
);
COMMENT ON TABLE learning.learning_evidence IS 'Hecho confirmado que alimenta progreso sin reescribir la entrega.';

CREATE TABLE learning.evidence_correction (
    correction_id uuid NOT NULL DEFAULT uuidv7(),
    original_evidence_id uuid NOT NULL,
    replacement_evidence_id uuid,
    reason_code varchar(64) NOT NULL,
    reason text NOT NULL,
    corrected_by uuid NOT NULL,
    corrected_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_learning_evidence_correction PRIMARY KEY (correction_id),
    CONSTRAINT ck_learning_evidence_correction_reason_code_1 CHECK (reason_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_learning_evidence_correction_reason_1 CHECK (length(reason) > 0)
);
COMMENT ON TABLE learning.evidence_correction IS 'Explica sustitución o anulación de evidencia.';

CREATE TABLE learning.study_session_snapshot (
    study_session_id uuid NOT NULL,
    last_activity_id uuid NOT NULL,
    last_instance_id uuid,
    state_version bigint NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_learning_study_session_snapshot PRIMARY KEY (study_session_id),
    CONSTRAINT ck_learning_study_session_snapshot_state_version_1 CHECK (state_version > 0)
);
COMMENT ON TABLE learning.study_session_snapshot IS 'Proyección privada de reanudación de sesión.';


-- Esquema progress
CREATE TABLE progress.song_progress (
    song_progress_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid NOT NULL,
    recording_id uuid NOT NULL,
    current_derivation_id uuid,
    completion numeric(7,6) NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_progress_song_progress PRIMARY KEY (song_progress_id),
    CONSTRAINT ck_progress_song_progress_completion_1 CHECK (completion BETWEEN 0 AND 1),
    CONSTRAINT ck_progress_song_progress_version_1 CHECK (version > 0)
);
COMMENT ON TABLE progress.song_progress IS 'Cabeza del progreso privado por cuenta y grabación.';

CREATE TABLE progress.progress_derivation (
    derivation_id uuid NOT NULL DEFAULT uuidv7(),
    song_progress_id uuid NOT NULL,
    algorithm_version text NOT NULL,
    derived_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completion numeric(7,6) NOT NULL DEFAULT 0,
    evidence_watermark timestamptz NOT NULL,
    supersedes_id uuid,
    CONSTRAINT pk_progress_progress_derivation PRIMARY KEY (derivation_id),
    CONSTRAINT ck_progress_progress_derivation_algorithm_version_1 CHECK (length(algorithm_version) > 0),
    CONSTRAINT ck_progress_progress_derivation_completion_1 CHECK (completion BETWEEN 0 AND 1),
    CONSTRAINT ck_progress_progress_derivation_table_1 CHECK (evidence_watermark <= derived_at)
);
COMMENT ON TABLE progress.progress_derivation IS 'Resultado versionado de calcular progreso.';

CREATE TABLE progress.progress_contribution (
    derivation_id uuid NOT NULL,
    evidence_id uuid NOT NULL,
    weight numeric(7,6) NOT NULL DEFAULT 0,
    contribution numeric(7,6) NOT NULL DEFAULT 0,
    CONSTRAINT pk_progress_progress_contribution PRIMARY KEY (derivation_id, evidence_id),
    CONSTRAINT ck_progress_progress_contribution_weight_1 CHECK (weight BETWEEN 0 AND 1),
    CONSTRAINT ck_progress_progress_contribution_contribution_1 CHECK (contribution BETWEEN 0 AND 1)
);
COMMENT ON TABLE progress.progress_contribution IS 'Linaje evidencia-derivación.';

CREATE TABLE progress.competency_progress (
    competency_progress_id uuid NOT NULL DEFAULT uuidv7(),
    song_progress_id uuid NOT NULL,
    competency_id uuid NOT NULL,
    derivation_id uuid NOT NULL,
    mastery numeric(7,6) NOT NULL DEFAULT 0,
    evidence_count integer NOT NULL DEFAULT 0,
    CONSTRAINT pk_progress_competency_progress PRIMARY KEY (competency_progress_id),
    CONSTRAINT ck_progress_competency_progress_mastery_1 CHECK (mastery BETWEEN 0 AND 1),
    CONSTRAINT ck_progress_competency_progress_evidence_count_1 CHECK (evidence_count >= 0)
);
COMMENT ON TABLE progress.competency_progress IS 'Nivel derivado por competencia dentro de una canción.';

CREATE TABLE progress.resume_point (
    resume_point_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid NOT NULL,
    recording_id uuid NOT NULL,
    study_session_id uuid,
    line_id uuid,
    instance_id uuid,
    confirmed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_progress_resume_point PRIMARY KEY (resume_point_id),
    CONSTRAINT ck_progress_resume_point_version_1 CHECK (version > 0)
);
COMMENT ON TABLE progress.resume_point IS 'Punto confirmado para reanudar canción/sesión.';

CREATE TABLE progress.progress_history (
    history_id uuid NOT NULL DEFAULT uuidv7(),
    song_progress_id uuid NOT NULL,
    derivation_id uuid NOT NULL,
    previous_value numeric(7,6),
    new_value numeric(7,6) NOT NULL,
    reason_code varchar(64) NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_progress_progress_history PRIMARY KEY (history_id),
    CONSTRAINT ck_progress_progress_history_previous_value_1 CHECK (previous_value BETWEEN 0 AND 1),
    CONSTRAINT ck_progress_progress_history_new_value_1 CHECK (new_value BETWEEN 0 AND 1),
    CONSTRAINT ck_progress_progress_history_reason_code_1 CHECK (reason_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE progress.progress_history IS 'Historial compacto de cambios visibles de progreso.';

CREATE TABLE progress.learner_progress_projection (
    account_id uuid NOT NULL,
    totals jsonb NOT NULL DEFAULT '{}'::jsonb,
    last_activity_at timestamptz,
    projection_version bigint NOT NULL DEFAULT 1,
    rebuilt_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_progress_learner_progress_projection PRIMARY KEY (account_id),
    CONSTRAINT ck_progress_learner_progress_projection_projection_version_1 CHECK (projection_version > 0)
);
COMMENT ON TABLE progress.learner_progress_projection IS 'Proyección privada para panel/resumen del estudiante.';


-- Esquema editorial
CREATE TABLE editorial.rights_holder (
    rights_holder_id uuid NOT NULL DEFAULT uuidv7(),
    holder_type varchar(64) NOT NULL,
    display_name text NOT NULL,
    contact_ref bytea,
    status_code varchar(64) NOT NULL,
    CONSTRAINT pk_editorial_rights_holder PRIMARY KEY (rights_holder_id),
    CONSTRAINT ck_editorial_rights_holder_holder_type_1 CHECK (holder_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_rights_holder_display_name_1 CHECK (length(display_name) > 0),
    CONSTRAINT ck_editorial_rights_holder_contact_ref_1 CHECK (octet_length(contact_ref) >= 16),
    CONSTRAINT ck_editorial_rights_holder_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE editorial.rights_holder IS 'Persona u organización que concede o declara derechos.';

CREATE TABLE editorial.rights_record (
    rights_record_id uuid NOT NULL DEFAULT uuidv7(),
    rights_holder_id uuid NOT NULL,
    object_type varchar(64) NOT NULL,
    object_id uuid NOT NULL,
    basis_code varchar(64) NOT NULL,
    status_code varchar(64) NOT NULL,
    valid_from timestamptz,
    valid_to timestamptz,
    evidence_object_id uuid,
    CONSTRAINT pk_editorial_rights_record PRIMARY KEY (rights_record_id),
    CONSTRAINT ck_editorial_rights_record_object_type_1 CHECK (object_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_rights_record_basis_code_1 CHECK (basis_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_rights_record_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_rights_record_table_1 CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from)
);
COMMENT ON TABLE editorial.rights_record IS 'Base de uso, licencia o autorización sobre un objeto.';

CREATE TABLE editorial.rights_scope (
    rights_scope_id uuid NOT NULL DEFAULT uuidv7(),
    rights_record_id uuid NOT NULL,
    territory_code varchar(64) NOT NULL,
    language_tag varchar(35),
    channel_code varchar(64) NOT NULL,
    use_code varchar(64) NOT NULL,
    CONSTRAINT pk_editorial_rights_scope PRIMARY KEY (rights_scope_id),
    CONSTRAINT ck_editorial_rights_scope_territory_code_1 CHECK (territory_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_rights_scope_language_tag_1 CHECK (language_tag ~ '^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$'),
    CONSTRAINT ck_editorial_rights_scope_channel_code_1 CHECK (channel_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_rights_scope_use_code_1 CHECK (use_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE editorial.rights_scope IS 'Territorio, idioma, canal y uso permitido por un derecho.';

CREATE TABLE editorial.provenance_record (
    provenance_id uuid NOT NULL DEFAULT uuidv7(),
    object_type varchar(64) NOT NULL,
    object_id uuid NOT NULL,
    source_reference_id uuid NOT NULL,
    contribution_type varchar(64) NOT NULL,
    recorded_by uuid NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_editorial_provenance_record PRIMARY KEY (provenance_id),
    CONSTRAINT ck_editorial_provenance_record_object_type_1 CHECK (object_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_provenance_record_contribution_type_1 CHECK (contribution_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE editorial.provenance_record IS 'Linaje de un componente editorial y sus fuentes.';

CREATE TABLE editorial.editorial_package (
    package_id uuid NOT NULL DEFAULT uuidv7(),
    recording_id uuid NOT NULL,
    package_no integer NOT NULL,
    status_code varchar(64) NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    frozen_at timestamptz,
    checksum bytea NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_editorial_editorial_package PRIMARY KEY (package_id),
    CONSTRAINT ck_editorial_editorial_package_package_no_1 CHECK (package_no > 0),
    CONSTRAINT ck_editorial_editorial_package_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_editorial_package_checksum_1 CHECK (octet_length(checksum) BETWEEN 16 AND 128),
    CONSTRAINT ck_editorial_editorial_package_version_1 CHECK (version > 0)
);
COMMENT ON TABLE editorial.editorial_package IS 'Agregado que reúne versiones compatibles para revisión/publicación.';

CREATE TABLE editorial.package_component (
    package_component_id uuid NOT NULL DEFAULT uuidv7(),
    package_id uuid NOT NULL,
    component_kind varchar(64) NOT NULL,
    lyrics_revision_id uuid,
    timing_revision_id uuid,
    translation_revision_id uuid,
    analysis_revision_id uuid,
    exercise_revision_id uuid,
    checksum bytea NOT NULL,
    CONSTRAINT pk_editorial_package_component PRIMARY KEY (package_component_id),
    CONSTRAINT ck_editorial_package_component_component_kind_1 CHECK (component_kind ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_package_component_checksum_1 CHECK (octet_length(checksum) BETWEEN 16 AND 128),
    CONSTRAINT ck_editorial_package_component_table_1 CHECK (num_nonnulls(lyrics_revision_id, timing_revision_id, translation_revision_id, analysis_revision_id, exercise_revision_id) = 1)
);
COMMENT ON TABLE editorial.package_component IS 'Vincula el paquete con una revisión concreta y tipada.';

CREATE TABLE editorial.review_submission (
    submission_id uuid NOT NULL DEFAULT uuidv7(),
    package_id uuid NOT NULL,
    submitted_by uuid NOT NULL,
    submitted_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status_code varchar(64) NOT NULL,
    checklist_version text NOT NULL,
    CONSTRAINT pk_editorial_review_submission PRIMARY KEY (submission_id),
    CONSTRAINT ck_editorial_review_submission_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_review_submission_checklist_version_1 CHECK (length(checklist_version) > 0)
);
COMMENT ON TABLE editorial.review_submission IS 'Sometimiento congelado a revisión.';

CREATE TABLE editorial.review_assignment (
    assignment_id uuid NOT NULL DEFAULT uuidv7(),
    submission_id uuid NOT NULL,
    reviewer_id uuid NOT NULL,
    scope_code varchar(64) NOT NULL,
    assigned_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    due_at timestamptz,
    conflict_declared boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_editorial_review_assignment PRIMARY KEY (assignment_id),
    CONSTRAINT ck_editorial_review_assignment_scope_code_1 CHECK (scope_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_review_assignment_table_1 CHECK (due_at IS NULL OR due_at >= assigned_at)
);
COMMENT ON TABLE editorial.review_assignment IS 'Asignación explícita e independiente de revisor.';

CREATE TABLE editorial.review_decision (
    decision_id uuid NOT NULL DEFAULT uuidv7(),
    submission_id uuid NOT NULL,
    assignment_id uuid NOT NULL,
    decision_code varchar(64) NOT NULL,
    reason text NOT NULL,
    decided_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    checklist_result jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT pk_editorial_review_decision PRIMARY KEY (decision_id),
    CONSTRAINT ck_editorial_review_decision_decision_code_1 CHECK (decision_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_review_decision_reason_1 CHECK (length(reason) > 0)
);
COMMENT ON TABLE editorial.review_decision IS 'Decisión explicable sobre el paquete o un componente.';

CREATE TABLE editorial.publication (
    publication_id uuid NOT NULL DEFAULT uuidv7(),
    recording_id uuid NOT NULL,
    package_id uuid NOT NULL,
    publication_no integer NOT NULL,
    status_code varchar(64) NOT NULL,
    active_from timestamptz NOT NULL,
    active_to timestamptz,
    published_by uuid NOT NULL,
    published_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    checksum bytea NOT NULL,
    CONSTRAINT pk_editorial_publication PRIMARY KEY (publication_id),
    CONSTRAINT ck_editorial_publication_publication_no_1 CHECK (publication_no > 0),
    CONSTRAINT ck_editorial_publication_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_publication_checksum_1 CHECK (octet_length(checksum) BETWEEN 16 AND 128),
    CONSTRAINT ck_editorial_publication_table_1 CHECK (active_to IS NULL OR active_to > active_from),
    CONSTRAINT ck_editorial_publication_table_2 CHECK (published_at <= active_from OR status_code <> 'ACTIVE')
);
COMMENT ON TABLE editorial.publication IS 'Publicación atómica de un paquete para una grabación.';

CREATE TABLE editorial.publication_component (
    publication_component_id uuid NOT NULL DEFAULT uuidv7(),
    publication_id uuid NOT NULL,
    component_kind varchar(64) NOT NULL,
    source_component_id uuid NOT NULL,
    component_checksum bytea NOT NULL,
    display_order integer NOT NULL,
    CONSTRAINT pk_editorial_publication_component PRIMARY KEY (publication_component_id),
    CONSTRAINT ck_editorial_publication_component_component_kind_1 CHECK (component_kind ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_publication_component_component_checksum_1 CHECK (octet_length(component_checksum) BETWEEN 16 AND 128),
    CONSTRAINT ck_editorial_publication_component_display_order_1 CHECK (display_order >= 0)
);
COMMENT ON TABLE editorial.publication_component IS 'Instantánea de componentes realmente publicados.';

CREATE TABLE editorial.publication_availability (
    availability_id uuid NOT NULL DEFAULT uuidv7(),
    publication_id uuid NOT NULL,
    territory_code varchar(64) NOT NULL,
    language_tag varchar(35),
    audience_code varchar(64) NOT NULL,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    status_code varchar(64) NOT NULL,
    CONSTRAINT pk_editorial_publication_availability PRIMARY KEY (availability_id),
    CONSTRAINT ck_editorial_publication_availability_territory_code_1 CHECK (territory_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_publication_availability_language_tag_1 CHECK (language_tag ~ '^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$'),
    CONSTRAINT ck_editorial_publication_availability_audience_code_1 CHECK (audience_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_publication_availability_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_publication_availability_table_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
);
COMMENT ON TABLE editorial.publication_availability IS 'Elegibilidad por territorio, idioma, audiencia y vigencia.';

CREATE TABLE editorial.correction_case (
    case_id uuid NOT NULL DEFAULT uuidv7(),
    publication_id uuid NOT NULL,
    case_type varchar(64) NOT NULL,
    status_code varchar(64) NOT NULL,
    reason text NOT NULL,
    opened_by uuid NOT NULL,
    opened_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at timestamptz,
    CONSTRAINT pk_editorial_correction_case PRIMARY KEY (case_id),
    CONSTRAINT ck_editorial_correction_case_case_type_1 CHECK (case_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_correction_case_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_correction_case_reason_1 CHECK (length(reason) > 0)
);
COMMENT ON TABLE editorial.correction_case IS 'Expediente de corrección, reversión o sustitución.';

CREATE TABLE editorial.publication_action (
    action_id uuid NOT NULL DEFAULT uuidv7(),
    publication_id uuid NOT NULL,
    case_id uuid,
    action_code varchar(64) NOT NULL,
    from_status varchar(64) NOT NULL,
    to_status varchar(64) NOT NULL,
    effective_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actor_id uuid NOT NULL,
    reason text NOT NULL,
    correlation_id uuid NOT NULL,
    CONSTRAINT pk_editorial_publication_action PRIMARY KEY (action_id),
    CONSTRAINT ck_editorial_publication_action_action_code_1 CHECK (action_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_publication_action_from_status_1 CHECK (from_status ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_publication_action_to_status_1 CHECK (to_status ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_publication_action_reason_1 CHECK (length(reason) > 0)
);
COMMENT ON TABLE editorial.publication_action IS 'Acción append-only que activa, retira, restaura, revierte o sustituye.';

CREATE TABLE editorial.published_package_projection (
    publication_id uuid NOT NULL DEFAULT uuidv7(),
    recording_id uuid NOT NULL,
    component_versions jsonb NOT NULL DEFAULT '{}'::jsonb,
    payload_ref uuid,
    projection_version bigint NOT NULL DEFAULT 1,
    built_at timestamptz NOT NULL,
    CONSTRAINT pk_editorial_published_package_projection PRIMARY KEY (publication_id),
    CONSTRAINT ck_editorial_published_package_projection_projection_version_1 CHECK (projection_version > 0)
);
COMMENT ON TABLE editorial.published_package_projection IS 'Paquete coherente optimizado para lectura del estudiante.';

CREATE TABLE editorial.editorial_lock (
    lock_id uuid NOT NULL DEFAULT uuidv7(),
    recording_id uuid NOT NULL,
    operation_code varchar(64) NOT NULL,
    owner_operation_id uuid NOT NULL,
    acquired_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamptz NOT NULL,
    CONSTRAINT pk_editorial_editorial_lock PRIMARY KEY (lock_id),
    CONSTRAINT ck_editorial_editorial_lock_operation_code_1 CHECK (operation_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_editorial_editorial_lock_table_1 CHECK (expires_at > acquired_at)
);
COMMENT ON TABLE editorial.editorial_lock IS 'Bloqueo lógico breve para publicar/corregir sin carrera.';


-- Esquema configuration
CREATE TABLE configuration.catalog_definition (
    catalog_definition_id uuid NOT NULL DEFAULT uuidv7(),
    catalog_code varchar(64) NOT NULL,
    owner_module varchar(64) NOT NULL,
    value_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
    status_code varchar(64) NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_configuration_catalog_definition PRIMARY KEY (catalog_definition_id),
    CONSTRAINT ck_configuration_catalog_definition_catalog_code_1 CHECK (catalog_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_catalog_definition_owner_module_1 CHECK (owner_module ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_catalog_definition_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_catalog_definition_version_1 CHECK (version > 0)
);
COMMENT ON TABLE configuration.catalog_definition IS 'Definición y propietario conceptual de un catálogo.';

CREATE TABLE configuration.catalog_entry (
    catalog_entry_id uuid NOT NULL DEFAULT uuidv7(),
    catalog_definition_id uuid NOT NULL,
    entry_code varchar(64) NOT NULL,
    labels jsonb NOT NULL DEFAULT '{}'::jsonb,
    value jsonb NOT NULL DEFAULT '{}'::jsonb,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    status_code varchar(64) NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_configuration_catalog_entry PRIMARY KEY (catalog_entry_id),
    CONSTRAINT ck_configuration_catalog_entry_entry_code_1 CHECK (entry_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_catalog_entry_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_catalog_entry_version_1 CHECK (version > 0),
    CONSTRAINT ck_configuration_catalog_entry_table_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
);
COMMENT ON TABLE configuration.catalog_entry IS 'Valor administrable con código estable, vigencia y localización.';

CREATE TABLE configuration.parameter_definition (
    parameter_definition_id uuid NOT NULL DEFAULT uuidv7(),
    parameter_key text NOT NULL,
    owner_module varchar(64) NOT NULL,
    value_type varchar(64) NOT NULL,
    validation_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
    default_value jsonb,
    status_code varchar(64) NOT NULL,
    CONSTRAINT pk_configuration_parameter_definition PRIMARY KEY (parameter_definition_id),
    CONSTRAINT ck_configuration_parameter_definition_parameter_key_1 CHECK (length(parameter_key) > 0),
    CONSTRAINT ck_configuration_parameter_definition_owner_module_1 CHECK (owner_module ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_parameter_definition_value_type_1 CHECK (value_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_parameter_definition_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE configuration.parameter_definition IS 'Contrato tipado de un parámetro no secreto.';

CREATE TABLE configuration.parameter_version (
    parameter_version_id uuid NOT NULL DEFAULT uuidv7(),
    parameter_definition_id uuid NOT NULL,
    version_no integer NOT NULL,
    scope_code varchar(64) NOT NULL,
    scope_value text,
    typed_value jsonb NOT NULL DEFAULT '{}'::jsonb,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    status_code varchar(64) NOT NULL,
    checksum bytea NOT NULL,
    CONSTRAINT pk_configuration_parameter_version PRIMARY KEY (parameter_version_id),
    CONSTRAINT ck_configuration_parameter_version_scope_code_1 CHECK (scope_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_parameter_version_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_parameter_version_checksum_1 CHECK (octet_length(checksum) BETWEEN 16 AND 128),
    CONSTRAINT ck_configuration_parameter_version_table_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
);
COMMENT ON TABLE configuration.parameter_version IS 'Valor candidato versionado con ámbito y vigencia.';

CREATE TABLE configuration.configuration_change_set (
    change_set_id uuid NOT NULL DEFAULT uuidv7(),
    status_code varchar(64) NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    validated_at timestamptz,
    approved_by uuid,
    checksum bytea NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_configuration_configuration_change_set PRIMARY KEY (change_set_id),
    CONSTRAINT ck_configuration_configuration_change_set_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_configuration_change_set_checksum_1 CHECK (octet_length(checksum) BETWEEN 16 AND 128),
    CONSTRAINT ck_configuration_configuration_change_set_version_1 CHECK (version > 0)
);
COMMENT ON TABLE configuration.configuration_change_set IS 'Conjunto atómico de cambios simulables y aprobables.';

CREATE TABLE configuration.configuration_change_item (
    change_item_id uuid NOT NULL DEFAULT uuidv7(),
    change_set_id uuid NOT NULL,
    object_type varchar(64) NOT NULL,
    catalog_entry_id uuid,
    parameter_version_id uuid,
    action_code varchar(64) NOT NULL,
    expected_version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_configuration_configuration_change_item PRIMARY KEY (change_item_id),
    CONSTRAINT ck_configuration_configuration_change_item_object_type_1 CHECK (object_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_configuration_change_item_action_code_1 CHECK (action_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_configuration_change_item_expected_version_1 CHECK (expected_version > 0),
    CONSTRAINT ck_configuration_configuration_change_item_table_1 CHECK (num_nonnulls(catalog_entry_id, parameter_version_id) = 1)
);
COMMENT ON TABLE configuration.configuration_change_item IS 'Elemento tipado de catálogo o parámetro dentro de un cambio.';

CREATE TABLE configuration.configuration_activation (
    activation_id uuid NOT NULL DEFAULT uuidv7(),
    change_set_id uuid NOT NULL,
    action_code varchar(64) NOT NULL,
    effective_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    applied_by uuid NOT NULL,
    result_code varchar(64) NOT NULL,
    correlation_id uuid NOT NULL,
    CONSTRAINT pk_configuration_configuration_activation PRIMARY KEY (activation_id),
    CONSTRAINT ck_configuration_configuration_activation_action_code_1 CHECK (action_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_configuration_activation_result_code_1 CHECK (result_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE configuration.configuration_activation IS 'Aplicación o reversión atómica con vigencia.';

CREATE TABLE configuration.effective_parameter (
    parameter_key text NOT NULL,
    scope_code varchar(64) NOT NULL,
    scope_value text,
    parameter_version_id uuid NOT NULL,
    typed_value jsonb NOT NULL DEFAULT '{}'::jsonb,
    effective_from timestamptz NOT NULL,
    projection_version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_configuration_effective_parameter PRIMARY KEY (parameter_version_id),
    CONSTRAINT ck_configuration_effective_parameter_parameter_key_1 CHECK (length(parameter_key) > 0),
    CONSTRAINT ck_configuration_effective_parameter_scope_code_1 CHECK (scope_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_effective_parameter_projection_version_1 CHECK (projection_version > 0)
);
COMMENT ON TABLE configuration.effective_parameter IS 'Proyección resoluble de valores efectivos por ámbito.';

CREATE TABLE configuration.business_calendar (
    calendar_id uuid NOT NULL DEFAULT uuidv7(),
    calendar_code varchar(64) NOT NULL,
    time_zone varchar(64) NOT NULL,
    rules jsonb NOT NULL DEFAULT '{}'::jsonb,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_configuration_business_calendar PRIMARY KEY (calendar_id),
    CONSTRAINT ck_configuration_business_calendar_calendar_code_1 CHECK (calendar_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_business_calendar_time_zone_1 CHECK (length(time_zone) BETWEEN 1 AND 64),
    CONSTRAINT ck_configuration_business_calendar_version_1 CHECK (version > 0),
    CONSTRAINT ck_configuration_business_calendar_table_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
);
COMMENT ON TABLE configuration.business_calendar IS 'Calendario y zona para vigencias o procesos definidos.';

CREATE TABLE configuration.retention_policy (
    retention_policy_id uuid NOT NULL DEFAULT uuidv7(),
    data_class varchar(64) NOT NULL,
    purpose_code varchar(64) NOT NULL,
    retention_days integer NOT NULL,
    trigger_code varchar(64) NOT NULL,
    exception_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
    valid_from timestamptz NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_configuration_retention_policy PRIMARY KEY (retention_policy_id),
    CONSTRAINT ck_configuration_retention_policy_data_class_1 CHECK (data_class ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_retention_policy_purpose_code_1 CHECK (purpose_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_retention_policy_trigger_code_1 CHECK (trigger_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_configuration_retention_policy_version_1 CHECK (version > 0),
    CONSTRAINT ck_configuration_retention_policy_table_1 CHECK (retention_days >= 0)
);
COMMENT ON TABLE configuration.retention_policy IS 'Política ejecutable de retención por clase y finalidad.';


-- Esquema ops
CREATE TABLE ops.outbox_message (
    event_id uuid NOT NULL,
    event_name text NOT NULL,
    schema_version integer NOT NULL DEFAULT 1,
    aggregate_type varchar(64) NOT NULL,
    aggregate_id uuid NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    correlation_id uuid NOT NULL,
    causation_id uuid,
    status_code varchar(64) NOT NULL,
    next_attempt_at timestamptz,
    CONSTRAINT pk_ops_outbox_message PRIMARY KEY (event_id),
    CONSTRAINT ck_ops_outbox_message_event_name_1 CHECK (length(event_name) > 0),
    CONSTRAINT ck_ops_outbox_message_schema_version_1 CHECK (schema_version > 0),
    CONSTRAINT ck_ops_outbox_message_aggregate_type_1 CHECK (aggregate_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_outbox_message_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE ops.outbox_message IS 'Evento interno confirmado en la misma transacción del agregado.';

CREATE TABLE ops.inbox_message (
    consumer_code varchar(64) NOT NULL,
    event_id uuid NOT NULL,
    received_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_at timestamptz,
    result_code varchar(64) NOT NULL,
    CONSTRAINT pk_ops_inbox_message PRIMARY KEY (consumer_code, event_id),
    CONSTRAINT ck_ops_inbox_message_consumer_code_1 CHECK (consumer_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_inbox_message_result_code_1 CHECK (result_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$')
);
COMMENT ON TABLE ops.inbox_message IS 'Deduplicación por consumidor de un evento interno.';

CREATE TABLE ops.idempotency_record (
    idempotency_id uuid NOT NULL DEFAULT uuidv7(),
    account_id uuid,
    operation_code varchar(64) NOT NULL,
    idempotency_key text NOT NULL,
    request_digest bytea NOT NULL,
    response_code integer NOT NULL,
    response_ref jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamptz NOT NULL,
    CONSTRAINT pk_ops_idempotency_record PRIMARY KEY (idempotency_id),
    CONSTRAINT ck_ops_idempotency_record_operation_code_1 CHECK (operation_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_idempotency_record_idempotency_key_1 CHECK (length(idempotency_key) > 0),
    CONSTRAINT ck_ops_idempotency_record_request_digest_1 CHECK (octet_length(request_digest) BETWEEN 16 AND 128),
    CONSTRAINT ck_ops_idempotency_record_response_code_1 CHECK (response_code >= 0),
    CONSTRAINT ck_ops_idempotency_record_table_1 CHECK (expires_at > created_at),
    CONSTRAINT ck_ops_idempotency_record_table_2 CHECK (response_code BETWEEN 100 AND 599)
);
COMMENT ON TABLE ops.idempotency_record IS 'Respuesta lógica reutilizable para una escritura repetida.';

CREATE TABLE ops.background_job (
    job_id uuid NOT NULL DEFAULT uuidv7(),
    job_type varchar(64) NOT NULL,
    owner_module varchar(64) NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    status_code varchar(64) NOT NULL,
    scheduled_at timestamptz NOT NULL,
    next_attempt_at timestamptz,
    attempt_count integer NOT NULL DEFAULT 0,
    correlation_id uuid NOT NULL,
    CONSTRAINT pk_ops_background_job PRIMARY KEY (job_id),
    CONSTRAINT ck_ops_background_job_job_type_1 CHECK (job_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_background_job_owner_module_1 CHECK (owner_module ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_background_job_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_background_job_attempt_count_1 CHECK (attempt_count >= 0),
    CONSTRAINT ck_ops_background_job_table_1 CHECK (attempt_count >= 0)
);
COMMENT ON TABLE ops.background_job IS 'Trabajo reintentable de indexación, retención, correo, exportación o recálculo.';

CREATE TABLE ops.job_attempt (
    job_attempt_id uuid NOT NULL DEFAULT uuidv7(),
    job_id uuid NOT NULL,
    attempt_no integer NOT NULL,
    started_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at timestamptz,
    result_code varchar(64) NOT NULL,
    error_code varchar(64),
    error_digest bytea,
    CONSTRAINT pk_ops_job_attempt PRIMARY KEY (job_attempt_id),
    CONSTRAINT ck_ops_job_attempt_attempt_no_1 CHECK (attempt_no > 0),
    CONSTRAINT ck_ops_job_attempt_result_code_1 CHECK (result_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_job_attempt_error_code_1 CHECK (error_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_job_attempt_error_digest_1 CHECK (octet_length(error_digest) BETWEEN 16 AND 128),
    CONSTRAINT ck_ops_job_attempt_table_1 CHECK (finished_at IS NULL OR finished_at >= started_at)
);
COMMENT ON TABLE ops.job_attempt IS 'Evidencia de cada ejecución de trabajo.';

CREATE TABLE ops.stored_object (
    object_id uuid NOT NULL DEFAULT uuidv7(),
    owner_module varchar(64) NOT NULL,
    purpose_code varchar(64) NOT NULL,
    storage_key text NOT NULL,
    media_type text NOT NULL,
    size_bytes bigint NOT NULL,
    checksum bytea NOT NULL,
    encryption_key_ref varchar(512) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    retention_until timestamptz,
    status_code varchar(64) NOT NULL,
    CONSTRAINT pk_ops_stored_object PRIMARY KEY (object_id),
    CONSTRAINT ck_ops_stored_object_owner_module_1 CHECK (owner_module ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_stored_object_purpose_code_1 CHECK (purpose_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_stored_object_storage_key_1 CHECK (length(storage_key) > 0),
    CONSTRAINT ck_ops_stored_object_media_type_1 CHECK (length(media_type) > 0),
    CONSTRAINT ck_ops_stored_object_size_bytes_1 CHECK (size_bytes >= 0),
    CONSTRAINT ck_ops_stored_object_checksum_1 CHECK (octet_length(checksum) BETWEEN 16 AND 128),
    CONSTRAINT ck_ops_stored_object_encryption_key_ref_1 CHECK (length(encryption_key_ref) > 0),
    CONSTRAINT ck_ops_stored_object_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_stored_object_table_1 CHECK (size_bytes >= 0),
    CONSTRAINT ck_ops_stored_object_table_2 CHECK (retention_until IS NULL OR retention_until >= created_at)
);
COMMENT ON TABLE ops.stored_object IS 'Metadatos de un objeto privado cifrado fuera de PostgreSQL.';

CREATE TABLE ops.read_model_checkpoint (
    projection_code varchar(64) NOT NULL,
    consumer_code varchar(64) NOT NULL,
    last_event_id uuid,
    last_occurred_at timestamptz,
    projection_version bigint NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ops_read_model_checkpoint PRIMARY KEY (projection_code, consumer_code),
    CONSTRAINT ck_ops_read_model_checkpoint_projection_code_1 CHECK (projection_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_read_model_checkpoint_consumer_code_1 CHECK (consumer_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_read_model_checkpoint_projection_version_1 CHECK (projection_version > 0)
);
COMMENT ON TABLE ops.read_model_checkpoint IS 'Marca de avance para reconstruir proyecciones.';

CREATE TABLE ops.data_quality_issue (
    issue_id uuid NOT NULL DEFAULT uuidv7(),
    owner_module varchar(64) NOT NULL,
    rule_code varchar(64) NOT NULL,
    object_type varchar(64) NOT NULL,
    object_id uuid NOT NULL,
    severity_code varchar(64) NOT NULL,
    detected_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status_code varchar(64) NOT NULL,
    resolved_at timestamptz,
    CONSTRAINT pk_ops_data_quality_issue PRIMARY KEY (issue_id),
    CONSTRAINT ck_ops_data_quality_issue_owner_module_1 CHECK (owner_module ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_data_quality_issue_rule_code_1 CHECK (rule_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_data_quality_issue_object_type_1 CHECK (object_type ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_data_quality_issue_severity_code_1 CHECK (severity_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_data_quality_issue_status_code_1 CHECK (status_code ~ '^[A-Z0-9][A-Z0-9._-]{0,63}$'),
    CONSTRAINT ck_ops_data_quality_issue_table_1 CHECK (resolved_at IS NULL OR resolved_at >= detected_at)
);
COMMENT ON TABLE ops.data_quality_issue IS 'Hallazgo verificable de integridad, referencia o calidad de datos.';


-- 4. Claves foráneas
ALTER TABLE identity.user_profile ADD CONSTRAINT fk_identity_user_profile_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE identity.preference_set ADD CONSTRAINT fk_identity_preference_set_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE identity.preference_set ADD CONSTRAINT fk_identity_preference_set_current_revision_id FOREIGN KEY (current_revision_id) REFERENCES identity.preference_revision (revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE identity.preference_revision ADD CONSTRAINT fk_identity_preference_revision_created_by FOREIGN KEY (created_by) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE identity.consent_record ADD CONSTRAINT fk_identity_consent_record_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE identity.privacy_request ADD CONSTRAINT fk_identity_privacy_request_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.credential ADD CONSTRAINT fk_security_credential_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.account_verification ADD CONSTRAINT fk_security_account_verification_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.recovery_token ADD CONSTRAINT fk_security_recovery_token_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.session ADD CONSTRAINT fk_security_session_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.mfa_method ADD CONSTRAINT fk_security_mfa_method_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.role_permission ADD CONSTRAINT fk_security_role_permission_role_id FOREIGN KEY (role_id) REFERENCES security.role (role_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.role_permission ADD CONSTRAINT fk_security_role_permission_permission_id FOREIGN KEY (permission_id) REFERENCES security.permission (permission_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.role_permission ADD CONSTRAINT fk_security_role_permission_granted_by FOREIGN KEY (granted_by) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.role_assignment ADD CONSTRAINT fk_security_role_assignment_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.role_assignment ADD CONSTRAINT fk_security_role_assignment_role_id FOREIGN KEY (role_id) REFERENCES security.role (role_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.role_assignment ADD CONSTRAINT fk_security_role_assignment_scope_id FOREIGN KEY (scope_id) REFERENCES security.access_scope (scope_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.security_event ADD CONSTRAINT fk_security_security_event_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.audit_event ADD CONSTRAINT fk_security_audit_event_actor_id FOREIGN KEY (actor_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE security.audit_seal ADD CONSTRAINT fk_security_audit_seal_object_id FOREIGN KEY (object_id) REFERENCES ops.stored_object (object_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE catalog.artist_alias ADD CONSTRAINT fk_catalog_artist_alias_artist_id FOREIGN KEY (artist_id) REFERENCES catalog.artist (artist_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE catalog.work_title ADD CONSTRAINT fk_catalog_work_title_work_id FOREIGN KEY (work_id) REFERENCES catalog.musical_work (work_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE catalog.work_artist ADD CONSTRAINT fk_catalog_work_artist_work_id FOREIGN KEY (work_id) REFERENCES catalog.musical_work (work_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE catalog.work_artist ADD CONSTRAINT fk_catalog_work_artist_artist_id FOREIGN KEY (artist_id) REFERENCES catalog.artist (artist_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE catalog.recording ADD CONSTRAINT fk_catalog_recording_work_id FOREIGN KEY (work_id) REFERENCES catalog.musical_work (work_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE catalog.recording_source ADD CONSTRAINT fk_catalog_recording_source_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE catalog.recording_credit ADD CONSTRAINT fk_catalog_recording_credit_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE catalog.recording_credit ADD CONSTRAINT fk_catalog_recording_credit_artist_id FOREIGN KEY (artist_id) REFERENCES catalog.artist (artist_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE catalog.recording_status_history ADD CONSTRAINT fk_catalog_recording_status_history_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE catalog.recording_status_history ADD CONSTRAINT fk_catalog_recording_status_history_changed_by FOREIGN KEY (changed_by) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE catalog.song_search_document ADD CONSTRAINT fk_catalog_song_search_document_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE catalog.song_search_document ADD CONSTRAINT fk_catalog_song_search_document_publication_id FOREIGN KEY (publication_id) REFERENCES editorial.publication (publication_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.lyrics_revision ADD CONSTRAINT fk_content_lyrics_revision_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.lyrics_revision ADD CONSTRAINT fk_content_lyrics_revision_parent_revision_id FOREIGN KEY (parent_revision_id) REFERENCES content.lyrics_revision (lyrics_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE content.lyrics_revision ADD CONSTRAINT fk_content_lyrics_revision_created_by FOREIGN KEY (created_by) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.lyric_section ADD CONSTRAINT fk_content_lyric_section_lyrics_revision_id FOREIGN KEY (lyrics_revision_id) REFERENCES content.lyrics_revision (lyrics_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.lyric_line ADD CONSTRAINT fk_content_lyric_line_section_id FOREIGN KEY (section_id) REFERENCES content.lyric_section (section_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.lyric_token ADD CONSTRAINT fk_content_lyric_token_line_id FOREIGN KEY (line_id) REFERENCES content.lyric_line (line_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.timing_revision ADD CONSTRAINT fk_content_timing_revision_lyrics_revision_id FOREIGN KEY (lyrics_revision_id) REFERENCES content.lyrics_revision (lyrics_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.timing_revision ADD CONSTRAINT fk_content_timing_revision_source_id FOREIGN KEY (source_id) REFERENCES catalog.recording_source (source_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.timing_segment ADD CONSTRAINT fk_content_timing_segment_timing_revision_id FOREIGN KEY (timing_revision_id) REFERENCES content.timing_revision (timing_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.timing_segment ADD CONSTRAINT fk_content_timing_segment_line_id FOREIGN KEY (line_id) REFERENCES content.lyric_line (line_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.translation_revision ADD CONSTRAINT fk_content_translation_revision_lyrics_revision_id FOREIGN KEY (lyrics_revision_id) REFERENCES content.lyrics_revision (lyrics_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.translation_revision ADD CONSTRAINT fk_content_translation_revision_parent_revision_id FOREIGN KEY (parent_revision_id) REFERENCES content.translation_revision (translation_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE content.translation_line ADD CONSTRAINT fk_content_translation_line_translation_revision_id FOREIGN KEY (translation_revision_id) REFERENCES content.translation_revision (translation_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.translation_line ADD CONSTRAINT fk_content_translation_line_line_id FOREIGN KEY (line_id) REFERENCES content.lyric_line (line_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.token_alignment ADD CONSTRAINT fk_content_token_alignment_translation_line_id FOREIGN KEY (translation_line_id) REFERENCES content.translation_line (translation_line_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.token_alignment ADD CONSTRAINT fk_content_token_alignment_token_id FOREIGN KEY (token_id) REFERENCES content.lyric_token (token_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.translation_note ADD CONSTRAINT fk_content_translation_note_translation_revision_id FOREIGN KEY (translation_revision_id) REFERENCES content.translation_revision (translation_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.translation_note ADD CONSTRAINT fk_content_translation_note_line_id FOREIGN KEY (line_id) REFERENCES content.lyric_line (line_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.translation_note ADD CONSTRAINT fk_content_translation_note_token_id FOREIGN KEY (token_id) REFERENCES content.lyric_token (token_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.translation_note ADD CONSTRAINT fk_content_translation_note_source_reference_id FOREIGN KEY (source_reference_id) REFERENCES catalog.source_reference (source_reference_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.linguistic_analysis_revision ADD CONSTRAINT fk_content_linguistic_analysis_revision_lyrics_revision_id FOREIGN KEY (lyrics_revision_id) REFERENCES content.lyrics_revision (lyrics_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.linguistic_analysis_revision ADD CONSTRAINT fk_content_linguistic_analysis_revision_parent_revision_id FOREIGN KEY (parent_revision_id) REFERENCES content.linguistic_analysis_revision (analysis_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE content.token_reading ADD CONSTRAINT fk_content_token_reading_analysis_revision_id FOREIGN KEY (analysis_revision_id) REFERENCES content.linguistic_analysis_revision (analysis_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.token_reading ADD CONSTRAINT fk_content_token_reading_token_id FOREIGN KEY (token_id) REFERENCES content.lyric_token (token_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.vocabulary_sense ADD CONSTRAINT fk_content_vocabulary_sense_vocabulary_id FOREIGN KEY (vocabulary_id) REFERENCES content.vocabulary_entry (vocabulary_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.vocabulary_occurrence ADD CONSTRAINT fk_content_vocabulary_occurrence_analysis_revision_id FOREIGN KEY (analysis_revision_id) REFERENCES content.linguistic_analysis_revision (analysis_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.vocabulary_occurrence ADD CONSTRAINT fk_content_vocabulary_occurrence_token_id FOREIGN KEY (token_id) REFERENCES content.lyric_token (token_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.vocabulary_occurrence ADD CONSTRAINT fk_content_vocabulary_occurrence_vocabulary_id FOREIGN KEY (vocabulary_id) REFERENCES content.vocabulary_entry (vocabulary_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.kanji_reading ADD CONSTRAINT fk_content_kanji_reading_kanji_id FOREIGN KEY (kanji_id) REFERENCES content.kanji_entry (kanji_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.kanji_occurrence ADD CONSTRAINT fk_content_kanji_occurrence_analysis_revision_id FOREIGN KEY (analysis_revision_id) REFERENCES content.linguistic_analysis_revision (analysis_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.kanji_occurrence ADD CONSTRAINT fk_content_kanji_occurrence_token_id FOREIGN KEY (token_id) REFERENCES content.lyric_token (token_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.kanji_occurrence ADD CONSTRAINT fk_content_kanji_occurrence_kanji_id FOREIGN KEY (kanji_id) REFERENCES content.kanji_entry (kanji_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.grammar_explanation ADD CONSTRAINT fk_content_grammar_explanation_grammar_point_id FOREIGN KEY (grammar_point_id) REFERENCES content.grammar_point (grammar_point_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.grammar_occurrence ADD CONSTRAINT fk_content_grammar_occurrence_analysis_revision_id FOREIGN KEY (analysis_revision_id) REFERENCES content.linguistic_analysis_revision (analysis_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.grammar_occurrence ADD CONSTRAINT fk_content_grammar_occurrence_grammar_point_id FOREIGN KEY (grammar_point_id) REFERENCES content.grammar_point (grammar_point_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.grammar_occurrence ADD CONSTRAINT fk_content_grammar_occurrence_line_id FOREIGN KEY (line_id) REFERENCES content.lyric_line (line_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.morphology_annotation ADD CONSTRAINT fk_content_morphology_annotation_analysis_revision_id FOREIGN KEY (analysis_revision_id) REFERENCES content.linguistic_analysis_revision (analysis_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE content.morphology_annotation ADD CONSTRAINT fk_content_morphology_annotation_token_id FOREIGN KEY (token_id) REFERENCES content.lyric_token (token_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.learner_profile ADD CONSTRAINT fk_learning_learner_profile_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.study_session ADD CONSTRAINT fk_learning_study_session_learner_profile_id FOREIGN KEY (learner_profile_id) REFERENCES learning.learner_profile (learner_profile_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.study_session ADD CONSTRAINT fk_learning_study_session_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.study_session ADD CONSTRAINT fk_learning_study_session_publication_id FOREIGN KEY (publication_id) REFERENCES editorial.publication (publication_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.study_activity ADD CONSTRAINT fk_learning_study_activity_study_session_id FOREIGN KEY (study_session_id) REFERENCES learning.study_session (study_session_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.exercise_definition ADD CONSTRAINT fk_learning_exercise_definition_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.exercise_definition ADD CONSTRAINT fk_learning_exercise_definition_line_id FOREIGN KEY (line_id) REFERENCES content.lyric_line (line_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.exercise_definition ADD CONSTRAINT fk_learning_exercise_definition_competency_id FOREIGN KEY (competency_id) REFERENCES learning.competency (competency_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.exercise_revision ADD CONSTRAINT fk_learning_exercise_revision_exercise_id FOREIGN KEY (exercise_id) REFERENCES learning.exercise_definition (exercise_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.exercise_item ADD CONSTRAINT fk_learning_exercise_item_exercise_revision_id FOREIGN KEY (exercise_revision_id) REFERENCES learning.exercise_revision (exercise_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.exercise_instance ADD CONSTRAINT fk_learning_exercise_instance_study_session_id FOREIGN KEY (study_session_id) REFERENCES learning.study_session (study_session_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.exercise_instance ADD CONSTRAINT fk_learning_exercise_instance_exercise_revision_id FOREIGN KEY (exercise_revision_id) REFERENCES learning.exercise_revision (exercise_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.exercise_instance_item ADD CONSTRAINT fk_learning_exercise_instance_item_instance_id FOREIGN KEY (instance_id) REFERENCES learning.exercise_instance (instance_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.exercise_instance_item ADD CONSTRAINT fk_learning_exercise_instance_item_source_item_id FOREIGN KEY (source_item_id) REFERENCES learning.exercise_item (exercise_item_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.answer_submission ADD CONSTRAINT fk_learning_answer_submission_instance_id FOREIGN KEY (instance_id) REFERENCES learning.exercise_instance (instance_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.answer_value ADD CONSTRAINT fk_learning_answer_value_submission_id FOREIGN KEY (submission_id) REFERENCES learning.answer_submission (submission_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.answer_value ADD CONSTRAINT fk_learning_answer_value_instance_item_id FOREIGN KEY (instance_item_id) REFERENCES learning.exercise_instance_item (instance_item_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.answer_value ADD CONSTRAINT fk_learning_answer_value_selected_item_id FOREIGN KEY (selected_item_id) REFERENCES learning.exercise_instance_item (instance_item_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.evaluation_result ADD CONSTRAINT fk_learning_evaluation_result_submission_id FOREIGN KEY (submission_id) REFERENCES learning.answer_submission (submission_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.feedback_item ADD CONSTRAINT fk_learning_feedback_item_evaluation_id FOREIGN KEY (evaluation_id) REFERENCES learning.evaluation_result (evaluation_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.feedback_item ADD CONSTRAINT fk_learning_feedback_item_item_id FOREIGN KEY (item_id) REFERENCES learning.exercise_instance_item (instance_item_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.learning_evidence ADD CONSTRAINT fk_learning_learning_evidence_learner_profile_id FOREIGN KEY (learner_profile_id) REFERENCES learning.learner_profile (learner_profile_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.learning_evidence ADD CONSTRAINT fk_learning_learning_evidence_evaluation_id FOREIGN KEY (evaluation_id) REFERENCES learning.evaluation_result (evaluation_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.learning_evidence ADD CONSTRAINT fk_learning_learning_evidence_competency_id FOREIGN KEY (competency_id) REFERENCES learning.competency (competency_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.learning_evidence ADD CONSTRAINT fk_learning_learning_evidence_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.learning_evidence ADD CONSTRAINT fk_learning_learning_evidence_superseded_by FOREIGN KEY (superseded_by) REFERENCES learning.learning_evidence (evidence_id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE learning.evidence_correction ADD CONSTRAINT fk_learning_evidence_correction_original_evidence_id FOREIGN KEY (original_evidence_id) REFERENCES learning.learning_evidence (evidence_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.evidence_correction ADD CONSTRAINT fk_learning_evidence_correction_replacement_evidence_id FOREIGN KEY (replacement_evidence_id) REFERENCES learning.learning_evidence (evidence_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.evidence_correction ADD CONSTRAINT fk_learning_evidence_correction_corrected_by FOREIGN KEY (corrected_by) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.study_session_snapshot ADD CONSTRAINT fk_learning_study_session_snapshot_study_session_id FOREIGN KEY (study_session_id) REFERENCES learning.study_session (study_session_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.study_session_snapshot ADD CONSTRAINT fk_learning_study_session_snapshot_last_activity_id FOREIGN KEY (last_activity_id) REFERENCES learning.study_activity (activity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE learning.study_session_snapshot ADD CONSTRAINT fk_learning_study_session_snapshot_last_instance_id FOREIGN KEY (last_instance_id) REFERENCES learning.exercise_instance (instance_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.song_progress ADD CONSTRAINT fk_progress_song_progress_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.song_progress ADD CONSTRAINT fk_progress_song_progress_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.song_progress ADD CONSTRAINT fk_progress_song_progress_current_derivation_id FOREIGN KEY (current_derivation_id) REFERENCES progress.progress_derivation (derivation_id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE progress.progress_derivation ADD CONSTRAINT fk_progress_progress_derivation_song_progress_id FOREIGN KEY (song_progress_id) REFERENCES progress.song_progress (song_progress_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.progress_derivation ADD CONSTRAINT fk_progress_progress_derivation_supersedes_id FOREIGN KEY (supersedes_id) REFERENCES progress.progress_derivation (derivation_id) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE progress.progress_contribution ADD CONSTRAINT fk_progress_progress_contribution_derivation_id FOREIGN KEY (derivation_id) REFERENCES progress.progress_derivation (derivation_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.progress_contribution ADD CONSTRAINT fk_progress_progress_contribution_evidence_id FOREIGN KEY (evidence_id) REFERENCES learning.learning_evidence (evidence_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.competency_progress ADD CONSTRAINT fk_progress_competency_progress_song_progress_id FOREIGN KEY (song_progress_id) REFERENCES progress.song_progress (song_progress_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.competency_progress ADD CONSTRAINT fk_progress_competency_progress_competency_id FOREIGN KEY (competency_id) REFERENCES learning.competency (competency_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.competency_progress ADD CONSTRAINT fk_progress_competency_progress_derivation_id FOREIGN KEY (derivation_id) REFERENCES progress.progress_derivation (derivation_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.resume_point ADD CONSTRAINT fk_progress_resume_point_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.resume_point ADD CONSTRAINT fk_progress_resume_point_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.resume_point ADD CONSTRAINT fk_progress_resume_point_study_session_id FOREIGN KEY (study_session_id) REFERENCES learning.study_session (study_session_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.resume_point ADD CONSTRAINT fk_progress_resume_point_line_id FOREIGN KEY (line_id) REFERENCES content.lyric_line (line_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.resume_point ADD CONSTRAINT fk_progress_resume_point_instance_id FOREIGN KEY (instance_id) REFERENCES learning.exercise_instance (instance_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.progress_history ADD CONSTRAINT fk_progress_progress_history_song_progress_id FOREIGN KEY (song_progress_id) REFERENCES progress.song_progress (song_progress_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.progress_history ADD CONSTRAINT fk_progress_progress_history_derivation_id FOREIGN KEY (derivation_id) REFERENCES progress.progress_derivation (derivation_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE progress.learner_progress_projection ADD CONSTRAINT fk_progress_learner_progress_projection_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.rights_record ADD CONSTRAINT fk_editorial_rights_record_rights_holder_id FOREIGN KEY (rights_holder_id) REFERENCES editorial.rights_holder (rights_holder_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.rights_record ADD CONSTRAINT fk_editorial_rights_record_evidence_object_id FOREIGN KEY (evidence_object_id) REFERENCES ops.stored_object (object_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.rights_scope ADD CONSTRAINT fk_editorial_rights_scope_rights_record_id FOREIGN KEY (rights_record_id) REFERENCES editorial.rights_record (rights_record_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.provenance_record ADD CONSTRAINT fk_editorial_provenance_record_source_reference_id FOREIGN KEY (source_reference_id) REFERENCES catalog.source_reference (source_reference_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.provenance_record ADD CONSTRAINT fk_editorial_provenance_record_recorded_by FOREIGN KEY (recorded_by) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.editorial_package ADD CONSTRAINT fk_editorial_editorial_package_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.editorial_package ADD CONSTRAINT fk_editorial_editorial_package_created_by FOREIGN KEY (created_by) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.package_component ADD CONSTRAINT fk_editorial_package_component_package_id FOREIGN KEY (package_id) REFERENCES editorial.editorial_package (package_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.package_component ADD CONSTRAINT fk_editorial_package_component_lyrics_revision_id FOREIGN KEY (lyrics_revision_id) REFERENCES content.lyrics_revision (lyrics_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.package_component ADD CONSTRAINT fk_editorial_package_component_timing_revision_id FOREIGN KEY (timing_revision_id) REFERENCES content.timing_revision (timing_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.package_component ADD CONSTRAINT fk_editorial_package_component_translation_revision_id FOREIGN KEY (translation_revision_id) REFERENCES content.translation_revision (translation_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.package_component ADD CONSTRAINT fk_editorial_package_component_analysis_revision_id FOREIGN KEY (analysis_revision_id) REFERENCES content.linguistic_analysis_revision (analysis_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.package_component ADD CONSTRAINT fk_editorial_package_component_exercise_revision_id FOREIGN KEY (exercise_revision_id) REFERENCES learning.exercise_revision (exercise_revision_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.review_submission ADD CONSTRAINT fk_editorial_review_submission_package_id FOREIGN KEY (package_id) REFERENCES editorial.editorial_package (package_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.review_submission ADD CONSTRAINT fk_editorial_review_submission_submitted_by FOREIGN KEY (submitted_by) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.review_assignment ADD CONSTRAINT fk_editorial_review_assignment_submission_id FOREIGN KEY (submission_id) REFERENCES editorial.review_submission (submission_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.review_assignment ADD CONSTRAINT fk_editorial_review_assignment_reviewer_id FOREIGN KEY (reviewer_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.review_decision ADD CONSTRAINT fk_editorial_review_decision_submission_id FOREIGN KEY (submission_id) REFERENCES editorial.review_submission (submission_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.review_decision ADD CONSTRAINT fk_editorial_review_decision_assignment_id FOREIGN KEY (assignment_id) REFERENCES editorial.review_assignment (assignment_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.publication ADD CONSTRAINT fk_editorial_publication_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.publication ADD CONSTRAINT fk_editorial_publication_package_id FOREIGN KEY (package_id) REFERENCES editorial.editorial_package (package_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.publication ADD CONSTRAINT fk_editorial_publication_published_by FOREIGN KEY (published_by) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.publication_component ADD CONSTRAINT fk_editorial_publication_component_publication_id FOREIGN KEY (publication_id) REFERENCES editorial.publication (publication_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.publication_component ADD CONSTRAINT fk_editorial_publication_component_source_component_id FOREIGN KEY (source_component_id) REFERENCES editorial.package_component (package_component_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.publication_availability ADD CONSTRAINT fk_editorial_publication_availability_publication_id FOREIGN KEY (publication_id) REFERENCES editorial.publication (publication_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.correction_case ADD CONSTRAINT fk_editorial_correction_case_publication_id FOREIGN KEY (publication_id) REFERENCES editorial.publication (publication_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.correction_case ADD CONSTRAINT fk_editorial_correction_case_opened_by FOREIGN KEY (opened_by) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.publication_action ADD CONSTRAINT fk_editorial_publication_action_publication_id FOREIGN KEY (publication_id) REFERENCES editorial.publication (publication_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.publication_action ADD CONSTRAINT fk_editorial_publication_action_case_id FOREIGN KEY (case_id) REFERENCES editorial.correction_case (case_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.publication_action ADD CONSTRAINT fk_editorial_publication_action_actor_id FOREIGN KEY (actor_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.published_package_projection ADD CONSTRAINT fk_editorial_published_package_projection_publication_id FOREIGN KEY (publication_id) REFERENCES editorial.publication (publication_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.published_package_projection ADD CONSTRAINT fk_editorial_published_package_projection_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.published_package_projection ADD CONSTRAINT fk_editorial_published_package_projection_payload_ref FOREIGN KEY (payload_ref) REFERENCES ops.stored_object (object_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE editorial.editorial_lock ADD CONSTRAINT fk_editorial_editorial_lock_recording_id FOREIGN KEY (recording_id) REFERENCES catalog.recording (recording_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE configuration.catalog_entry ADD CONSTRAINT fk_configuration_catalog_entry_catalog_definition_id FOREIGN KEY (catalog_definition_id) REFERENCES configuration.catalog_definition (catalog_definition_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE configuration.parameter_version ADD CONSTRAINT fk_configuration_parameter_version_parameter_definition_id FOREIGN KEY (parameter_definition_id) REFERENCES configuration.parameter_definition (parameter_definition_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE configuration.configuration_change_set ADD CONSTRAINT fk_configuration_configuration_change_set_created_by FOREIGN KEY (created_by) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE configuration.configuration_change_set ADD CONSTRAINT fk_configuration_configuration_change_set_approved_by FOREIGN KEY (approved_by) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE configuration.configuration_change_item ADD CONSTRAINT fk_configuration_configuration_change_item_change_set_id FOREIGN KEY (change_set_id) REFERENCES configuration.configuration_change_set (change_set_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE configuration.configuration_change_item ADD CONSTRAINT fk_configuration_configuration_change_item_catalog_entry_id FOREIGN KEY (catalog_entry_id) REFERENCES configuration.catalog_entry (catalog_entry_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE configuration.configuration_change_item ADD CONSTRAINT fk_configuration_configuration_change_item_parameter_version_id FOREIGN KEY (parameter_version_id) REFERENCES configuration.parameter_version (parameter_version_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE configuration.configuration_activation ADD CONSTRAINT fk_configuration_configuration_activation_change_set_id FOREIGN KEY (change_set_id) REFERENCES configuration.configuration_change_set (change_set_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE configuration.configuration_activation ADD CONSTRAINT fk_configuration_configuration_activation_applied_by FOREIGN KEY (applied_by) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE configuration.effective_parameter ADD CONSTRAINT fk_configuration_effective_parameter_parameter_version_id FOREIGN KEY (parameter_version_id) REFERENCES configuration.parameter_version (parameter_version_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ops.inbox_message ADD CONSTRAINT fk_ops_inbox_message_event_id FOREIGN KEY (event_id) REFERENCES ops.outbox_message (event_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ops.idempotency_record ADD CONSTRAINT fk_ops_idempotency_record_account_id FOREIGN KEY (account_id) REFERENCES security.account (account_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ops.job_attempt ADD CONSTRAINT fk_ops_job_attempt_job_id FOREIGN KEY (job_id) REFERENCES ops.background_job (job_id) ON UPDATE RESTRICT ON DELETE RESTRICT;

-- 5. Unicidad lógica
CREATE UNIQUE INDEX ux_identity_preference_set_01 ON identity.preference_set (account_id);
CREATE UNIQUE INDEX ux_identity_preference_revision_01 ON identity.preference_revision (preference_set_id, revision_no);
CREATE UNIQUE INDEX ux_security_account_01 ON security.account (email_lookup_hash);
CREATE UNIQUE INDEX ux_security_credential_01 ON security.credential (account_id) WHERE active;
CREATE UNIQUE INDEX ux_security_account_verification_01 ON security.account_verification (token_hash);
CREATE UNIQUE INDEX ux_security_recovery_token_01 ON security.recovery_token (token_hash);
CREATE UNIQUE INDEX ux_security_session_01 ON security.session (session_hash);
CREATE UNIQUE INDEX ux_security_role_01 ON security.role (role_code);
CREATE UNIQUE INDEX ux_security_permission_01 ON security.permission (permission_code);
CREATE UNIQUE INDEX ux_catalog_artist_alias_01 ON catalog.artist_alias (artist_id, normalized_text, language_tag);
CREATE UNIQUE INDEX ux_catalog_work_title_01 ON catalog.work_title (work_id, normalized_text, language_tag, title_type);
CREATE UNIQUE INDEX ux_catalog_recording_credit_01 ON catalog.recording_credit (recording_id, display_order);
CREATE UNIQUE INDEX ux_content_lyrics_revision_01 ON content.lyrics_revision (recording_id, revision_no);
CREATE UNIQUE INDEX ux_content_lyric_section_01 ON content.lyric_section (lyrics_revision_id, display_order);
CREATE UNIQUE INDEX ux_content_lyric_line_01 ON content.lyric_line (section_id, line_no);
CREATE UNIQUE INDEX ux_content_lyric_token_01 ON content.lyric_token (line_id, token_no);
CREATE UNIQUE INDEX ux_content_timing_revision_01 ON content.timing_revision (lyrics_revision_id, source_id, revision_no);
CREATE UNIQUE INDEX ux_content_timing_segment_01 ON content.timing_segment (timing_revision_id, display_order);
CREATE UNIQUE INDEX ux_content_translation_revision_01 ON content.translation_revision (lyrics_revision_id, target_language, translation_type, revision_no);
CREATE UNIQUE INDEX ux_content_translation_line_01 ON content.translation_line (translation_revision_id, line_id, variant_code);
CREATE UNIQUE INDEX ux_content_token_reading_01 ON content.token_reading (analysis_revision_id, token_id, reading_type);
CREATE UNIQUE INDEX ux_content_linguistic_analysis_revision_01 ON content.linguistic_analysis_revision (lyrics_revision_id, revision_no);
CREATE UNIQUE INDEX ux_content_vocabulary_entry_01 ON content.vocabulary_entry (lemma, reading, part_of_speech, sense_key);
CREATE UNIQUE INDEX ux_content_vocabulary_sense_01 ON content.vocabulary_sense (vocabulary_id, language_tag, display_order);
CREATE UNIQUE INDEX ux_content_vocabulary_occurrence_01 ON content.vocabulary_occurrence (analysis_revision_id, token_id, vocabulary_id);
CREATE UNIQUE INDEX ux_content_kanji_entry_01 ON content.kanji_entry (character);
CREATE UNIQUE INDEX ux_content_kanji_reading_01 ON content.kanji_reading (kanji_id, reading, reading_type, language_tag);
CREATE UNIQUE INDEX ux_content_kanji_occurrence_01 ON content.kanji_occurrence (analysis_revision_id, token_id, kanji_id, char_offset);
CREATE UNIQUE INDEX ux_content_grammar_point_01 ON content.grammar_point (grammar_code);
CREATE UNIQUE INDEX ux_content_grammar_explanation_01 ON content.grammar_explanation (grammar_point_id, language_tag, revision_no);
CREATE UNIQUE INDEX ux_content_morphology_annotation_01 ON content.morphology_annotation (analysis_revision_id, token_id);
CREATE UNIQUE INDEX ux_learning_learner_profile_01 ON learning.learner_profile (account_id);
CREATE UNIQUE INDEX ux_learning_competency_01 ON learning.competency (competency_code);
CREATE UNIQUE INDEX ux_learning_study_activity_01 ON learning.study_activity (study_session_id, sequence_no);
CREATE UNIQUE INDEX ux_learning_exercise_definition_01 ON learning.exercise_definition (recording_id, line_id, exercise_type, competency_id) NULLS NOT DISTINCT;
CREATE UNIQUE INDEX ux_learning_exercise_revision_01 ON learning.exercise_revision (exercise_id, revision_no);
CREATE UNIQUE INDEX ux_learning_exercise_item_01 ON learning.exercise_item (exercise_revision_id, item_order);
CREATE UNIQUE INDEX ux_learning_exercise_instance_01 ON learning.exercise_instance (study_session_id, instance_no);
CREATE UNIQUE INDEX ux_learning_exercise_instance_item_01 ON learning.exercise_instance_item (instance_id, display_order);
CREATE UNIQUE INDEX ux_learning_answer_submission_01 ON learning.answer_submission (instance_id, submission_no);
CREATE UNIQUE INDEX ux_learning_answer_submission_02 ON learning.answer_submission (instance_id, idempotency_key);
CREATE UNIQUE INDEX ux_learning_answer_value_01 ON learning.answer_value (submission_id, instance_item_id);
CREATE UNIQUE INDEX ux_learning_evaluation_result_01 ON learning.evaluation_result (submission_id);
CREATE UNIQUE INDEX ux_learning_feedback_item_01 ON learning.feedback_item (evaluation_id, display_order);
CREATE UNIQUE INDEX ux_learning_learning_evidence_01 ON learning.learning_evidence (evaluation_id, competency_id);
CREATE UNIQUE INDEX ux_progress_song_progress_01 ON progress.song_progress (account_id, recording_id);
CREATE UNIQUE INDEX ux_progress_competency_progress_01 ON progress.competency_progress (derivation_id, competency_id);
CREATE UNIQUE INDEX ux_progress_resume_point_01 ON progress.resume_point (account_id, recording_id);
CREATE UNIQUE INDEX ux_editorial_rights_scope_01 ON editorial.rights_scope (rights_record_id, territory_code, language_tag, channel_code, use_code) NULLS NOT DISTINCT;
CREATE UNIQUE INDEX ux_editorial_provenance_record_01 ON editorial.provenance_record (object_type, object_id, source_reference_id, contribution_type);
CREATE UNIQUE INDEX ux_editorial_editorial_package_01 ON editorial.editorial_package (recording_id, package_no);
CREATE UNIQUE INDEX ux_editorial_package_component_01 ON editorial.package_component (package_id, component_kind, lyrics_revision_id, timing_revision_id, translation_revision_id, analysis_revision_id, exercise_revision_id) NULLS NOT DISTINCT;
CREATE UNIQUE INDEX ux_editorial_review_submission_01 ON editorial.review_submission (package_id) WHERE status_code IN ('SUBMITTED','IN_REVIEW');
CREATE UNIQUE INDEX ux_editorial_review_assignment_01 ON editorial.review_assignment (submission_id, reviewer_id, scope_code);
CREATE UNIQUE INDEX ux_editorial_review_decision_01 ON editorial.review_decision (assignment_id);
CREATE UNIQUE INDEX ux_editorial_publication_01 ON editorial.publication (recording_id, publication_no);
CREATE UNIQUE INDEX ux_editorial_publication_component_01 ON editorial.publication_component (publication_id, display_order);
CREATE UNIQUE INDEX ux_editorial_correction_case_01 ON editorial.correction_case (publication_id, case_type) WHERE status_code NOT IN ('RESOLVED','REJECTED','CLOSED');
CREATE UNIQUE INDEX ux_editorial_publication_action_01 ON editorial.publication_action (correlation_id, action_code);
CREATE UNIQUE INDEX ux_editorial_editorial_lock_01 ON editorial.editorial_lock (recording_id, operation_code);
CREATE UNIQUE INDEX ux_configuration_catalog_definition_01 ON configuration.catalog_definition (catalog_code);
CREATE UNIQUE INDEX ux_configuration_parameter_definition_01 ON configuration.parameter_definition (parameter_key);
CREATE UNIQUE INDEX ux_configuration_parameter_version_01 ON configuration.parameter_version (parameter_definition_id, version_no);
CREATE UNIQUE INDEX ux_configuration_configuration_activation_01 ON configuration.configuration_activation (change_set_id, action_code, effective_at);
CREATE UNIQUE INDEX ux_configuration_effective_parameter_01 ON configuration.effective_parameter (parameter_key, scope_code, scope_value) NULLS NOT DISTINCT;
CREATE UNIQUE INDEX ux_configuration_retention_policy_01 ON configuration.retention_policy (data_class, purpose_code, valid_from);
CREATE UNIQUE INDEX ux_ops_idempotency_record_01 ON ops.idempotency_record (account_id, operation_code, idempotency_key) NULLS NOT DISTINCT;
CREATE UNIQUE INDEX ux_ops_job_attempt_01 ON ops.job_attempt (job_id, attempt_no);
CREATE UNIQUE INDEX ux_ops_stored_object_01 ON ops.stored_object (storage_key);
CREATE UNIQUE INDEX ux_ops_data_quality_issue_01 ON ops.data_quality_issue (owner_module, rule_code, object_type, object_id) WHERE status_code IN ('OPEN','ACKNOWLEDGED');

-- 6. Vigencias no solapadas
ALTER TABLE security.role_permission ADD CONSTRAINT ex_role_permission_validity EXCLUDE USING gist (role_id WITH =, permission_id WITH =, tstzrange(valid_from, valid_to, '[)') WITH &&);
ALTER TABLE security.role_assignment ADD CONSTRAINT ex_role_assignment_validity EXCLUDE USING gist (account_id WITH =, role_id WITH =, (coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid)) WITH =, tstzrange(valid_from, valid_to, '[)') WITH &&);
ALTER TABLE security.audit_seal ADD CONSTRAINT ex_audit_seal_range EXCLUDE USING gist (tstzrange(range_start, range_end, '[)') WITH &&);
ALTER TABLE editorial.publication ADD CONSTRAINT ex_publication_active_range EXCLUDE USING gist (recording_id WITH =, tstzrange(active_from, active_to, '[)') WITH &&) WHERE (status_code IN ('SCHEDULED','ACTIVE'));
ALTER TABLE editorial.publication_availability ADD CONSTRAINT ex_publication_availability_range EXCLUDE USING gist (publication_id WITH =, territory_code WITH =, (coalesce(language_tag, '*')) WITH =, audience_code WITH =, tstzrange(valid_from, valid_to, '[)') WITH &&) WHERE (status_code = 'ACTIVE');
ALTER TABLE configuration.catalog_entry ADD CONSTRAINT ex_catalog_entry_validity EXCLUDE USING gist (catalog_definition_id WITH =, entry_code WITH =, tstzrange(valid_from, valid_to, '[)') WITH &&) WHERE (status_code IN ('ACTIVE','SCHEDULED'));
ALTER TABLE configuration.parameter_version ADD CONSTRAINT ex_parameter_version_validity EXCLUDE USING gist (parameter_definition_id WITH =, scope_code WITH =, (coalesce(scope_value, '*')) WITH =, tstzrange(valid_from, valid_to, '[)') WITH &&) WHERE (status_code IN ('ACTIVE','SCHEDULED'));
ALTER TABLE configuration.business_calendar ADD CONSTRAINT ex_business_calendar_validity EXCLUDE USING gist (calendar_code WITH =, tstzrange(valid_from, valid_to, '[)') WITH &&);

-- 7. Índices de FK y rutas calientes
CREATE INDEX ix_identity_preference_set_account_id ON identity.preference_set (account_id);
CREATE INDEX ix_identity_preference_set_current_revision_id ON identity.preference_set (current_revision_id);
CREATE INDEX ix_identity_preference_revision_created_by ON identity.preference_revision (created_by);
CREATE INDEX ix_identity_consent_record_account_id ON identity.consent_record (account_id);
CREATE INDEX ix_identity_privacy_request_account_id ON identity.privacy_request (account_id);
CREATE INDEX ix_security_credential_account_id ON security.credential (account_id);
CREATE INDEX ix_security_account_verification_account_id ON security.account_verification (account_id);
CREATE INDEX ix_security_recovery_token_account_id ON security.recovery_token (account_id);
CREATE INDEX ix_security_session_account_id ON security.session (account_id);
CREATE INDEX ix_security_mfa_method_account_id ON security.mfa_method (account_id);
CREATE INDEX ix_security_role_permission_role_id ON security.role_permission (role_id);
CREATE INDEX ix_security_role_permission_permission_id ON security.role_permission (permission_id);
CREATE INDEX ix_security_role_permission_granted_by ON security.role_permission (granted_by);
CREATE INDEX ix_security_role_assignment_account_id ON security.role_assignment (account_id);
CREATE INDEX ix_security_role_assignment_role_id ON security.role_assignment (role_id);
CREATE INDEX ix_security_role_assignment_scope_id ON security.role_assignment (scope_id);
CREATE INDEX ix_security_security_event_account_id ON security.security_event (account_id);
CREATE INDEX ix_security_audit_event_actor_id ON security.audit_event (actor_id);
CREATE INDEX ix_security_audit_seal_object_id ON security.audit_seal (object_id);
CREATE INDEX ix_catalog_artist_alias_artist_id ON catalog.artist_alias (artist_id);
CREATE INDEX ix_catalog_work_title_work_id ON catalog.work_title (work_id);
CREATE INDEX ix_catalog_work_artist_work_id ON catalog.work_artist (work_id);
CREATE INDEX ix_catalog_work_artist_artist_id ON catalog.work_artist (artist_id);
CREATE INDEX ix_catalog_recording_work_id ON catalog.recording (work_id);
CREATE INDEX ix_catalog_recording_source_recording_id ON catalog.recording_source (recording_id);
CREATE INDEX ix_catalog_recording_credit_recording_id ON catalog.recording_credit (recording_id);
CREATE INDEX ix_catalog_recording_credit_artist_id ON catalog.recording_credit (artist_id);
CREATE INDEX ix_catalog_recording_status_history_recording_id ON catalog.recording_status_history (recording_id);
CREATE INDEX ix_catalog_recording_status_history_changed_by ON catalog.recording_status_history (changed_by);
CREATE INDEX ix_catalog_song_search_document_publication_id ON catalog.song_search_document (publication_id);
CREATE INDEX ix_content_lyrics_revision_recording_id ON content.lyrics_revision (recording_id);
CREATE INDEX ix_content_lyrics_revision_parent_revision_id ON content.lyrics_revision (parent_revision_id);
CREATE INDEX ix_content_lyrics_revision_created_by ON content.lyrics_revision (created_by);
CREATE INDEX ix_content_lyric_section_lyrics_revision_id ON content.lyric_section (lyrics_revision_id);
CREATE INDEX ix_content_lyric_line_section_id ON content.lyric_line (section_id);
CREATE INDEX ix_content_lyric_token_line_id ON content.lyric_token (line_id);
CREATE INDEX ix_content_timing_revision_lyrics_revision_id ON content.timing_revision (lyrics_revision_id);
CREATE INDEX ix_content_timing_revision_source_id ON content.timing_revision (source_id);
CREATE INDEX ix_content_timing_segment_timing_revision_id ON content.timing_segment (timing_revision_id);
CREATE INDEX ix_content_timing_segment_line_id ON content.timing_segment (line_id);
CREATE INDEX ix_content_translation_revision_lyrics_revision_id ON content.translation_revision (lyrics_revision_id);
CREATE INDEX ix_content_translation_revision_parent_revision_id ON content.translation_revision (parent_revision_id);
CREATE INDEX ix_content_translation_line_translation_revision_id ON content.translation_line (translation_revision_id);
CREATE INDEX ix_content_translation_line_line_id ON content.translation_line (line_id);
CREATE INDEX ix_content_token_alignment_translation_line_id ON content.token_alignment (translation_line_id);
CREATE INDEX ix_content_token_alignment_token_id ON content.token_alignment (token_id);
CREATE INDEX ix_content_translation_note_translation_revision_id ON content.translation_note (translation_revision_id);
CREATE INDEX ix_content_translation_note_line_id ON content.translation_note (line_id);
CREATE INDEX ix_content_translation_note_token_id ON content.translation_note (token_id);
CREATE INDEX ix_content_translation_note_source_reference_id ON content.translation_note (source_reference_id);
CREATE INDEX ix_content_linguistic_analysis_revision_lyrics_revision_id ON content.linguistic_analysis_revision (lyrics_revision_id);
CREATE INDEX ix_content_linguistic_analysis_revision_parent_revision_id ON content.linguistic_analysis_revision (parent_revision_id);
CREATE INDEX ix_content_token_reading_analysis_revision_id ON content.token_reading (analysis_revision_id);
CREATE INDEX ix_content_token_reading_token_id ON content.token_reading (token_id);
CREATE INDEX ix_content_vocabulary_sense_vocabulary_id ON content.vocabulary_sense (vocabulary_id);
CREATE INDEX ix_content_vocabulary_occurrence_analysis_revision_id ON content.vocabulary_occurrence (analysis_revision_id);
CREATE INDEX ix_content_vocabulary_occurrence_token_id ON content.vocabulary_occurrence (token_id);
CREATE INDEX ix_content_vocabulary_occurrence_vocabulary_id ON content.vocabulary_occurrence (vocabulary_id);
CREATE INDEX ix_content_kanji_reading_kanji_id ON content.kanji_reading (kanji_id);
CREATE INDEX ix_content_kanji_occurrence_analysis_revision_id ON content.kanji_occurrence (analysis_revision_id);
CREATE INDEX ix_content_kanji_occurrence_token_id ON content.kanji_occurrence (token_id);
CREATE INDEX ix_content_kanji_occurrence_kanji_id ON content.kanji_occurrence (kanji_id);
CREATE INDEX ix_content_grammar_explanation_grammar_point_id ON content.grammar_explanation (grammar_point_id);
CREATE INDEX ix_content_grammar_occurrence_analysis_revision_id ON content.grammar_occurrence (analysis_revision_id);
CREATE INDEX ix_content_grammar_occurrence_grammar_point_id ON content.grammar_occurrence (grammar_point_id);
CREATE INDEX ix_content_grammar_occurrence_line_id ON content.grammar_occurrence (line_id);
CREATE INDEX ix_content_morphology_annotation_analysis_revision_id ON content.morphology_annotation (analysis_revision_id);
CREATE INDEX ix_content_morphology_annotation_token_id ON content.morphology_annotation (token_id);
CREATE INDEX ix_learning_learner_profile_account_id ON learning.learner_profile (account_id);
CREATE INDEX ix_learning_study_session_learner_profile_id ON learning.study_session (learner_profile_id);
CREATE INDEX ix_learning_study_session_recording_id ON learning.study_session (recording_id);
CREATE INDEX ix_learning_study_session_publication_id ON learning.study_session (publication_id);
CREATE INDEX ix_learning_study_activity_study_session_id ON learning.study_activity (study_session_id);
CREATE INDEX ix_learning_exercise_definition_recording_id ON learning.exercise_definition (recording_id);
CREATE INDEX ix_learning_exercise_definition_line_id ON learning.exercise_definition (line_id);
CREATE INDEX ix_learning_exercise_definition_competency_id ON learning.exercise_definition (competency_id);
CREATE INDEX ix_learning_exercise_revision_exercise_id ON learning.exercise_revision (exercise_id);
CREATE INDEX ix_learning_exercise_item_exercise_revision_id ON learning.exercise_item (exercise_revision_id);
CREATE INDEX ix_learning_exercise_instance_study_session_id ON learning.exercise_instance (study_session_id);
CREATE INDEX ix_learning_exercise_instance_exercise_revision_id ON learning.exercise_instance (exercise_revision_id);
CREATE INDEX ix_learning_exercise_instance_item_instance_id ON learning.exercise_instance_item (instance_id);
CREATE INDEX ix_learning_exercise_instance_item_source_item_id ON learning.exercise_instance_item (source_item_id);
CREATE INDEX ix_learning_answer_submission_instance_id ON learning.answer_submission (instance_id);
CREATE INDEX ix_learning_answer_value_submission_id ON learning.answer_value (submission_id);
CREATE INDEX ix_learning_answer_value_instance_item_id ON learning.answer_value (instance_item_id);
CREATE INDEX ix_learning_answer_value_selected_item_id ON learning.answer_value (selected_item_id);
CREATE INDEX ix_learning_evaluation_result_submission_id ON learning.evaluation_result (submission_id);
CREATE INDEX ix_learning_feedback_item_evaluation_id ON learning.feedback_item (evaluation_id);
CREATE INDEX ix_learning_feedback_item_item_id ON learning.feedback_item (item_id);
CREATE INDEX ix_learning_learning_evidence_learner_profile_id ON learning.learning_evidence (learner_profile_id);
CREATE INDEX ix_learning_learning_evidence_evaluation_id ON learning.learning_evidence (evaluation_id);
CREATE INDEX ix_learning_learning_evidence_competency_id ON learning.learning_evidence (competency_id);
CREATE INDEX ix_learning_learning_evidence_recording_id ON learning.learning_evidence (recording_id);
CREATE INDEX ix_learning_learning_evidence_superseded_by ON learning.learning_evidence (superseded_by);
CREATE INDEX ix_learning_evidence_correction_original_evidence_id ON learning.evidence_correction (original_evidence_id);
CREATE INDEX ix_learning_evidence_correction_replacement_evidence_id ON learning.evidence_correction (replacement_evidence_id);
CREATE INDEX ix_learning_evidence_correction_corrected_by ON learning.evidence_correction (corrected_by);
CREATE INDEX ix_learning_study_session_snapshot_last_activity_id ON learning.study_session_snapshot (last_activity_id);
CREATE INDEX ix_learning_study_session_snapshot_last_instance_id ON learning.study_session_snapshot (last_instance_id);
CREATE INDEX ix_progress_song_progress_account_id ON progress.song_progress (account_id);
CREATE INDEX ix_progress_song_progress_recording_id ON progress.song_progress (recording_id);
CREATE INDEX ix_progress_song_progress_current_derivation_id ON progress.song_progress (current_derivation_id);
CREATE INDEX ix_progress_progress_derivation_song_progress_id ON progress.progress_derivation (song_progress_id);
CREATE INDEX ix_progress_progress_derivation_supersedes_id ON progress.progress_derivation (supersedes_id);
CREATE INDEX ix_progress_progress_contribution_derivation_id ON progress.progress_contribution (derivation_id);
CREATE INDEX ix_progress_progress_contribution_evidence_id ON progress.progress_contribution (evidence_id);
CREATE INDEX ix_progress_competency_progress_song_progress_id ON progress.competency_progress (song_progress_id);
CREATE INDEX ix_progress_competency_progress_competency_id ON progress.competency_progress (competency_id);
CREATE INDEX ix_progress_competency_progress_derivation_id ON progress.competency_progress (derivation_id);
CREATE INDEX ix_progress_resume_point_account_id ON progress.resume_point (account_id);
CREATE INDEX ix_progress_resume_point_recording_id ON progress.resume_point (recording_id);
CREATE INDEX ix_progress_resume_point_study_session_id ON progress.resume_point (study_session_id);
CREATE INDEX ix_progress_resume_point_line_id ON progress.resume_point (line_id);
CREATE INDEX ix_progress_resume_point_instance_id ON progress.resume_point (instance_id);
CREATE INDEX ix_progress_progress_history_song_progress_id ON progress.progress_history (song_progress_id);
CREATE INDEX ix_progress_progress_history_derivation_id ON progress.progress_history (derivation_id);
CREATE INDEX ix_editorial_rights_record_rights_holder_id ON editorial.rights_record (rights_holder_id);
CREATE INDEX ix_editorial_rights_record_evidence_object_id ON editorial.rights_record (evidence_object_id);
CREATE INDEX ix_editorial_rights_scope_rights_record_id ON editorial.rights_scope (rights_record_id);
CREATE INDEX ix_editorial_provenance_record_source_reference_id ON editorial.provenance_record (source_reference_id);
CREATE INDEX ix_editorial_provenance_record_recorded_by ON editorial.provenance_record (recorded_by);
CREATE INDEX ix_editorial_editorial_package_recording_id ON editorial.editorial_package (recording_id);
CREATE INDEX ix_editorial_editorial_package_created_by ON editorial.editorial_package (created_by);
CREATE INDEX ix_editorial_package_component_package_id ON editorial.package_component (package_id);
CREATE INDEX ix_editorial_package_component_lyrics_revision_id ON editorial.package_component (lyrics_revision_id);
CREATE INDEX ix_editorial_package_component_timing_revision_id ON editorial.package_component (timing_revision_id);
CREATE INDEX ix_editorial_package_component_translation_revision_id ON editorial.package_component (translation_revision_id);
CREATE INDEX ix_editorial_package_component_analysis_revision_id ON editorial.package_component (analysis_revision_id);
CREATE INDEX ix_editorial_package_component_exercise_revision_id ON editorial.package_component (exercise_revision_id);
CREATE INDEX ix_editorial_review_submission_package_id ON editorial.review_submission (package_id);
CREATE INDEX ix_editorial_review_submission_submitted_by ON editorial.review_submission (submitted_by);
CREATE INDEX ix_editorial_review_assignment_submission_id ON editorial.review_assignment (submission_id);
CREATE INDEX ix_editorial_review_assignment_reviewer_id ON editorial.review_assignment (reviewer_id);
CREATE INDEX ix_editorial_review_decision_submission_id ON editorial.review_decision (submission_id);
CREATE INDEX ix_editorial_review_decision_assignment_id ON editorial.review_decision (assignment_id);
CREATE INDEX ix_editorial_publication_recording_id ON editorial.publication (recording_id);
CREATE INDEX ix_editorial_publication_package_id ON editorial.publication (package_id);
CREATE INDEX ix_editorial_publication_published_by ON editorial.publication (published_by);
CREATE INDEX ix_editorial_publication_component_publication_id ON editorial.publication_component (publication_id);
CREATE INDEX ix_editorial_publication_component_source_component_id ON editorial.publication_component (source_component_id);
CREATE INDEX ix_editorial_publication_availability_publication_id ON editorial.publication_availability (publication_id);
CREATE INDEX ix_editorial_correction_case_publication_id ON editorial.correction_case (publication_id);
CREATE INDEX ix_editorial_correction_case_opened_by ON editorial.correction_case (opened_by);
CREATE INDEX ix_editorial_publication_action_publication_id ON editorial.publication_action (publication_id);
CREATE INDEX ix_editorial_publication_action_case_id ON editorial.publication_action (case_id);
CREATE INDEX ix_editorial_publication_action_actor_id ON editorial.publication_action (actor_id);
CREATE INDEX ix_editorial_published_package_projection_recording_id ON editorial.published_package_projection (recording_id);
CREATE INDEX ix_editorial_published_package_projection_payload_ref ON editorial.published_package_projection (payload_ref);
CREATE INDEX ix_editorial_editorial_lock_recording_id ON editorial.editorial_lock (recording_id);
CREATE INDEX ix_configuration_catalog_entry_catalog_definition_id ON configuration.catalog_entry (catalog_definition_id);
CREATE INDEX ix_configuration_parameter_version_parameter_definition_id ON configuration.parameter_version (parameter_definition_id);
CREATE INDEX ix_configuration_configuration_change_set_created_by ON configuration.configuration_change_set (created_by);
CREATE INDEX ix_configuration_configuration_change_set_approved_by ON configuration.configuration_change_set (approved_by);
CREATE INDEX ix_configuration_configuration_change_item_change_set_id ON configuration.configuration_change_item (change_set_id);
CREATE INDEX ix_configuration_configuration_change_item_catalog_entry_id ON configuration.configuration_change_item (catalog_entry_id);
CREATE INDEX ix_configuration_configuration_change_item_parameter_version_id ON configuration.configuration_change_item (parameter_version_id);
CREATE INDEX ix_configuration_configuration_activation_change_set_id ON configuration.configuration_activation (change_set_id);
CREATE INDEX ix_configuration_configuration_activation_applied_by ON configuration.configuration_activation (applied_by);
CREATE INDEX ix_ops_inbox_message_event_id ON ops.inbox_message (event_id);
CREATE INDEX ix_ops_idempotency_record_account_id ON ops.idempotency_record (account_id);
CREATE INDEX ix_ops_job_attempt_job_id ON ops.job_attempt (job_id);
CREATE INDEX ix_account_status ON security.account (status_code, created_at DESC);
CREATE INDEX ix_session_account_expiry ON security.session (account_id, absolute_expires_at) WHERE revoked_at IS NULL;
CREATE INDEX ix_role_assignment_account ON security.role_assignment (account_id, valid_from, valid_to);
CREATE INDEX ix_security_event_account_time ON security.security_event (account_id, occurred_at DESC);
CREATE INDEX ix_audit_object_time ON security.audit_event (object_type, object_id, occurred_at DESC);
CREATE INDEX ix_audit_time ON security.audit_event (occurred_at DESC);
CREATE INDEX ix_artist_alias_trgm ON catalog.artist_alias USING gin (normalized_text public.gin_trgm_ops);
CREATE INDEX ix_work_title_trgm ON catalog.work_title USING gin (normalized_text public.gin_trgm_ops);
CREATE INDEX ix_song_search_vector ON catalog.song_search_document USING gin (search_vector);
CREATE INDEX ix_song_search_terms_trgm ON catalog.song_search_document USING gin (normalized_terms public.gin_trgm_ops);
CREATE INDEX ix_lyric_line_order ON content.lyric_line (section_id, line_no);
CREATE INDEX ix_timing_segment_seek ON content.timing_segment (timing_revision_id, start_ms, end_ms);
CREATE INDEX ix_translation_line_lookup ON content.translation_line (translation_revision_id, line_id, display_order);
CREATE INDEX ix_vocabulary_occurrence_token ON content.vocabulary_occurrence (token_id, analysis_revision_id);
CREATE INDEX ix_study_session_learner_status ON learning.study_session (learner_profile_id, status_code, started_at DESC);
CREATE INDEX ix_instance_session_state ON learning.exercise_instance (study_session_id, state_code, instance_no);
CREATE INDEX ix_submission_instance_time ON learning.answer_submission (instance_id, submitted_at DESC);
CREATE INDEX ix_evidence_learner_time ON learning.learning_evidence (learner_profile_id, confirmed_at DESC);
CREATE INDEX ix_song_progress_account_updated ON progress.song_progress (account_id, updated_at DESC);
CREATE INDEX ix_progress_history_song_time ON progress.progress_history (song_progress_id, occurred_at DESC);
CREATE INDEX ix_publication_recording_status ON editorial.publication (recording_id, status_code, active_from DESC);
CREATE INDEX ix_review_submission_package ON editorial.review_submission (package_id, status_code, submitted_at DESC);
CREATE INDEX ix_parameter_effective_lookup ON configuration.parameter_version (parameter_definition_id, scope_code, scope_value, valid_from DESC);
CREATE INDEX ix_outbox_claim ON ops.outbox_message (status_code, next_attempt_at, occurred_at) WHERE status_code IN ('PENDING','RETRY_WAIT');
CREATE INDEX ix_job_claim ON ops.background_job (status_code, next_attempt_at, scheduled_at) WHERE status_code IN ('PENDING','RETRY_WAIT');
CREATE INDEX ix_idempotency_expiry ON ops.idempotency_record (expires_at);
CREATE INDEX ix_quality_open ON ops.data_quality_issue (owner_module, severity_code, detected_at DESC) WHERE status_code IN ('OPEN','ACKNOWLEDGED');

-- 8. Triggers de concurrencia e inmutabilidad
CREATE TRIGGER tr_identity_user_profile_version BEFORE UPDATE ON identity.user_profile FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_identity_preference_set_version BEFORE UPDATE ON identity.preference_set FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_security_account_version BEFORE UPDATE ON security.account FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_security_role_version BEFORE UPDATE ON security.role FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_catalog_artist_version BEFORE UPDATE ON catalog.artist FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_catalog_musical_work_version BEFORE UPDATE ON catalog.musical_work FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_catalog_recording_version BEFORE UPDATE ON catalog.recording FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_catalog_recording_source_version BEFORE UPDATE ON catalog.recording_source FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_content_lyrics_revision_version BEFORE UPDATE ON content.lyrics_revision FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_content_vocabulary_entry_version BEFORE UPDATE ON content.vocabulary_entry FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_content_kanji_entry_version BEFORE UPDATE ON content.kanji_entry FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_content_grammar_point_version BEFORE UPDATE ON content.grammar_point FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_learning_learner_profile_version BEFORE UPDATE ON learning.learner_profile FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_learning_competency_version BEFORE UPDATE ON learning.competency FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_learning_study_session_version BEFORE UPDATE ON learning.study_session FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_learning_exercise_definition_version BEFORE UPDATE ON learning.exercise_definition FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_learning_exercise_revision_version BEFORE UPDATE ON learning.exercise_revision FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_learning_exercise_instance_version BEFORE UPDATE ON learning.exercise_instance FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_progress_song_progress_version BEFORE UPDATE ON progress.song_progress FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_progress_resume_point_version BEFORE UPDATE ON progress.resume_point FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_editorial_editorial_package_version BEFORE UPDATE ON editorial.editorial_package FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_configuration_catalog_definition_version BEFORE UPDATE ON configuration.catalog_definition FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_configuration_catalog_entry_version BEFORE UPDATE ON configuration.catalog_entry FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_configuration_configuration_change_set_version BEFORE UPDATE ON configuration.configuration_change_set FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_configuration_business_calendar_version BEFORE UPDATE ON configuration.business_calendar FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_configuration_retention_policy_version BEFORE UPDATE ON configuration.retention_policy FOR EACH ROW EXECUTE FUNCTION ops.bump_version();
CREATE TRIGGER tr_identity_consent_record_append_only BEFORE UPDATE OR DELETE ON identity.consent_record FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_security_security_event_append_only BEFORE UPDATE OR DELETE ON security.security_event FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_security_audit_event_append_only BEFORE UPDATE OR DELETE ON security.audit_event FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_security_audit_seal_append_only BEFORE UPDATE OR DELETE ON security.audit_seal FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_catalog_recording_status_history_append_only BEFORE UPDATE OR DELETE ON catalog.recording_status_history FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_learning_answer_submission_append_only BEFORE UPDATE OR DELETE ON learning.answer_submission FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_learning_answer_value_append_only BEFORE UPDATE OR DELETE ON learning.answer_value FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_learning_evaluation_result_append_only BEFORE UPDATE OR DELETE ON learning.evaluation_result FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_learning_feedback_item_append_only BEFORE UPDATE OR DELETE ON learning.feedback_item FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_learning_evidence_correction_append_only BEFORE UPDATE OR DELETE ON learning.evidence_correction FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_progress_progress_derivation_append_only BEFORE UPDATE OR DELETE ON progress.progress_derivation FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_progress_progress_contribution_append_only BEFORE UPDATE OR DELETE ON progress.progress_contribution FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_progress_competency_progress_append_only BEFORE UPDATE OR DELETE ON progress.competency_progress FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_progress_progress_history_append_only BEFORE UPDATE OR DELETE ON progress.progress_history FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_editorial_provenance_record_append_only BEFORE UPDATE OR DELETE ON editorial.provenance_record FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_editorial_review_decision_append_only BEFORE UPDATE OR DELETE ON editorial.review_decision FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_editorial_publication_component_append_only BEFORE UPDATE OR DELETE ON editorial.publication_component FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_editorial_publication_action_append_only BEFORE UPDATE OR DELETE ON editorial.publication_action FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_configuration_configuration_activation_append_only BEFORE UPDATE OR DELETE ON configuration.configuration_activation FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_ops_job_attempt_append_only BEFORE UPDATE OR DELETE ON ops.job_attempt FOR EACH ROW EXECUTE FUNCTION ops.prevent_mutation();
CREATE TRIGGER tr_content_lyrics_revision_terminal BEFORE UPDATE OR DELETE ON content.lyrics_revision FOR EACH ROW EXECUTE FUNCTION ops.guard_terminal_status();
CREATE TRIGGER tr_content_timing_revision_terminal BEFORE UPDATE OR DELETE ON content.timing_revision FOR EACH ROW EXECUTE FUNCTION ops.guard_terminal_status();
CREATE TRIGGER tr_content_translation_revision_terminal BEFORE UPDATE OR DELETE ON content.translation_revision FOR EACH ROW EXECUTE FUNCTION ops.guard_terminal_status();
CREATE TRIGGER tr_content_linguistic_analysis_revision_terminal BEFORE UPDATE OR DELETE ON content.linguistic_analysis_revision FOR EACH ROW EXECUTE FUNCTION ops.guard_terminal_status();
CREATE TRIGGER tr_learning_exercise_revision_terminal BEFORE UPDATE OR DELETE ON learning.exercise_revision FOR EACH ROW EXECUTE FUNCTION ops.guard_terminal_status();
CREATE TRIGGER tr_learning_evidence_correction BEFORE UPDATE OR DELETE ON learning.learning_evidence FOR EACH ROW EXECUTE FUNCTION ops.guard_evidence_mutation();
CREATE TRIGGER tr_package_component_mutable BEFORE INSERT OR UPDATE OR DELETE ON editorial.package_component FOR EACH ROW EXECUTE FUNCTION editorial.guard_package_component_mutable();

-- 9. Vistas públicas mínimas
CREATE OR REPLACE VIEW catalog.v_public_song AS
SELECT p.publication_id,
       r.recording_id,
       w.work_id,
       w.canonical_title,
       r.recording_title,
       r.duration_ms,
       p.active_from,
       p.active_to
FROM editorial.publication p
JOIN catalog.recording r ON r.recording_id = p.recording_id
JOIN catalog.musical_work w ON w.work_id = r.work_id
WHERE p.status_code = 'ACTIVE'
  AND p.active_from <= CURRENT_TIMESTAMP
  AND (p.active_to IS NULL OR p.active_to > CURRENT_TIMESTAMP);

CREATE OR REPLACE VIEW catalog.v_public_song_search AS
SELECT d.recording_id,
       d.publication_id,
       d.normalized_terms,
       d.search_vector,
       d.indexed_at
FROM catalog.song_search_document d
JOIN editorial.publication p ON p.publication_id = d.publication_id
WHERE p.status_code = 'ACTIVE'
  AND p.active_from <= CURRENT_TIMESTAMP
  AND (p.active_to IS NULL OR p.active_to > CURRENT_TIMESTAMP);

-- 10. Seguridad por fila para datos personales
ALTER TABLE identity.user_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.user_profile FORCE ROW LEVEL SECURITY;
CREATE POLICY p_user_profile_owner ON identity.user_profile TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_user_profile_backoffice ON identity.user_profile TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_user_profile_worker ON identity.user_profile TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE identity.preference_set ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.preference_set FORCE ROW LEVEL SECURITY;
CREATE POLICY p_preference_set_owner ON identity.preference_set TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_preference_set_backoffice ON identity.preference_set TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_preference_set_worker ON identity.preference_set TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE identity.preference_revision ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.preference_revision FORCE ROW LEVEL SECURITY;
CREATE POLICY p_preference_revision_owner ON identity.preference_revision TO jp_app USING (EXISTS (SELECT 1 FROM identity.preference_set p WHERE p.preference_set_id = preference_revision.preference_set_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM identity.preference_set p WHERE p.preference_set_id = preference_revision.preference_set_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_preference_revision_backoffice ON identity.preference_revision TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_preference_revision_worker ON identity.preference_revision TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE identity.consent_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.consent_record FORCE ROW LEVEL SECURITY;
CREATE POLICY p_consent_record_owner ON identity.consent_record TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_consent_record_backoffice ON identity.consent_record TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_consent_record_worker ON identity.consent_record TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE identity.privacy_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.privacy_request FORCE ROW LEVEL SECURITY;
CREATE POLICY p_privacy_request_owner ON identity.privacy_request TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_privacy_request_backoffice ON identity.privacy_request TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_privacy_request_worker ON identity.privacy_request TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE security.account ENABLE ROW LEVEL SECURITY;
ALTER TABLE security.account FORCE ROW LEVEL SECURITY;
CREATE POLICY p_account_owner ON security.account TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_account_backoffice ON security.account TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_account_worker ON security.account TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE security.credential ENABLE ROW LEVEL SECURITY;
ALTER TABLE security.credential FORCE ROW LEVEL SECURITY;
CREATE POLICY p_credential_owner ON security.credential TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_credential_backoffice ON security.credential TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_credential_worker ON security.credential TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE security.account_verification ENABLE ROW LEVEL SECURITY;
ALTER TABLE security.account_verification FORCE ROW LEVEL SECURITY;
CREATE POLICY p_account_verification_owner ON security.account_verification TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_account_verification_backoffice ON security.account_verification TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_account_verification_worker ON security.account_verification TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE security.recovery_token ENABLE ROW LEVEL SECURITY;
ALTER TABLE security.recovery_token FORCE ROW LEVEL SECURITY;
CREATE POLICY p_recovery_token_owner ON security.recovery_token TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_recovery_token_backoffice ON security.recovery_token TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_recovery_token_worker ON security.recovery_token TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE security.session ENABLE ROW LEVEL SECURITY;
ALTER TABLE security.session FORCE ROW LEVEL SECURITY;
CREATE POLICY p_session_owner ON security.session TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_session_backoffice ON security.session TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_session_worker ON security.session TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE security.mfa_method ENABLE ROW LEVEL SECURITY;
ALTER TABLE security.mfa_method FORCE ROW LEVEL SECURITY;
CREATE POLICY p_mfa_method_owner ON security.mfa_method TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_mfa_method_backoffice ON security.mfa_method TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_mfa_method_worker ON security.mfa_method TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE security.role_assignment ENABLE ROW LEVEL SECURITY;
ALTER TABLE security.role_assignment FORCE ROW LEVEL SECURITY;
CREATE POLICY p_role_assignment_owner ON security.role_assignment TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_role_assignment_backoffice ON security.role_assignment TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_role_assignment_worker ON security.role_assignment TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE security.security_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE security.security_event FORCE ROW LEVEL SECURITY;
CREATE POLICY p_security_event_owner ON security.security_event TO jp_app USING (account_id IS NULL OR account_id = security.current_account_id()) WITH CHECK (account_id IS NULL OR account_id = security.current_account_id());
CREATE POLICY p_security_event_backoffice ON security.security_event TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_security_event_worker ON security.security_event TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE learning.learner_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning.learner_profile FORCE ROW LEVEL SECURITY;
CREATE POLICY p_learner_profile_owner ON learning.learner_profile TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_learner_profile_backoffice ON learning.learner_profile TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_learner_profile_worker ON learning.learner_profile TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE learning.study_session ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning.study_session FORCE ROW LEVEL SECURITY;
CREATE POLICY p_study_session_owner ON learning.study_session TO jp_app USING (EXISTS (SELECT 1 FROM learning.learner_profile p WHERE p.learner_profile_id = study_session.learner_profile_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM learning.learner_profile p WHERE p.learner_profile_id = study_session.learner_profile_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_study_session_backoffice ON learning.study_session TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_study_session_worker ON learning.study_session TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE learning.study_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning.study_activity FORCE ROW LEVEL SECURITY;
CREATE POLICY p_study_activity_owner ON learning.study_activity TO jp_app USING (EXISTS (SELECT 1 FROM learning.study_session s JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE s.study_session_id = study_activity.study_session_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM learning.study_session s JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE s.study_session_id = study_activity.study_session_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_study_activity_backoffice ON learning.study_activity TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_study_activity_worker ON learning.study_activity TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE learning.exercise_instance ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning.exercise_instance FORCE ROW LEVEL SECURITY;
CREATE POLICY p_exercise_instance_owner ON learning.exercise_instance TO jp_app USING (EXISTS (SELECT 1 FROM learning.study_session s JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE s.study_session_id = exercise_instance.study_session_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM learning.study_session s JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE s.study_session_id = exercise_instance.study_session_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_exercise_instance_backoffice ON learning.exercise_instance TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_exercise_instance_worker ON learning.exercise_instance TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE learning.exercise_instance_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning.exercise_instance_item FORCE ROW LEVEL SECURITY;
CREATE POLICY p_exercise_instance_item_owner ON learning.exercise_instance_item TO jp_app USING (EXISTS (SELECT 1 FROM learning.exercise_instance i JOIN learning.study_session s ON s.study_session_id = i.study_session_id JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE i.instance_id = exercise_instance_item.instance_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM learning.exercise_instance i JOIN learning.study_session s ON s.study_session_id = i.study_session_id JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE i.instance_id = exercise_instance_item.instance_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_exercise_instance_item_backoffice ON learning.exercise_instance_item TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_exercise_instance_item_worker ON learning.exercise_instance_item TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE learning.answer_submission ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning.answer_submission FORCE ROW LEVEL SECURITY;
CREATE POLICY p_answer_submission_owner ON learning.answer_submission TO jp_app USING (EXISTS (SELECT 1 FROM learning.exercise_instance i JOIN learning.study_session s ON s.study_session_id = i.study_session_id JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE i.instance_id = answer_submission.instance_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM learning.exercise_instance i JOIN learning.study_session s ON s.study_session_id = i.study_session_id JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE i.instance_id = answer_submission.instance_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_answer_submission_backoffice ON learning.answer_submission TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_answer_submission_worker ON learning.answer_submission TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE learning.answer_value ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning.answer_value FORCE ROW LEVEL SECURITY;
CREATE POLICY p_answer_value_owner ON learning.answer_value TO jp_app USING (EXISTS (SELECT 1 FROM learning.answer_submission a JOIN learning.exercise_instance i ON i.instance_id = a.instance_id JOIN learning.study_session s ON s.study_session_id = i.study_session_id JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE a.submission_id = answer_value.submission_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM learning.answer_submission a JOIN learning.exercise_instance i ON i.instance_id = a.instance_id JOIN learning.study_session s ON s.study_session_id = i.study_session_id JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE a.submission_id = answer_value.submission_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_answer_value_backoffice ON learning.answer_value TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_answer_value_worker ON learning.answer_value TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE learning.evaluation_result ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning.evaluation_result FORCE ROW LEVEL SECURITY;
CREATE POLICY p_evaluation_result_owner ON learning.evaluation_result TO jp_app USING (EXISTS (SELECT 1 FROM learning.answer_submission a JOIN learning.exercise_instance i ON i.instance_id = a.instance_id JOIN learning.study_session s ON s.study_session_id = i.study_session_id JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE a.submission_id = evaluation_result.submission_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM learning.answer_submission a JOIN learning.exercise_instance i ON i.instance_id = a.instance_id JOIN learning.study_session s ON s.study_session_id = i.study_session_id JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE a.submission_id = evaluation_result.submission_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_evaluation_result_backoffice ON learning.evaluation_result TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_evaluation_result_worker ON learning.evaluation_result TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE learning.feedback_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning.feedback_item FORCE ROW LEVEL SECURITY;
CREATE POLICY p_feedback_item_owner ON learning.feedback_item TO jp_app USING (EXISTS (SELECT 1 FROM learning.evaluation_result e JOIN learning.answer_submission a ON a.submission_id = e.submission_id JOIN learning.exercise_instance i ON i.instance_id = a.instance_id JOIN learning.study_session s ON s.study_session_id = i.study_session_id JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE e.evaluation_id = feedback_item.evaluation_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM learning.evaluation_result e JOIN learning.answer_submission a ON a.submission_id = e.submission_id JOIN learning.exercise_instance i ON i.instance_id = a.instance_id JOIN learning.study_session s ON s.study_session_id = i.study_session_id JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE e.evaluation_id = feedback_item.evaluation_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_feedback_item_backoffice ON learning.feedback_item TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_feedback_item_worker ON learning.feedback_item TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE learning.learning_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning.learning_evidence FORCE ROW LEVEL SECURITY;
CREATE POLICY p_learning_evidence_owner ON learning.learning_evidence TO jp_app USING (EXISTS (SELECT 1 FROM learning.learner_profile p WHERE p.learner_profile_id = learning_evidence.learner_profile_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM learning.learner_profile p WHERE p.learner_profile_id = learning_evidence.learner_profile_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_learning_evidence_backoffice ON learning.learning_evidence TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_learning_evidence_worker ON learning.learning_evidence TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE learning.evidence_correction ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning.evidence_correction FORCE ROW LEVEL SECURITY;
CREATE POLICY p_evidence_correction_owner ON learning.evidence_correction TO jp_app USING (EXISTS (SELECT 1 FROM learning.learning_evidence e JOIN learning.learner_profile p ON p.learner_profile_id = e.learner_profile_id WHERE e.evidence_id = evidence_correction.original_evidence_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM learning.learning_evidence e JOIN learning.learner_profile p ON p.learner_profile_id = e.learner_profile_id WHERE e.evidence_id = evidence_correction.original_evidence_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_evidence_correction_backoffice ON learning.evidence_correction TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_evidence_correction_worker ON learning.evidence_correction TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE learning.study_session_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning.study_session_snapshot FORCE ROW LEVEL SECURITY;
CREATE POLICY p_study_session_snapshot_owner ON learning.study_session_snapshot TO jp_app USING (EXISTS (SELECT 1 FROM learning.study_session s JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE s.study_session_id = study_session_snapshot.study_session_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM learning.study_session s JOIN learning.learner_profile p ON p.learner_profile_id = s.learner_profile_id WHERE s.study_session_id = study_session_snapshot.study_session_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_study_session_snapshot_backoffice ON learning.study_session_snapshot TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_study_session_snapshot_worker ON learning.study_session_snapshot TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE progress.song_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE progress.song_progress FORCE ROW LEVEL SECURITY;
CREATE POLICY p_song_progress_owner ON progress.song_progress TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_song_progress_backoffice ON progress.song_progress TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_song_progress_worker ON progress.song_progress TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE progress.progress_derivation ENABLE ROW LEVEL SECURITY;
ALTER TABLE progress.progress_derivation FORCE ROW LEVEL SECURITY;
CREATE POLICY p_progress_derivation_owner ON progress.progress_derivation TO jp_app USING (EXISTS (SELECT 1 FROM progress.song_progress p WHERE p.song_progress_id = progress_derivation.song_progress_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM progress.song_progress p WHERE p.song_progress_id = progress_derivation.song_progress_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_progress_derivation_backoffice ON progress.progress_derivation TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_progress_derivation_worker ON progress.progress_derivation TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE progress.progress_contribution ENABLE ROW LEVEL SECURITY;
ALTER TABLE progress.progress_contribution FORCE ROW LEVEL SECURITY;
CREATE POLICY p_progress_contribution_owner ON progress.progress_contribution TO jp_app USING (EXISTS (SELECT 1 FROM progress.progress_derivation d JOIN progress.song_progress p ON p.song_progress_id = d.song_progress_id WHERE d.derivation_id = progress_contribution.derivation_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM progress.progress_derivation d JOIN progress.song_progress p ON p.song_progress_id = d.song_progress_id WHERE d.derivation_id = progress_contribution.derivation_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_progress_contribution_backoffice ON progress.progress_contribution TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_progress_contribution_worker ON progress.progress_contribution TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE progress.competency_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE progress.competency_progress FORCE ROW LEVEL SECURITY;
CREATE POLICY p_competency_progress_owner ON progress.competency_progress TO jp_app USING (EXISTS (SELECT 1 FROM progress.song_progress p WHERE p.song_progress_id = competency_progress.song_progress_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM progress.song_progress p WHERE p.song_progress_id = competency_progress.song_progress_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_competency_progress_backoffice ON progress.competency_progress TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_competency_progress_worker ON progress.competency_progress TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE progress.resume_point ENABLE ROW LEVEL SECURITY;
ALTER TABLE progress.resume_point FORCE ROW LEVEL SECURITY;
CREATE POLICY p_resume_point_owner ON progress.resume_point TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_resume_point_backoffice ON progress.resume_point TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_resume_point_worker ON progress.resume_point TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE progress.progress_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE progress.progress_history FORCE ROW LEVEL SECURITY;
CREATE POLICY p_progress_history_owner ON progress.progress_history TO jp_app USING (EXISTS (SELECT 1 FROM progress.song_progress p WHERE p.song_progress_id = progress_history.song_progress_id AND p.account_id = security.current_account_id())) WITH CHECK (EXISTS (SELECT 1 FROM progress.song_progress p WHERE p.song_progress_id = progress_history.song_progress_id AND p.account_id = security.current_account_id()));
CREATE POLICY p_progress_history_backoffice ON progress.progress_history TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_progress_history_worker ON progress.progress_history TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE progress.learner_progress_projection ENABLE ROW LEVEL SECURITY;
ALTER TABLE progress.learner_progress_projection FORCE ROW LEVEL SECURITY;
CREATE POLICY p_learner_progress_projection_owner ON progress.learner_progress_projection TO jp_app USING (account_id = security.current_account_id()) WITH CHECK (account_id = security.current_account_id());
CREATE POLICY p_learner_progress_projection_backoffice ON progress.learner_progress_projection TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_learner_progress_projection_worker ON progress.learner_progress_projection TO jp_worker USING (true) WITH CHECK (true);
ALTER TABLE ops.idempotency_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.idempotency_record FORCE ROW LEVEL SECURITY;
CREATE POLICY p_idempotency_record_owner ON ops.idempotency_record TO jp_app USING (account_id IS NULL OR account_id = security.current_account_id()) WITH CHECK (account_id IS NULL OR account_id = security.current_account_id());
CREATE POLICY p_idempotency_record_backoffice ON ops.idempotency_record TO jp_backoffice USING (true) WITH CHECK (true);
CREATE POLICY p_idempotency_record_worker ON ops.idempotency_record TO jp_worker USING (true) WITH CHECK (true);

-- 11. Privilegios mínimos
REVOKE ALL ON ALL TABLES IN SCHEMA identity, security, catalog, content, learning, progress, editorial, configuration, ops FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA security, ops FROM PUBLIC;
GRANT USAGE ON SCHEMA identity, security, catalog, content, learning, progress, editorial, configuration, ops TO jp_app, jp_backoffice, jp_worker;
GRANT USAGE ON SCHEMA catalog TO jp_readonly;

GRANT SELECT ON ALL TABLES IN SCHEMA catalog, content, editorial, configuration TO jp_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA identity, learning, progress TO jp_app;
GRANT SELECT, INSERT, UPDATE ON security.account, security.credential, security.account_verification,
    security.recovery_token, security.session, security.security_event TO jp_app;
GRANT SELECT ON security.role, security.permission, security.role_permission,
    security.role_assignment, security.access_scope TO jp_app;
GRANT SELECT, INSERT, UPDATE ON ops.idempotency_record, ops.outbox_message TO jp_app;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA security, catalog, content, editorial, configuration TO jp_backoffice;
GRANT SELECT ON ALL TABLES IN SCHEMA identity, learning, progress, ops TO jp_backoffice;
GRANT INSERT ON security.audit_event, ops.outbox_message TO jp_backoffice;

GRANT SELECT ON ALL TABLES IN SCHEMA identity, security, catalog, content, learning, progress, editorial, configuration TO jp_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ops TO jp_worker;
GRANT INSERT, UPDATE ON catalog.song_search_document, editorial.published_package_projection,
    progress.learner_progress_projection TO jp_worker;

GRANT SELECT ON catalog.v_public_song, catalog.v_public_song_search TO jp_readonly;
GRANT EXECUTE ON FUNCTION security.current_account_id() TO jp_app, jp_backoffice, jp_worker;
GRANT EXECUTE ON FUNCTION ops.bump_version(), ops.prevent_mutation(), ops.guard_terminal_status()
    TO jp_owner;

ALTER DEFAULT PRIVILEGES FOR ROLE jp_owner IN SCHEMA identity, security, catalog, content,
    learning, progress, editorial, configuration, ops REVOKE ALL ON TABLES FROM PUBLIC;

COMMIT;


