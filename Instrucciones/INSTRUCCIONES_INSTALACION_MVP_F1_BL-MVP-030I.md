# Instalación — BL-MVP-030I

Rama: `main`.

HEAD requerido:

`73fff5fe4982085ba090316c883587ef987e746f`

Extrae `BL-MVP-030I_Paquete_Correctivo.zip` directamente sobre la raíz.

Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-030i.ps1
```

Resultado esperado:

```text
OK: dotnet format y analyzers aprobados.
OK: proyecto UnitTests compila sin CA1707.
OK: pruebas unitarias aprobadas.
OK: git diff --check aprobado.
OK: BL-MVP-030I aplicado y validado.
```

Después ejecuta nuevamente la puerta completa:

```powershell
.\scripts\apply-bl-mvp-030.ps1
```

Sin `Skip*`. No hacer staging, commit ni push hasta GREEN completo.
