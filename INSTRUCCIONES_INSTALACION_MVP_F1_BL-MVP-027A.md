# Instalación — BL-MVP-027A

## Precondición

Repositorio:

`C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender`

Rama: `main`

HEAD:

`32a2cbdb5bf0102b3e527cb1998fb5a227a56294`

La primera aplicación de BL-MVP-027 debe haber quedado detenida únicamente en
`npm run format:check` por `PersonalAccountLoginPage.tsx`.

## Extracción

Extrae `BL-MVP-027A_Paquete_Correctivo.zip` directamente sobre la raíz del repositorio, sin carpeta
envolvente.

El ZIP incluye el archivo completo afectado, el instalador, README e instrucciones.

## Ejecución

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-027a.ps1
```

El instalador usa `node_modules\.bin\prettier.cmd` versión 3.9.6. Si `node_modules` no está presente,
restaura paquetes con `npm ci`.

Resultado esperado:

```text
Prettier local: 3.9.6
OK: Prettier aprobó apps/web/src/routes/public/PersonalAccountLoginPage.tsx.
OK: TypeScript aprobado.
OK: git diff --check aprobado.
OK: BL-MVP-027A aplicado y validado.
```

Después ejecuta nuevamente, sin `Skip*`:

```powershell
.\scripts\apply-bl-mvp-027.ps1
```

No ejecutar staging, commit ni push hasta que la puerta BL-MVP-027 completa termine GREEN.
