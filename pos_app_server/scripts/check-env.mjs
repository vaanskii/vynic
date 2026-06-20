/**
 * Print .env checklist before first deploy (optional — server also bootstraps on start).
 *   npm run check:env
 */
import 'dotenv/config';

const CHECKS = [
  { key: 'DATABASE_URL', required: true },
  { key: 'JWT_SECRET', required: true },
  { key: 'POS_SYNC_API_KEY', required: true },
  { key: 'JWT_REFRESH_SECRET', required: false },
  { key: 'COOKIE_ENCRYPTION_KEY', required: true },
  { key: 'BOG_CLIENT_ID', required: false },
  { key: 'BOG_CLIENT_SECRET', required: false },
  { key: 'FRONTEND_URL', required: false },
  { key: 'API_URL', required: false },
  // Website SUPER_ADMIN seed (optional). Each accepts either name —
  // bootstrap.service.ts reads WEBSITE_ADMIN_* first, then falls back to SUPER_ADMIN_*.
  // Phone + password must both be set for an admin to be seeded; email defaults if omitted.
  { keys: ['WEBSITE_ADMIN_PHONE', 'SUPER_ADMIN_PHONE'], required: false },
  { keys: ['WEBSITE_ADMIN_PASSWORD', 'SUPER_ADMIN_PASSWORD'], required: false },
  { keys: ['WEBSITE_ADMIN_EMAIL', 'SUPER_ADMIN_EMAIL'], required: false },
];

let failed = false;
console.log('\n=== Env checklist ===\n');
for (const check of CHECKS) {
  const keys = check.keys ?? [check.key];
  const ok = keys.some((k) => Boolean(process.env[k]?.trim()));
  const label = keys.join(' | ');
  console.log(`  ${ok ? '✓' : check.required ? '✗' : '○'} ${label}`);
  if (check.required && !ok) failed = true;
}
console.log('\n  Menu — synced from POS, not from .env');
console.log('  Website tables + admin — seeded automatically on server start\n');
process.exit(failed ? 1 : 0);
