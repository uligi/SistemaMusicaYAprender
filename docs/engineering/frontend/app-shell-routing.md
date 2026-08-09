# App shell, rutas y fronteras visibles · BL-MVP-020

## Contrato

La fuente normativa de BL-MVP-020 exige UI-MVP-001-032, compatibilidad y accesibilidad. El resultado
aceptable es que existan áreas pública, estudiante, editorial y administración con carga por ruta y que
el servidor continúe siendo la autoridad.

## Arquitectura

`AppRouter` lee `window.location` y resuelve el manifiesto sin almacenar credenciales ni sesión en URL.
`AppLink` conserva un `href` real para semántica y fallback, pero usa History API en navegación interna.
El Nginx existente mantiene `try_files $uri $uri/ /index.html;`, por lo que una recarga directa de una
ruta cliente vuelve a `index.html`.

Las áreas son `React.lazy`. El manifiesto contiene exactamente las 32 rutas del diseño de interfaz.

## Frontera visible de acceso

`AccessBoundary` solo decide qué experiencia puede mostrarse. No es autorización de negocio.

- Público: visible sin sesión.
- Público/estudiante: contenido elegible visible; persistencia sigue requiriendo sesión.
- Estudiante: exige snapshot autenticado.
- Editorial/administración: exige capacidades efectivas concretas.

No se concede acceso por nombre de rol. `BackofficeShell` calcula navegación desde capacidades como
`lyrics:edit`, `publication:review` o `audit:read`. Las historias F1 conectarán estas capacidades con la
sesión del servidor.

El snapshot inicial es anónimo y no usa `localStorage` ni `sessionStorage`.

## Accesibilidad

- enlace “Saltar al contenido”;
- landmarks `header`, `nav`, `main`, `footer`;
- `aria-current="page"` en navegación;
- foco al `h1` cuando cambia la ruta;
- estado propio para rutas inexistentes;
- UI-EST-07/UI-EST-08 para fronteras de sesión/capacidad;
- navegación adaptable a 320 px;
- movimiento reducido heredado de tokens.

## Convenciones

Las rutas públicas usan slugs. Las editoriales usan identificadores opacos. El manifiesto no transporta
correos, credenciales, notas ni secretos. Una ruta desconocida no redirige silenciosamente.
