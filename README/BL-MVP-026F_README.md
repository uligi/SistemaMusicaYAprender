# BL-MVP-026F — reconciliación del inventario de correctivos

## Motivo

BL-MVP-026E quedó validado correctamente con Git Bash, pero al volver a ejecutar
`scripts/apply-bl-mvp-026.ps1` el instalador base se detuvo antes de las pruebas porque su inventario
de cambios permitidos todavía no reconocía los archivos de los correctivos D y E.

El bloqueo observado fue exclusivamente de gobernanza/inventario. No es un fallo funcional de login,
cookie, CSRF, PostgreSQL ni del cambio aplicado por BL-MVP-026D.

## Decisión

Los correctivos de este proyecto forman parte del historial técnico del repositorio. Por tanto, no se
eliminan para satisfacer la puerta. BL-MVP-026F amplía de forma controlada el inventario permitido del
instalador base para reconocer los artefactos D, E y F.

## Alcance

BL-MVP-026F:

- modifica solamente `scripts/apply-bl-mvp-026.ps1`;
- agrega al inventario permitido las instrucciones, README e instaladores de 026D, 026E y 026F;
- no modifica la lógica de login, cookies, CSRF, base de datos, Nginx, Docker ni pruebas;
- valida la sintaxis del instalador base mediante el parser de PowerShell;
- ejecuta `git diff --check`;
- es idempotente: si las rutas ya están autorizadas no las duplica;
- no ejecuta `git add`, commit ni push.

Después debe ejecutarse nuevamente la puerta completa:

```powershell
.\scripts\apply-bl-mvp-026.ps1
```

No usar opciones `Skip*`.
