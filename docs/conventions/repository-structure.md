# Convención de estructura del repositorio

```text
apps/             Puntos de entrada desplegables: web, API y worker.
src/BuildingBlocks/ Primitivas compartidas sin lógica de negocio de módulos.
src/Modules/      Módulos funcionales P0 del monolito modular.
tests/            Unitarias, integración, arquitectura y E2E.
infrastructure/   Docker, PostgreSQL, observabilidad, objetos y SMTP.
docs/             Arquitectura, ADR y convenciones.
scripts/          Automatización reproducible para desarrollo y CI.
```

## Reglas

1. La lógica de negocio vive en su módulo propietario.
2. Ningún módulo referencia otro módulo mediante `ProjectReference`.
3. API y worker son raíces de composición; no contienen reglas de dominio.
4. BuildingBlocks contiene mecanismos genéricos, no entidades del producto.
5. Un módulo se comunica mediante contrato de aplicación o evento versionado.
6. Los proyectos diferidos no se representan mediante carpetas o ensamblados vacíos.
7. Los secretos, datos locales y artefactos generados nunca se confirman al repositorio.
