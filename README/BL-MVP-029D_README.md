# BL-MVP-029D — smoke determinista para umbrales 5/20

## Motivo

La puerta completa posterior a 029C aprobó formato, compilaciones, Playwright 14/14, unitarias 21/21,
arquitectura, PostgreSQL, Docker y las regresiones BL-MVP-026/027. El único fallo restante fue:

```text
ERROR: BL-MVP-029: límite por cuenta conocida esperaba '429' y obtuvo '401'.
```

El smoke original usaba una ventana artificial de solo 30 segundos tanto para verificar los
umbrales como para verificar expiración. Cada intento de login ejecuta Argon2id deliberadamente,
incluidos los rechazos, por lo que en una máquina real el primer fallo puede envejecer fuera de esos
30 segundos antes de llegar al sexto intento.

## Corrección

No se cambia el backend ni la configuración productiva.

El smoke se separa en dos fases:

- **Umbrales:** ventana de prueba 300 s, límites exactos 5/cuenta y 20/cliente. Después de los cinco
  fallos conocidos se consulta PostgreSQL y se exigen exactamente cinco eventos persistidos antes
  de pedir el sexto 429.
- **Recuperación:** se reinicia solo la API standalone con una ventana de prueba de 5 s, correlación,
  cuenta y cliente nuevos. Se demuestra 5 fallos → 429 → expiración → 401.

Luego continúa el login válido, los límites de sesión <=12 h / <=30 días y la revocación.

Los defaults de producción siguen siendo 5, 20 y 900 segundos.
