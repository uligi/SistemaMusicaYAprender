# Instalación — BL-MVP-031A

Base requerida:

`3f1ae3d64b3a0c20c5b2ba1af7003a9cc4b305af`

Rama: `main`.

Extrae `BL-MVP-031A_Paquete_Correctivo.zip` directamente sobre la raíz del repositorio.

Ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-031a.ps1
```

Resultado esperado:

```text
OK: headers CSRF alineados con HttpRequestOptions.
OK: RoleManagementPage formateado.
OK: TypeScript aprobado.
OK: git diff --check aprobado.
OK: BL-MVP-031A aplicado y validado.
```

Después vuelve a ejecutar la puerta completa:

```powershell
.\scripts\apply-bl-mvp-031.ps1
```

Sin `Skip*`. No ejecutar `git add`, commit ni push hasta que BL-MVP-031 esté GREEN localmente y se
revise el inventario.
