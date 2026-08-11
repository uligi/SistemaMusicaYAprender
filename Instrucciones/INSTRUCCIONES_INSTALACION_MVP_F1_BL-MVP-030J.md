# Instalación — BL-MVP-030J

Rama: `main`.

HEAD requerido:

`73fff5fe4982085ba090316c883587ef987e746f`

Extrae `BL-MVP-030J_Paquete_Correctivo.zip` directamente sobre la raíz.

Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-030j.ps1
```

Resultado esperado:

```text
OK: TypeScript E2E aprobado.
OK: regresion E2E BL-MVP-027 aprobada con el contrato de sesion BL-MVP-030.
OK: git diff --check aprobado.
OK: BL-MVP-030J aplicado y validado.
```

Después vuelve a ejecutar la puerta completa:

```powershell
.\scripts\apply-bl-mvp-030.ps1
```

Sin `Skip*`. No hacer staging, commit ni push hasta GREEN completo.
