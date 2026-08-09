BEGIN;

DELETE FROM identity.user_profile
WHERE
    account_id IN (
        '13000000-0000-4000-8000-000000000001',
        '13000000-0000-4000-8000-000000000002'
    );

DELETE FROM security.account
WHERE
    account_id IN (
        '13000000-0000-4000-8000-000000000001',
        '13000000-0000-4000-8000-000000000002'
    );

INSERT INTO
    security.account (
        account_id,
        email_lookup_hash,
        email_cipher,
        status_code,
        created_at,
        version
    )
VALUES
    (
        '13000000-0000-4000-8000-000000000001',
        decode(repeat('13', 32), 'hex'),
        decode(repeat('31', 16), 'hex'),
        'ACTIVE',
        CURRENT_TIMESTAMP,
        1
    ),
    (
        '13000000-0000-4000-8000-000000000002',
        decode(repeat('24', 32), 'hex'),
        decode(repeat('42', 16), 'hex'),
        'ACTIVE',
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
        '13000000-0000-4000-8000-000000000001',
        'BL-MVP-013 Cuenta A',
        'es',
        'America/Costa_Rica',
        CURRENT_TIMESTAMP,
        1
    ),
    (
        '13000000-0000-4000-8000-000000000002',
        'BL-MVP-013 Cuenta B',
        'es',
        'America/Costa_Rica',
        CURRENT_TIMESTAMP,
        1
    );

COMMIT;
