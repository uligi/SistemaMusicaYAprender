BL-MVP-003A - Correccion de puerta de calidad

Problema corregido:
Windows PowerShell 5.1 no convierte automaticamente un codigo de salida distinto de 0
de programas nativos (dotnet/npm) en una excepcion, incluso con $ErrorActionPreference='Stop'.
Por eso el script anterior podia mostrar 'OK' despues de una compilacion fallida.

Copie el contenido de la carpeta scripts sobre la carpeta scripts del repositorio y reemplace
los cuatro archivos. Luego ejecute:

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\check-quality.ps1

Ahora cualquier fallo de restore, npm, formato, build o pruebas detiene la puerta inmediatamente.
