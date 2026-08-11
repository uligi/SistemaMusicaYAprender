# Instalación — BL-MVP-029A

## Precondición

Repositorio:

`C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender`

Rama: `main`

HEAD:

`147e86ffe9b53435d7f277282f6c091aef3523d0`

La primera ejecución de BL-MVP-029 debe haberse detenido en `npm run format:check` por estos dos
archivos:

- `docs/engineering/security/login-abuse-and-session-limits.md`
- `tests/E2ETests/personal-login-abuse.spec.ts`

## Extracción

Extrae `BL-MVP-029A_Paquete_Correctivo.zip` directamente sobre la raíz del repositorio, sin carpeta
envolvente.

El ZIP incluye:

- los dos archivos completos afectados;
- `scripts/apply-bl-mvp-029.ps1` completo, reconciliado para aceptar 029A;
- el instalador 029A;
- README e instrucciones.

## Ejecución

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-029a.ps1
```

Resultado esperado:

```text
Prettier local: 3.9.6
OK: Prettier aprobo los dos archivos afectados.
OK: TypeScript E2E aprobado.
OK: git diff --check aprobado.
OK: BL-MVP-029A aplicado y validado.
```

Después ejecuta nuevamente, sin `Skip*`:

```powershell
.\scripts\apply-bl-mvp-029.ps1
```

No ejecutar staging, commit ni push hasta que la puerta BL-MVP-029 completa termine GREEN.
