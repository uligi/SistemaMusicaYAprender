# BL-MVP-031A — corregir tipo de headers CSRF

## Primera falla observada

La puerta inicial de BL-MVP-031 llegó hasta `npm run typecheck` y falló únicamente en
`RoleManagementPage.tsx`:

```text
TS2322: Type 'HeadersInit' is not assignable to type
'Readonly<Record<string, string>> | undefined'.
```

Los errores se producen al pasar el resultado de `csrfHeaders()` a las dos mutaciones del cliente
HTTP.

## Causa

`csrfHeaders()` se declaró como:

```ts
Promise<HeadersInit | null>;
```

pero el contrato ya existente del cliente tipado usa:

```ts
headers?: Readonly<Record<string, string>>;
```

`HeadersInit` es una unión más amplia que también admite `Headers` y tuplas `[string, string][]`;
TypeScript no puede garantizar que esas variantes satisfagan `Readonly<Record<string, string>>`.

## Corrección

BL-MVP-031A estrecha únicamente el retorno de `csrfHeaders()` a:

```ts
Promise<Readonly<Record<string, string>> | null>;
```

La función ya devuelve un objeto `{ [headerName]: requestToken }`, por lo que el nuevo tipo describe
exactamente el valor real y el contrato de `HttpRequestOptions`.

No cambia la lógica CSRF, la API, PostgreSQL, autorización, auditoría ni la UI.

## Validación

031A ejecuta el Prettier local del repositorio, `npm run typecheck`, restaura defensivamente
`tsconfig.app.tsbuildinfo` y ejecuta `git diff --check`.
