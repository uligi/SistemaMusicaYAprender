# Instalación — BL-MVP-030G

Rama: `main`.

HEAD requerido:

`73fff5fe4982085ba090316c883587ef987e746f`

Extrae `BL-MVP-030G_Paquete_Correctivo.zip` directamente sobre la raíz.

Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-030g.ps1
```

Resultado esperado:

```text
OK: dotnet format y analyzers aprobados.
OK: modulo Security compila sin CA1720.
OK: proyecto UnitTests compila.
OK: pruebas unitarias aprobadas.
OK: git diff --check aprobado.
OK: BL-MVP-030G aplicado y validado.
```

Después ejecuta nuevamente la puerta completa:

```powershell
.\scripts\apply-bl-mvp-030.ps1
```

Sin `Skip*`. No hacer staging, commit ni push hasta GREEN completo.
