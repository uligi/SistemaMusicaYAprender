# Instalación — BL-MVP-030A

## Precondición

Rama: `main`

HEAD:

`73fff5fe4982085ba090316c883587ef987e746f`

La primera ejecución de BL-MVP-030 debe haberse detenido en `npm run format:check` por:

- `apps/web/src/app/router/route-manifest.ts`
- `docs/engineering/security/effective-authorization.md`

## Extracción

Extrae `BL-MVP-030A_Paquete_Correctivo.zip` directamente sobre la raíz del repositorio.

## Ejecución

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-030a.ps1
```

Resultado esperado:

```text
Prettier local: 3.9.6
OK: Prettier aprobo los dos archivos afectados.
OK: TypeScript aprobado.
OK: git diff --check aprobado.
OK: BL-MVP-030A aplicado y validado.
```

Después ejecuta nuevamente la puerta completa:

```powershell
.\scripts\apply-bl-mvp-030.ps1
```

No usar `Skip*`. No ejecutar staging, commit ni push hasta GREEN completo.
