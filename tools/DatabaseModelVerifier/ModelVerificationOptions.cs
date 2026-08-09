namespace MusicaAprender.DatabaseModelVerifier;

internal sealed record ModelVerificationOptions(
    string Host,
    int Port,
    string Database,
    string SecretDirectory,
    string RepositoryRoot,
    string? SummaryPath)
{
    internal static ModelVerificationOptions Parse(string[] args)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal);

        for (var index = 0; index < args.Length; index += 2)
        {
            if (index + 1 >= args.Length
                || !args[index].StartsWith("--", StringComparison.Ordinal))
            {
                throw new ArgumentException(
                    "Uso: --host <host> --port <port> --database <db> " +
                    "--secret-directory <ruta> --repository-root <ruta> " +
                    "[--summary <ruta>]");
            }

            values[args[index][2..]] = args[index + 1];
        }

        var host = Require(values, "host");
        var database = Require(values, "database");
        var secretDirectory = Require(values, "secret-directory");
        var repositoryRoot = Require(values, "repository-root");

        if (!int.TryParse(Require(values, "port"), out var port)
            || port is < 1 or > 65535)
        {
            throw new ArgumentException("--port debe ser un puerto TCP valido.");
        }

        if (database.Length > 63)
        {
            throw new ArgumentException("--database excede 63 caracteres.");
        }

        values.TryGetValue("summary", out var summaryPath);

        return new ModelVerificationOptions(
            host,
            port,
            database,
            Path.GetFullPath(secretDirectory),
            Path.GetFullPath(repositoryRoot),
            string.IsNullOrWhiteSpace(summaryPath)
                ? null
                : Path.GetFullPath(summaryPath));
    }

    private static string Require(
        Dictionary<string, string> values,
        string key)
    {
        if (!values.TryGetValue(key, out var value)
            || string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException($"Falta --{key}.");
        }

        return value.Trim();
    }
}
