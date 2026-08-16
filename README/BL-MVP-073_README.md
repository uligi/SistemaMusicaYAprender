# BL-MVP-073 · Instancia congelada y reanudable de ejercicio

## Resultado aceptable

> La instancia fija revisión, orden de opciones y contexto; reabrir no cambia lo ya presentado.

BL-MVP-073 materializa `UI-MVP-012` sobre una sesión privada ya creada por BL072.

## Alcance

- prepara únicamente un `FILL_BLANK_OPTIONS` incluido en la publicación exacta de la sesión;
- crea una sola `learning.exercise_instance` con `instance_no = 1`;
- congela la `exercise_revision` exacta;
- genera una semilla una vez y copia únicamente opciones visibles a `learning.exercise_instance_item`;
- el orden se guarda en `display_order` y no se vuelve a barajar al recargar;
- reconstruye el espacio desde el token canónico de la revisión publicada;
- usa `jp_app` + RLS de propietario;
- la creación exige CSRF y las lecturas privadas usan `Cache-Control: private, no-store`;
- no expone `solution_spec`, `expected_value`, rol `CORRECT`, explicación ni feedback editorial.

## Frontera

BL073 no evalúa, no crea evidencia y no actualiza progreso. La confirmación de respuesta corresponde a BL074; la evaluación reproducible empieza en BL075.

## Verificación

```powershell
$env:PGUSER = "musica_local"
$env:PGDATABASE = "musica_aprender"
$env:BL073_USE_DOCKER_PSQL = "true"

& "C:\Program Files\Git\bin\bash.exe" scripts/ci/learning/verify-exercise-instance-freeze.sh
```
