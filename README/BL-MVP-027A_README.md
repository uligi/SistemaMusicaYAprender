# BL-MVP-027A — corrección de formato Prettier

## Motivo

La primera ejecución de `scripts/apply-bl-mvp-027.ps1` aprobó restauración, toolchain, secretos,
compilación inicial y TypeScript, pero la puerta se detuvo en:

```text
[warn] apps/web/src/routes/public/PersonalAccountLoginPage.tsx
[warn] Code style issues found in the above file. Run Prettier with --write to fix.
npm run format:check fallo con codigo de salida 1.
```

No se observó un error funcional ni de tipos. La puerta falló exclusivamente porque el archivo
`PersonalAccountLoginPage.tsx` no estaba serializado exactamente con el formato canónico de
Prettier 3.9.6 configurado por el repositorio.

## Corrección

BL-MVP-027A no cambia la lógica de logout. El instalador:

1. exige `main` sobre `32a2cbdb5bf0102b3e527cb1998fb5a227a56294`;
2. usa el Prettier local fijado por `package.json` (`3.9.6`);
3. ejecuta `prettier --write` únicamente sobre
   `apps/web/src/routes/public/PersonalAccountLoginPage.tsx`;
4. vuelve a ejecutar `prettier --check` para ese archivo;
5. ejecuta TypeScript y `git diff --check`;
6. no ejecuta staging, commit ni push.

Después debe reejecutarse `scripts/apply-bl-mvp-027.ps1` completo, sin opciones `Skip*`.

## Alcance

No se modifican contratos API, CSRF, cookies, PostgreSQL, CI, SQL maestro, sesión, autorización ni
criterios de aceptación. Es un correctivo de formato únicamente.
