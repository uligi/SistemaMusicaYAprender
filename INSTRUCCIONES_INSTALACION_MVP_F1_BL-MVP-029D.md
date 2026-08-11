# Instalación — BL-MVP-029D

Rama: `main`

HEAD esperado:

`147e86ffe9b53435d7f277282f6c091aef3523d0`

Extrae `BL-MVP-029D_Paquete_Correctivo.zip` sobre la raíz y ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-029d.ps1
```

Resultado esperado:

```text
OK: BL-MVP-029 limites 5/cuenta y 20/IP, recuperacion independiente, eventos y sesion revocable verificados.
OK: BL-MVP-029D validado con umbrales 5/20 y recuperacion desacoplada del costo Argon2id.
```

Después ejecuta nuevamente:

```powershell
.\scripts\apply-bl-mvp-029.ps1
```

Sin `Skip*`. No ejecutar staging, commit ni push hasta GREEN completo.
