\set ON_ERROR_STOP on

WITH fk_base AS (
    SELECT
        constraint_row.oid AS constraint_oid,
        constraint_row.conname AS constraint_name,
        dependent_namespace.nspname AS dependent_schema,
        dependent_table.relname AS dependent_table,
        dependent_table.oid AS dependent_table_oid,
        principal_namespace.nspname AS principal_schema,
        principal_table.relname AS principal_table,
        principal_table.oid AS principal_table_oid,
        constraint_row.conkey,
        constraint_row.confkey
    FROM pg_catalog.pg_constraint AS constraint_row
    JOIN pg_catalog.pg_class AS dependent_table
      ON dependent_table.oid = constraint_row.conrelid
    JOIN pg_catalog.pg_namespace AS dependent_namespace
      ON dependent_namespace.oid = dependent_table.relnamespace
    JOIN pg_catalog.pg_class AS principal_table
      ON principal_table.oid = constraint_row.confrelid
    JOIN pg_catalog.pg_namespace AS principal_namespace
      ON principal_namespace.oid = principal_table.relnamespace
    WHERE constraint_row.contype = 'f'
      AND dependent_namespace.nspname IN (
          'identity',
          'security',
          'catalog',
          'content',
          'learning',
          'progress',
          'editorial',
          'configuration',
          'ops'
      )
      AND principal_namespace.nspname IN (
          'identity',
          'security',
          'catalog',
          'content',
          'learning',
          'progress',
          'editorial',
          'configuration',
          'ops'
      )
      AND dependent_namespace.nspname <> principal_namespace.nspname
),
fk_columns AS (
    SELECT
        fk_base.constraint_oid,
        fk_base.constraint_name,
        fk_base.dependent_schema,
        fk_base.dependent_table,
        fk_base.principal_schema,
        fk_base.principal_table,
        dependent_key.ordinality AS column_ordinal,
        dependent_attribute.attname AS dependent_column,
        principal_attribute.attname AS principal_column
    FROM fk_base
    CROSS JOIN LATERAL unnest(fk_base.conkey)
        WITH ORDINALITY AS dependent_key(attnum, ordinality)
    JOIN LATERAL unnest(fk_base.confkey)
        WITH ORDINALITY AS principal_key(attnum, ordinality)
      ON principal_key.ordinality = dependent_key.ordinality
    JOIN pg_catalog.pg_attribute AS dependent_attribute
      ON dependent_attribute.attrelid = fk_base.dependent_table_oid
     AND dependent_attribute.attnum = dependent_key.attnum
    JOIN pg_catalog.pg_attribute AS principal_attribute
      ON principal_attribute.attrelid = fk_base.principal_table_oid
     AND principal_attribute.attnum = principal_key.attnum
),
grouped AS (
    SELECT
        constraint_oid,
        constraint_name,
        dependent_schema,
        dependent_table,
        principal_schema,
        principal_table,
        jsonb_agg(
            dependent_column
            ORDER BY column_ordinal
        ) AS dependent_columns,
        jsonb_agg(
            principal_column
            ORDER BY column_ordinal
        ) AS principal_columns
    FROM fk_columns
    GROUP BY
        constraint_oid,
        constraint_name,
        dependent_schema,
        dependent_table,
        principal_schema,
        principal_table
)
SELECT jsonb_pretty(
    jsonb_build_object(
        'backlogItem',
        'BL-MVP-014',
        'relationships',
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'constraint',
                    constraint_name,
                    'dependentSchema',
                    dependent_schema,
                    'dependentTable',
                    dependent_table,
                    'dependentColumns',
                    dependent_columns,
                    'principalSchema',
                    principal_schema,
                    'principalTable',
                    principal_table,
                    'principalColumns',
                    principal_columns
                )
                ORDER BY
                    dependent_schema,
                    dependent_table,
                    constraint_name
            ),
            '[]'::jsonb
        )
    )
)
FROM grouped;
