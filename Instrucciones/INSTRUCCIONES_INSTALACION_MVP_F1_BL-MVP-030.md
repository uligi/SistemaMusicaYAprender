# Instalación — BL-MVP-030

Base requerida:

`73fff5fe4982085ba090316c883587ef987e746f`

Rama: `main`.

Extrae `BL-MVP-030_Paquete_Instalacion.zip` directamente sobre la raíz:

`C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender`

Después ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-030.ps1
```

No uses `Skip*`.

La puerta debe ejecutar calidad completa, Docker, regresiones 026/027/029 y el smoke
`verify-effective-authorization.sh`.

Resultado final esperado:

```text
OK: BL-MVP-030 permisos efectivos, alcance, vigencia y denegacion por defecto verificados.
OK: BL-MVP-030 instalado y validado localmente con autorizacion server-side y alcance vigente.
```

No hacer `git add`, commit ni push hasta revisar GREEN e inventario.
