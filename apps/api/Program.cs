var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => Results.Ok(new
{
    service = "MusicaAprender.Api",
    status = "scaffold",
    backlogItem = "BL-MVP-001"
}));

app.Run();

public partial class Program;
