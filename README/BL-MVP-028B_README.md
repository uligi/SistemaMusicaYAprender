# BL-MVP-028B — corrección del verificador de límites modulares

## Motivo

La segunda ejecución de `scripts/apply-bl-mvp-028.ps1` aprobó formato, compilación, 9/9 pruebas E2E, 14/14 pruebas unitarias y la prueba de arquitectura, pero se detuvo al invocar `scripts/check-module-boundaries.ps1`. Bajo el `Set-StrictMode` heredado del instalador, el acceso dinámico a `ProjectReference` fallaba en proyectos que no declaran ese nodo XML.

## Alcance

Este correctivo:

- obtiene los nodos `ProjectReference` mediante una selección XML que devuelve una colección vacía cuando no existen;
- lee el atributo `Include` de forma segura y omite referencias incompletas;
- conserva la prohibición de referencias directas entre módulos;
- no modifica API, web, worker, PostgreSQL, Argon2id, secretos, contratos ni pruebas;
- reutiliza el instalador completo `scripts/apply-bl-mvp-028.ps1` del paquete base.

## Instalación

Después de haber extraído BL-MVP-028 y BL-MVP-028A, extraer este ZIP sobre la raíz del repositorio, aceptar la sobrescritura y ejecutar:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-028.ps1
```

No volver a extraer los paquetes anteriores. No usar opciones `Skip*` ni ejecutar `git add`, commit o push antes de revisar el GREEN y el inventario.
