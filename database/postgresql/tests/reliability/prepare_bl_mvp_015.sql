BEGIN;

SELECT
    set_config('app.maintenance_mode', 'on', true);

DELETE FROM ops.inbox_message
WHERE
    event_id IN (
        '15000000-0000-7000-8000-000000000101',
        '15000000-0000-7000-8000-000000000102',
        '15000000-0000-7000-8000-000000000103',
        '15000000-0000-7000-8000-000000000104'
    );

DELETE FROM ops.job_attempt
WHERE
    job_id IN (
        '15000000-0000-7000-8000-000000000101',
        '15000000-0000-7000-8000-000000000102',
        '15000000-0000-7000-8000-000000000103',
        '15000000-0000-7000-8000-000000000104'
    );

DELETE FROM ops.background_job
WHERE
    job_id IN (
        '15000000-0000-7000-8000-000000000101',
        '15000000-0000-7000-8000-000000000102',
        '15000000-0000-7000-8000-000000000103',
        '15000000-0000-7000-8000-000000000104'
    );

DELETE FROM ops.idempotency_record
WHERE
    account_id = '15000000-0000-4000-8000-000000000001'
    OR operation_code LIKE 'BL015.%';

DELETE FROM ops.outbox_message
WHERE
    event_id IN (
        '15000000-0000-7000-8000-000000000101',
        '15000000-0000-7000-8000-000000000102',
        '15000000-0000-7000-8000-000000000103',
        '15000000-0000-7000-8000-000000000104'
    );

DELETE FROM ops.read_model_checkpoint
WHERE
    projection_code LIKE 'BL015.%';

DELETE FROM identity.user_profile
WHERE
    account_id = '15000000-0000-4000-8000-000000000001';

DELETE FROM security.account
WHERE
    account_id = '15000000-0000-4000-8000-000000000001';

COMMIT;

BEGIN;

INSERT INTO
    security.account (
        account_id,
        email_lookup_hash,
        email_cipher,
        status_code,
        verified_at,
        created_at,
        version
    )
VALUES
    (
        '15000000-0000-4000-8000-000000000001',
        decode(repeat('15', 32), 'hex'),
        decode(repeat('51', 16), 'hex'),
        'ACTIVE',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        1
    );

INSERT INTO
    identity.user_profile (
        account_id,
        display_name,
        ui_language,
        time_zone,
        created_at,
        version
    )
VALUES
    (
        '15000000-0000-4000-8000-000000000001',
        'BL-MVP-015 ORIGINAL',
        'es',
        'America/Costa_Rica',
        CURRENT_TIMESTAMP,
        1
    );

COMMIT;
