# BL-MVP-020A · Corrección TypeScript del matcher de rutas

Corrección puntual posterior al primer apply de BL-MVP-020.

## Error observado

TypeScript estricto informó `TS18048` en `match-route.ts` porque, con acceso indexado estricto, una lectura
`array[index]` conserva el tipo `string | undefined` aunque el código haya comprobado previamente que los dos
arrays tienen la misma longitud.

El problema no estaba en el manifiesto ni en las rutas. Era una obligación de narrowing del compilador.

## Corrección

`matchPath` ahora valida explícitamente:

```ts
if (expected === undefined || actual === undefined) {
  return null;
}
```

antes de llamar `startsWith`, `endsWith` o comparar los segmentos.

No cambia:

- las 32 rutas;
- la lógica de parámetros;
- las fronteras visibles de acceso;
- la carga lazy;
- CI;
- dependencias;
- backend;
- SQL;
- migraciones.

Después de sobrescribir el archivo, volver a ejecutar:

```powershell
.\\scripts\\apply-bl-mvp-020.ps1
```
