# Instalación — BL-MVP-030E

Rama: `main`.

HEAD requerido:

`73fff5fe4982085ba090316c883587ef987e746f`

BL-MVP-030D ya debe haber ejecutado los reemplazos del `route-manifest`.

Extrae `BL-MVP-030E_Paquete_Correctivo.zip` directamente sobre la raíz.

Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-030e.ps1
```

Resultado esperado:

```text
OK: cero capacidades legacy y catalogo canonico completo.
OK: Prettier aprobado.
OK: TypeScript aprobado.
OK: git diff --check aprobado.
OK: BL-MVP-030E aplicado y validado.
```

Después ejecuta nuevamente:

```powershell
.\scripts\apply-bl-mvp-030.ps1
```

Sin `Skip*`. No hacer staging, commit ni push hasta GREEN completo.
