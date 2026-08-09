FROM mcr.microsoft.com/dotnet/sdk:9.0.314-azurelinux3.0 AS build
WORKDIR /src

COPY . .
RUN dotnet restore apps/worker/MusicaAprender.Worker.csproj --locked-mode
RUN dotnet publish apps/worker/MusicaAprender.Worker.csproj \
    --configuration Release \
    --no-restore \
    --output /app/publish \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:9.0.16-azurelinux3.0 AS runtime
WORKDIR /app

COPY --from=build /app/publish .
USER app
ENTRYPOINT ["dotnet", "MusicaAprender.Worker.dll"]
