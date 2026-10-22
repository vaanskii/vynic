/** Explicit host routing keeps customer and operator sessions on separate origins. */
export function isAdminHost(hostname: string): boolean {
  return [
    "admin.vynic.ge",
    "admin.localhost",
    "admin.vynic.localhost",
  ].includes(hostname.toLowerCase().replace(/\.$/, ""));
}

type SiteLocation = Pick<Location, "hostname" | "protocol" | "port">;

export function siteOrigins(location: SiteLocation = window.location) {
  const hostname = location.hostname.toLowerCase().replace(/\.$/, "");
  const local =
    hostname === "localhost" ||
    hostname.endsWith(".localhost") ||
    hostname === "127.0.0.1" ||
    hostname === "[::1]";
  if (!local)
    return { public: "https://vynic.ge", admin: "https://admin.vynic.ge" };
  const base = hostname.endsWith("vynic.localhost")
    ? "vynic.localhost"
    : "localhost";
  const port = location.port ? `:${location.port}` : "";
  return {
    public: `${location.protocol}//${base}${port}`,
    admin: `${location.protocol}//admin.${base}${port}`,
  };
}

export function publicSiteUrl(path = "/") {
  return new URL(path, siteOrigins().public).href;
}
