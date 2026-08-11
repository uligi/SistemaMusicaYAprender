import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

test.describe('BL-MVP-031 · gestión de asignaciones de roles', () => {
  test('asigna y retira con motivo sin usar la visibilidad como autorización', async ({ page }) => {
    const target = '11111111-1111-4111-8111-111111111111';
    const assignmentId = '22222222-2222-4222-8222-222222222222';
    let assignment: Record<string, unknown> | null = null;

    await page.route('**/api/v1/auth/session', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'AUTHENTICATED',
          role: 'STUDENT',
          roles: ['STUDENT', 'ADMIN'],
          capabilities: ['PROFILE.READ', 'SECURITY.MANAGE_ROLES'],
        }),
      });
    });

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-role-management-e2e',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });

    await page.route('**/api/v1/security/role-assignments/catalog', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          roles: ['ADMIN', 'EDITOR', 'REVIEWER', 'STUDENT'],
          scopes: [],
        }),
      });
    });

    await page.route(`**/api/v1/security/role-assignments/${target}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(assignment ? [assignment] : []),
      });
    });

    await page.route('**/api/v1/security/role-assignments', async (route) => {
      if (route.request().method() !== 'POST') {
        await route.fallback();
        return;
      }

      const body = route.request().postDataJSON() as {
        accountId: string;
        roleCode: string;
        reason: string;
      };
      expect(body.accountId).toBe(target);
      expect(body.roleCode).toBe('EDITOR');
      expect(body.reason).toBe('Curaduría de catálogo');
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-role-management-e2e');

      assignment = {
        assignmentId,
        accountId: target,
        roleCode: 'EDITOR',
        scope: null,
        validFrom: '2026-08-11T02:00:00Z',
        validTo: null,
        reason: body.reason,
        state: 'ACTIVE',
      };

      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({ assignment, alreadyApplied: false }),
      });
    });

    await page.route(
      `**/api/v1/security/role-assignments/${assignmentId}/revoke`,
      async (route) => {
        const body = route.request().postDataJSON() as { reason: string };
        expect(body.reason).toBe('Fin de la responsabilidad');
        expect(route.request().headers()['x-csrf-token']).toBe('csrf-role-management-e2e');

        assignment = {
          ...(assignment ?? {}),
          validTo: '2026-08-11T03:00:00Z',
          state: 'EXPIRED',
        };

        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ assignment, alreadyApplied: false }),
        });
      },
    );

    await page.goto('/administracion/roles');

    await expect(page.getByRole('heading', { level: 1, name: 'Roles y permisos' })).toBeVisible();

    await page.getByLabel('Cuenta objetivo').fill(target);
    await page.getByLabel('Rol *', { exact: true }).selectOption('EDITOR');
    await page.getByRole('textbox', { name: 'Motivo', exact: true }).fill('Curaduría de catálogo');
    await page.getByRole('button', { name: 'Asignar rol' }).click();

    await expect(page.getByText('Asignación aplicada y auditada.')).toBeVisible();
    await expect(
      page.getByLabel('Asignaciones de la cuenta').getByText('EDITOR', { exact: true }),
    ).toBeVisible();

    await page.getByLabel('Motivo para retirar').fill('Fin de la responsabilidad');
    await page.getByRole('button', { name: 'Retirar' }).click();

    await expect(page.getByText('Asignación retirada y auditada.')).toBeVisible();
    await expect(page.getByText('Estado: EXPIRED')).toBeVisible();

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
