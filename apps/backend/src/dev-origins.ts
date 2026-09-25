const DEV_CLIENT_PORTS = new Set(['5173', '5174', '4173']);
const LAN_ORIGIN =
  /^https?:\/\/(localhost|admin\.localhost|vynic\.localhost|admin\.vynic\.localhost|127\.0\.0\.1|192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})(:\d+)?$/;

/** Development only; main.ts requires explicit configured origins in production. */
export function isDevLanOrigin(origin: string): boolean {
  if (!LAN_ORIGIN.test(origin)) return false;
  const port = origin.match(/:(\d+)$/)?.[1] ?? '80';
  return DEV_CLIENT_PORTS.has(port);
}
