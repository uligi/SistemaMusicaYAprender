# Instalación — BL-MVP-030H

Rama: `main`.

HEAD requerido:

`73fff5fe4982085ba090316c883587ef987e746f`

Extrae `BL-MVP-030H_Paquete_Correctivo.zip` directamente sobre la raíz.

Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-030h.ps1
```

Resultado esperado:

```text
OK: sintaxis PowerShell de 030, 030G y 030H aprobada.
OK: correccion CA1720 preserva el scope_type fisico OBJECT.
OK: dotnet format y analyzers aprobados.
OK: modulo Security compila sin CA1720.
OK: proyecto UnitTests compila.
OK: pruebas unitarias aprobadas.
OK: git diff --check aprobado.
OK: BL-MVP-030H aplicado y validado.
```

Después ejecuta nuevamente:

```powershell
.\scripts\apply-bl-mvp-030.ps1
```

Sin `Skip*`. No hacer staging, commit ni push hasta GREEN completo.
