# BL-MVP-031B — corregir formato Markdown de 031A

## Primera falla observada

Después de corregir el tipo de los headers CSRF, la puerta completa de BL-MVP-031 avanzó hasta
`npm run format:check` y se detuvo únicamente en:

```text
README/BL-MVP-031A_README.md
```

TypeScript ya quedó aprobado en esa ejecución.

## Corrección

BL-MVP-031B usa el Prettier local fijado por el repositorio para formatear y validar:

- `README/BL-MVP-031A_README.md`;
- `README/BL-MVP-031B_README.md`;
- `INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031B.md`.

La puerta base queda reconciliada para reconocer los artefactos 031B.

No cambia C#, TypeScript, PostgreSQL, autorización, auditoría, UI ni pruebas.
