# BL-MVP-030K — corregir formato Markdown de 030J

## Motivo

La puerta completa de BL-MVP-030 volvió a avanzar hasta `npm run format:check` y se detuvo
únicamente porque Prettier reportó:

```text
README/BL-MVP-030J_README.md
```

El código de aplicación no produjo un nuevo fallo en esa ejecución.

## Corrección

030K usa el Prettier local fijado por el repositorio (`3.9.6`) y formatea:

- `README/BL-MVP-030J_README.md`;
- `README/BL-MVP-030K_README.md`;
- `INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030K.md`.

Después ejecuta `prettier --check` sobre esos mismos archivos y `git diff --check`.

La puerta principal queda reconciliada para reconocer los artefactos 030K.

No cambia código C#, TypeScript, pruebas, permisos, sesiones, PostgreSQL ni CI.
