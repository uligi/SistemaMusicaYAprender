using System.Xml.Linq;

var root = FindRepositoryRoot(AppContext.BaseDirectory)
    ?? throw new InvalidOperationException("No se encontró la raíz del repositorio.");

var moduleProjects = Directory.GetFiles(
    Path.Combine(root, "src", "Modules"),
    "*.csproj",
    SearchOption.AllDirectories);

var violations = new List<string>();

foreach (var project in moduleProjects)
{
    var document = XDocument.Load(project);
    var references = document
        .Descendants("ProjectReference")
        .Select(element => element.Attribute("Include")?.Value)
        .Where(value => !string.IsNullOrWhiteSpace(value));

    foreach (var reference in references)
    {
        var normalized = reference!.Replace('\\', '/');
        if (normalized.Contains("/Modules/", StringComparison.OrdinalIgnoreCase))
        {
            violations.Add($"{Path.GetRelativePath(root, project)} -> {reference}");
        }
    }
}

if (violations.Count > 0)
{
    Console.Error.WriteLine("Se detectaron referencias directas entre módulos:");
    foreach (var violation in violations)
    {
        Console.Error.WriteLine($"- {violation}");
    }

    return 1;
}

Console.WriteLine("OK: no existen ProjectReference directos entre módulos.");
return 0;

static string? FindRepositoryRoot(string start)
{
    var current = new DirectoryInfo(start);
    while (current is not null)
    {
        if (File.Exists(Path.Combine(current.FullName, "MusicaAprender.sln")))
        {
            return current.FullName;
        }

        current = current.Parent;
    }

    return null;
}
