# Limpieza de repositorio — temporal Office

El commit `77d182bd75b7ac74e2021cc305090ddaa2d9183c` movió correctamente los README históricos,
pero también agregó accidentalmente:

`sistema de musica/~$cklog_Implementacion_MVP.docx`

Ese archivo es un lock/temporal de Microsoft Word y no debe mantenerse en el repositorio.

La corrección:

- agrega `~$*.docx` a `.gitignore`;
- elimina el temporal del working tree si todavía existe;
- deja la eliminación sin staging;
- no altera los README movidos;
- no ejecuta `git add`, commit ni push.
