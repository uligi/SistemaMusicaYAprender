const usernamePattern = /^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$/;

const reservedUsernames = new Set([
  'admin',
  'administrator',
  'api',
  'editor',
  'moderator',
  'musicayaprender',
  'reviewer',
  'root',
  'security',
  'support',
  'system',
  'www',
]);

export function normalizeUsername(value: string): string {
  return value.trim().toLocaleLowerCase('en-US');
}

export function usernameError(value: string): string | undefined {
  const normalized = normalizeUsername(value);

  if (!normalized) return 'Escribe un nombre de usuario.';
  if (normalized.length < 3 || normalized.length > 32) {
    return 'Usa entre 3 y 32 caracteres.';
  }
  if (!usernamePattern.test(normalized)) {
    return 'Usa letras a-z, números, punto, guion o guion bajo; empieza y termina con letra o número.';
  }
  if (reservedUsernames.has(normalized)) {
    return 'Ese nombre está reservado por el sistema. Elige otro.';
  }

  return undefined;
}

export function normalizeDirectoryQuery(value: string): string {
  return normalizeUsername(value.replace(/^@+/, ''));
}
