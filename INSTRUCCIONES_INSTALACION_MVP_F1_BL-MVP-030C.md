# Instalación — BL-MVP-030C

Rama: `main`.

HEAD requerido:

`73fff5fe4982085ba090316c883587ef987e746f`

BL-MVP-030A y 030B ya deben estar aplicados.

Extrae `BL-MVP-030C_Paquete_Correctivo.zip` directamente sobre la raíz del repositorio.

Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-030c.ps1
```

Resultado esperado:

```text
OK: route-manifest canonico validado sin depender del layout de Prettier.
OK: BL-MVP-030C aplicado y validado.
```

Después:

```powershell
.\scripts\apply-bl-mvp-030.ps1
```

Sin `Skip*`. No ejecutar staging, commit ni push hasta GREEN completo.
