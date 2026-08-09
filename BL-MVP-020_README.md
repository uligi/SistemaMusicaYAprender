# BL-MVP-020 · App shell, rutas y fronteras visibles de acceso

## Ficha normativa

- Fase: F0 — Cimientos
- Épica: EP-02 — Sistema de diseño y cliente base
- ID: BL-MVP-020
- Tipo: Habilitador
- Traza: UI-MVP-001-032; COM; ACC
- Story Points: 8
- Dependencias: BL-MVP-018 y BL-MVP-019
- Resultado aceptable: “Existen áreas pública, estudiante, editorial y administración con carga por ruta; el servidor sigue siendo autoridad.”

## Alcance implementado

BL-MVP-020 reemplaza el catálogo temporal de BL-MVP-019 como pantalla principal y construye el arnés de navegación real del cliente:

- manifiesto exacto de UI-MVP-001 a UI-MVP-032;
- enrutamiento cliente sin dependencia externa adicional;
- `React.lazy` para las áreas pública, estudiante, editorial y administración;
- fallback de ruta propia, sin redirección silenciosa;
- encabezado público;
- navegación del estudiante con Explorar, Aprender, Progreso y Preferencias;
- shell de backoffice por capacidades efectivas;
- frontera visible de acceso para rutas de estudiante y backoffice;
- salto accesible al contenido principal;
- foco al título de cada ruta;
- preservación del fallback de Nginx para rutas directas.

La interfaz puede decidir qué navegación mostrar, pero **nunca concede autorización**. El snapshot de acceso visible parte en modo anónimo y no se persiste en `localStorage` ni `sessionStorage`. Las historias de identidad posteriores conectarán el snapshot con la sesión emitida por el servidor. Cada endpoint protegido debe volver a autorizar en backend.

## Carga por ruta

Las cuatro áreas se importan con `React.lazy`:

- `routes/public/PublicArea.tsx`
- `routes/student/StudentArea.tsx`
- `routes/editorial/EditorialArea.tsx`
- `routes/administration/AdministrationArea.tsx`

Una ruta protegida no renderiza su bundle de área si la frontera visible no encuentra sesión/capacidad. Esto reduce carga y mantiene explícita la frontera, pero no se considera un control de seguridad del servidor.

## Validación

```powershell
node .\scripts\frontend\verify-design-tokens.mjs
node .\scripts\frontend\verify-accessible-components.mjs
node .\scripts\frontend\verify-app-shell.mjs
npm.cmd run typecheck
npm.cmd run build
```

Después de aplicar:

```powershell
.\scripts\local\start.ps1
.\scripts\local\verify-running.ps1
```

Pruebas manuales sugeridas:

1. `/` carga el área pública.
2. `/canciones` y `/canciones?consulta=kaiju` resuelven rutas diferentes del manifiesto.
3. `/preferencias` muestra frontera de sesión sin cargar la experiencia protegida.
4. `/editorial` muestra frontera de acceso anónima y no concede entrada por conocer la URL.
5. `/administracion/auditoria` tampoco concede acceso por URL.
6. una ruta inexistente muestra estado propio y no redirige.
7. Tab alcanza “Saltar al contenido” y el foco sigue siendo visible.
8. a 320 px no aparece scroll horizontal y la navegación refluye.
