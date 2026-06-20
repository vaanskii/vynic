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
  { key: 'COOKIE_ENCRYPTION_KEY', required: false },
  { key: 'BOG_CLIENT_ID', required: false },
  { key: 'BOG_CLIENT_SECRET', required: false },
  { key: 'FRONTEND_URL', required: false },
  { key: 'API_URL', required: false },
  { key: 'WEBSITE_ADMIN_PHONE', required: false },
  { key: 'WEBSITE_ADMIN_PASSWORD', required: false },
];

let failed = false;
console.log('\n=== Env checklist ===\n');
for (const { key, required } of CHECKS) {
  const ok = Boolean(process.env[key]?.trim());
  console.log(`  ${ok ? '✓' : required ? '✗' : '○'} ${key}`);
  if (required && !ok) failed = true;
}
console.log('\n  Menu — synced from POS, not from .env');
console.log('  Website tables + admin — seeded automatically on server start\n');
process.exit(failed ? 1 : 0);
