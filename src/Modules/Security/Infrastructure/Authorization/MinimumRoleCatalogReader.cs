using Microsoft.Extensions.Configuration;
using Npgsql;

namespace MusicaAprender.Modules.Security.Infrastructure.Authorization;

public static class MinimumRoleCatalogManifest
{
    public const string SafeRoleCode = "STUDENT";

    public static IReadOnlyList<string> RoleCodes { get; } =
    [
        SafeRoleCode,
        "EDITOR",
        "REVIEWER",
        "ADMIN"
    ];
}

public sealed record MinimumRoleCatalogStatus(
    bool StorageAvailable,
    int PublishedRoleCount,
    IReadOnlyList<string> MissingRoleCodes)
{
    public bool IsComplete => StorageAvailable && MissingRoleCodes.Count == 0;
}

public sealed class MinimumRoleCatalogReader(IConfiguration configuration)
{
    public async Task<MinimumRoleCatalogStatus> InspectAsync(
        CancellationToken cancellationToken = default)
    {
        var connectionString = configuration.GetConnectionString("PostgreSQL");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return UnavailableStatus();
        }

        try
        {
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            const string sql = """
                SELECT role_code
                FROM security.role
                WHERE role_code = ANY (@role_codes)
                  AND status_code = 'ACTIVE'
                  AND version > 0;
                """;

            await using var command = new NpgsqlCommand(sql, connection);
            command.Parameters.AddWithValue(
                "role_codes",
                MinimumRoleCatalogManifest.RoleCodes.ToArray());

            var published = new HashSet<string>(StringComparer.Ordinal);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                published.Add(reader.GetString(0));
            }

            var missing = MinimumRoleCatalogManifest.RoleCodes
                .Where(roleCode => !published.Contains(roleCode))
                .ToArray();

            return new MinimumRoleCatalogStatus(
                StorageAvailable: true,
                PublishedRoleCount: published.Count,
                MissingRoleCodes: missing);
        }
        catch (NpgsqlException)
        {
            return UnavailableStatus();
        }
        catch (InvalidOperationException)
        {
            return UnavailableStatus();
        }
        catch (ArgumentException)
        {
            return UnavailableStatus();
        }
    }

    private static MinimumRoleCatalogStatus UnavailableStatus() =>
        new(
            StorageAvailable: false,
            PublishedRoleCount: 0,
            MissingRoleCodes: MinimumRoleCatalogManifest.RoleCodes.ToArray());
}
