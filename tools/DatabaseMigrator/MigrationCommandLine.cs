using System.Globalization;
using System.Text.RegularExpressions;

namespace MusicaAprender.DatabaseMigrator;

internal sealed partial class MigrationCommandLine
{
    private MigrationCommandLine(
        string host,
        int port,
        string database,
        string username,
        string passwordFile)
    {
        Host = host;
        Port = port;
        Database = database;
        Username = username;
        PasswordFile = passwordFile;
    }

    internal string Host { get; }

    internal int Port { get; }

    internal string Database { get; }

    internal string Username { get; }

    internal string PasswordFile { get; }

    internal static MigrationCommandLine Parse(string[] args)
    {
        ArgumentNullException.ThrowIfNull(args);

        var values = new Dictionary<string, string>(StringComparer.Ordinal);

        for (var index = 0; index < args.Length; index += 2)
        {
            if (index + 1 >= args.Length || !args[index].StartsWith("--", StringComparison.Ordinal))
            {
                throw new ArgumentException(
                    "Argumentos esperados: --host --port --database --username --password-file.",
                    nameof(args));
            }

            values[args[index]] = args[index + 1];
        }

        var host = Require(values, "--host");
        var database = RequireIdentifier(values, "--database");
        var username = RequireIdentifier(values, "--username");
        var passwordFile = Path.GetFullPath(Require(values, "--password-file"));

        if (!File.Exists(passwordFile))
        {
            throw new FileNotFoundException(
                "No existe el archivo de secreto PostgreSQL indicado.",
                passwordFile);
        }

        var portText = Require(values, "--port");
        if (!int.TryParse(portText, NumberStyles.None, CultureInfo.InvariantCulture, out var port)
            || port is < 1 or > 65535)
        {
            throw new ArgumentException("--port debe ser un puerto TCP valido.", nameof(args));
        }

        return new MigrationCommandLine(host, port, database, username, passwordFile);
    }

    private static string Require(
        IReadOnlyDictionary<string, string> values,
        string key)
    {
        if (!values.TryGetValue(key, out var value) || string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException($"Falta el argumento requerido {key}.", nameof(values));
        }

        return value.Trim();
    }

    private static string RequireIdentifier(
        IReadOnlyDictionary<string, string> values,
        string key)
    {
        var value = Require(values, key);

        if (!PostgreSqlIdentifierRegex().IsMatch(value))
        {
            throw new ArgumentException(
                $"{key} no cumple el formato seguro de identificador PostgreSQL.",
                nameof(values));
        }

        return value;
    }

    [GeneratedRegex("^[A-Za-z_][A-Za-z0-9_]{0,62}$", RegexOptions.CultureInvariant)]
    private static partial Regex PostgreSqlIdentifierRegex();
}
