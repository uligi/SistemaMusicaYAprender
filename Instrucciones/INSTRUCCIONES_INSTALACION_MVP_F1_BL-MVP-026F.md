# Instrucciones de instalación — BL-MVP-026F

Repositorio:
`C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender`

## 1. Extracción

Extraer `BL-MVP-026F_Paquete_Instalacion.zip` directamente sobre la raíz del repositorio,
sin carpeta envolvente.

El paquete contiene:

- `scripts/apply-bl-mvp-026f.ps1`
- `README/BL-MVP-026F_README.md`
- `INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-026F.md`

No eliminar ni revertir BL-MVP-026D ni BL-MVP-026E.

## 2. Ejecución

Desde PowerShell en la raíz:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-026f.ps1
```

Resultado esperado:

```text
OK: sintaxis PowerShell de apply-bl-mvp-026.ps1 aprobada.
OK: git diff --check aprobado.
OK: BL-MVP-026F instalado.
```

## 3. Reejecutar BL-MVP-026 completo

```powershell
.\scripts\apply-bl-mvp-026.ps1
```

No usar `Skip*`.

## 4. Hasta obtener GREEN

No ejecutar `git add`, `git commit` ni `git push`.

Cuando BL-MVP-026 quede GREEN se revisará el inventario completo antes de staging.
