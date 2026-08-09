# BL-MVP-012 — Separar identidades de migración, aplicación y solo lectura

**Fase:** F0 — Cimientos  
**Épica:** EP-01 — Datos, persistencia e integración  
**Tipo:** Habilitador  
**Traza:** SEG; DDC; RNF-MVP-046-067  
**SP:** 5  
**Dependencias:** BL-MVP-010, BL-MVP-011

Resultado aceptable: **la API no posee permisos de propietario/migrador y cada cuenta recibe únicamente grants necesarios.**

## Qué implementa

- cinco identidades PostgreSQL `LOGIN` separadas;
- seis roles funcionales existentes permanecen `NOLOGIN`;
- secreto independiente por identidad;
- API usa `jp_login_api -> jp_app`;
- Worker usa `jp_login_worker -> jp_worker`;
- migrador explícito usa `jp_login_migrator -> jp_migrator -> jp_owner`;
- readonly solo hereda `jp_readonly`;
- backoffice queda como credencial/pool separado y no se monta en la API ordinaria;
- `musica_local` queda reservado para bootstrap/DBA local;
- migración vacía y CI se ejecutan con la identidad de migración, no con la cuenta administrativa;
- pruebas positivas y negativas de privilegios;
- matriz de acceso y evidencia CI.

## No pertenece a BL-MVP-012

La propagación transaccional de `app.account_id`, rol y correlación para RLS corresponde a BL-MVP-013.

## Aplicación

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-012.ps1
```

No haga commit hasta completar las validaciones indicadas por el script.
