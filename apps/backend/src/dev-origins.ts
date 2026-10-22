// Leave room for concurrent Vite apps to advance past occupied dev ports.
const DEV_CLIENT_PORT_MIN = 5173;
const DEV_CLIENT_PORT_MAX = 5273;
const LAN_ORIGIN =
  /^https?:\/\/(localhost|admin\.localhost|vynic\.localhost|admin\.vynic\.localhost|127\.0\.0\.1|192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})(:\d+)?$/;

/** Development only; main.ts requires explicit configured origins in production. */
export function isDevLanOrigin(origin: string): boolean {
  if (!LAN_ORIGIN.test(origin)) return false;
  const port = Number(origin.match(/:(\d+)$/)?.[1] ?? '80');
  return (
    port === 4173 ||
    (port >= DEV_CLIENT_PORT_MIN && port <= DEV_CLIENT_PORT_MAX)
  );
}
