# BL-MVP-072 · Iniciar una sesión de estudio

## Resultado

`UI-MVP-011` deja de ser un placeholder y permite a una persona autenticada iniciar una sesión privada únicamente sobre una canción con publicación vigente y al menos un ejercicio incluido en la publicación.

La operación:

- usa el pool normal `jp_app` y las políticas RLS de propietario;
- valida publicación, disponibilidad pública y componente `EXERCISE` canónico;
- usa CSRF e `Idempotency-Key`;
- conserva una sola sesión lógica ante doble activación;
- crea `learning.learner_profile` si la cuenta todavía no posee uno;
- escribe únicamente `learning.study_session` y el registro técnico de idempotencia;
- no crea respuesta, nota, actividad evaluada, evidencia ni progreso.

## Frontera

BL-MVP-072 **no inicia sesiones reales desde DRAFT**. Un ejercicio editorial guardado por BL071 solo será elegible cuando forme parte de una publicación válida. Tampoco crea todavía la instancia congelada del ejercicio: eso corresponde a BL-MVP-073.

## UX

La pantalla usa lenguaje directo:

- `Practicar esta canción`;
- `Tu sesión es privada`;
- `Empezar a practicar`;
- un estado explícito cuando todavía no existe práctica publicada;
- un estado explícito cuando ya existe una sesión en curso.

No hay temporizador obligatorio.

## Verificación

```powershell
$env:PGUSER = "musica_local"
$env:PGDATABASE = "musica_aprender"
$env:BL072_USE_DOCKER_PSQL = "true"

& "C:\Program Files\Git\bin\bash.exe" scripts/ci/learning/verify-study-session-start.sh

npm.cmd run test:e2e -- study-session-start.spec.ts --project=chromium-320
```
