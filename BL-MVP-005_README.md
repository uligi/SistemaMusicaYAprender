# BL-MVP-005 — Plantillas de issue, PR y trazabilidad

Resultado esperado del backlog: cada issue exige fase, épica, CU/CA o RNF, dependencia, criterios,
evidencia y riesgo de datos/seguridad.

Este incremento agrega:

```text
.github/
├── ISSUE_TEMPLATE/
│   ├── config.yml
│   └── implementation.yml
└── pull_request_template.md

scripts/
└── governance/
    ├── check-templates.ps1
    └── check-templates.sh

docs/
└── engineering/
    ├── governance/
    │   └── README.md
    └── traceability/
        └── README.md
```

También integra la verificación de gobierno en la puerta local y en CI.

## Aplicación

Copie el contenido del ZIP sobre la raíz del repositorio y reemplace archivos. Luego:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-005.ps1
```

Si termina con `OK: puerta local BL-MVP-005 aprobada.`:

```powershell
git status
git add .
git commit -m "chore: configurar trazabilidad GitHub BL-MVP-005"
git push origin main
```

Después del CI verde, abra **Issues -> New issue** y confirme que aparece el formulario
`Implementación BL-MVP` y que no existe la opción de issue en blanco.
