using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace MusicaAprender.DatabaseMigrator.Migrations;

[DbContext(typeof(PhysicalSchemaDbContext))]
[Migration(MigrationId)]
public sealed class UsernameIdentityDirectory : Migration
{
    internal const string MigrationId = "202608180001_UsernameIdentityDirectory";

    protected override void Up(MigrationBuilder migrationBuilder)
    {
        ArgumentNullException.ThrowIfNull(migrationBuilder);

        migrationBuilder.Sql(
            """
            BEGIN;
            SET LOCAL lock_timeout = '10s';
            SET LOCAL statement_timeout = '5min';
            SET LOCAL ROLE jp_owner;

            ALTER TABLE identity.user_profile
                ADD COLUMN username varchar(32);

            ALTER TABLE identity.user_profile
                ADD CONSTRAINT ck_identity_user_profile_username
                CHECK (
                    username IS NULL
                    OR (
                        username = lower(username)
                        AND username ~ '^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$'
                        AND username NOT IN (
                            'admin',
                            'administrator',
                            'api',
                            'editor',
                            'moderator',
                            'musicayaprender',
                            'reviewer',
                            'root',
                            'security',
                            'support',
                            'system',
                            'www'
                        )
                    )
                );

            CREATE UNIQUE INDEX uq_identity_user_profile_username
                ON identity.user_profile (username)
                WHERE username IS NOT NULL;

            COMMENT ON COLUMN identity.user_profile.username IS
                'Identificador humano estable, normalizado y no sensible; account_id sigue siendo la identidad técnica.';

            COMMIT;
            """,
            suppressTransaction: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        ArgumentNullException.ThrowIfNull(migrationBuilder);

        migrationBuilder.Sql(
            """
            DO $rollback$
            BEGIN
                RAISE EXCEPTION
                    'UsernameIdentityDirectory no admite Down automático porque username pasa a formar parte de la identidad estable.';
            END;
            $rollback$;
            """,
            suppressTransaction: true);
    }
}
