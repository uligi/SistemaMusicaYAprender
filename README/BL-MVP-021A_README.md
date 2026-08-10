# BL-MVP-021A — Corrección del verificador para TypeScript 7

## Problema observado

El primer `apply-bl-mvp-021.ps1` falló en el verificador BL-MVP-021 antes de llegar al typecheck real:

```text
TypeError: Cannot read properties of undefined (reading 'ES2022')
```

La causa era el uso del Compiler API JavaScript clásico desde:

```js
import ts from 'typescript';
ts.transpileModule(...)
ts.ScriptTarget.ES2022
```

El proyecto usa TypeScript 7, cuyo compilador es la implementación nativa. El verificador no debe depender del Compiler API JavaScript heredado.

## Corrección

`scripts/frontend/verify-http-client.mjs` ahora:

- no importa `typescript` como biblioteca JavaScript;
- genera un `tsconfig.runtime.json` temporal;
- invoca el `tsc` instalado por el propio proyecto mediante `npm exec -- tsc`;
- emite únicamente los módulos runtime del cliente HTTP a un directorio temporal;
- ejecuta sobre ese JavaScript emitido los mismos escenarios conductuales de BL-MVP-021;
- elimina el directorio temporal al finalizar.

El `apply` continúa ejecutando después el `npm run typecheck` real del repositorio, por lo que el compilador y `tsconfig.app.json` del proyecto siguen siendo la autoridad para el typecheck completo.

## Alcance

Esta corrección NO cambia:

- cliente HTTP;
- ProblemDetails;
- ETag/If-Match;
- política de reintentos;
- caché;
- nginx;
- CI;
- dependencias;
- backend;
- SQL;
- migraciones.

Solo corrige el arnés de verificación BL-MVP-021 para que sea compatible con el toolchain TypeScript 7 del repositorio.
