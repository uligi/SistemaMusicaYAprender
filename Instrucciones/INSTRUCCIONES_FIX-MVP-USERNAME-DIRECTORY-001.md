# Instalación local — FIX-MVP-USERNAME-DIRECTORY-001

Base exacta preparada: `80b2e3cf94b4a23b4175c970b316b1ed1cb3bc7d`.

1. Copia el instalador a `scripts/apply-fix-username-directory-001.ps1`.
2. Ejecuta desde la raíz con el working tree limpio.
3. El instalador no ejecuta `git add`, `commit`, `push` ni cambia de rama.
4. Revisa el diff antes de ejecutar gates.
5. La nueva migración debe aplicarse reiniciando el stack local.
6. No avanzar BL-MVP-080 hasta cerrar el correctivo.

Prueba manual principal:

1. registra/verifica una segunda cuenta con username;
2. entra como ADMIN con MFA;
3. en Roles y accesos busca esa cuenta por `@username`;
4. asigna `REVIEWER`;
5. vuelve a UI027 y comprueba que el selector muestra `@username`.
