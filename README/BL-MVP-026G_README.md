# BL-MVP-026G — corrección del lanzamiento HTTPS del smoke en GitHub Actions

## Motivo

BL-MVP-026 quedó GREEN local y se publicó en el commit
`4d515484b8597615b9665be4b0c5bded43565a6e`, pero GitHub Actions falló en:

`Verify same-origin login, CSRF and revocable server session`

El log de CI muestra simultáneamente:

- `Using launch settings from apps/api/Properties/launchSettings.json...`
- `Now listening on: http://localhost:5080`
- `ERROR: BL-MVP-026: la API no quedo disponible.`

El smoke standalone define por defecto `https://localhost:5080`, configura los archivos PEM de
Kestrel y asigna `ASPNETCORE_URLS` a esa URL. Sin embargo, el `dotnet run` no deshabilitaba
`launchSettings.json`. El único perfil de `apps/api/Properties/launchSettings.json` publica
`http://localhost:5080`, por lo que el proceso terminó escuchando en HTTP mientras `curl` esperaba HTTPS.

Los secretos efímeros de CI ya generan un certificado y una clave PEM para `localhost`, así que no es
necesario debilitar el smoke a HTTP.

## Corrección

BL-MVP-026G agrega exclusivamente:

```text
--no-launch-profile
```

al `dotnet run` interno de `scripts/ci/identity/verify-personal-login.sh`.

De esta forma el smoke standalone deja de aplicar `launchSettings.json` y respeta la configuración
explícita `ASPNETCORE_URLS=https://...` junto con el certificado efímero.

No cambia:

- la API ni `Program.cs`;
- cookies `Secure`, `HttpOnly`, `SameSite=Strict` o `Path=/`;
- CSRF;
- PostgreSQL;
- Nginx o Docker Compose;
- contratos funcionales de BL-MVP-026.

## Validación local del correctivo

El instalador `scripts/apply-bl-mvp-026g.ps1`:

1. exige `main` en el commit fallido publicado `4d515484...`;
2. rehúsa staging previo y cambios locales sobre el verificador;
3. aplica el cambio exacto;
4. ejecuta `bash -n` con Git Bash;
5. ejecuta `git diff --check`;
6. inicia un smoke standalone HTTPS en `https://localhost:5443`, separado del API Docker en 5080;
7. no hace `git add`, commit ni push.
