# BL-MVP-031I — servir un build actualizado en el E2E aislado

## Diagnóstico

031H cambió `RoleManagementPage.tsx` y luego ejecutó directamente un spec Playwright aislado.

El `playwright.config.ts` del repositorio inicia:

```text
npm run preview --workspace @musica-aprender/web
```

cuando no existe `PLAYWRIGHT_TEST_BASE_URL`.

`vite preview` sirve `apps/web/dist`; no transpila de nuevo el código fuente. Por tanto, ejecutar un
spec aislado después de cambiar `src/` sin ejecutar antes `npm run build` puede probar un `dist`
anterior.

Esto explica por qué 031H volvió a observar exactamente el comportamiento previo aunque su
TypeScript fuente ya contenía la corrección.

## Corrección

031I no modifica la lógica del producto. Corrige la validación aislada:

1. `npm run typecheck`;
2. `npm run build`;
3. `npm run typecheck:e2e`;
4. Playwright únicamente sobre `role-management.spec.ts`;
5. restauración de `tsconfig.app.tsbuildinfo`;
6. `git diff --check`.

La puerta completa `apply-bl-mvp-031.ps1` ya pasa por `check-quality.ps1`, que construye el frontend
antes del conjunto E2E; el defecto estaba en los correctivos aislados que invocaban Playwright sobre
`vite preview` sin regenerar `dist`.
