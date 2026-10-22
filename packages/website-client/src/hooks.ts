import type { WebsiteClient } from "./client";
import { SiteUnavailableError } from "./client";
import { gateSite, type SiteGate } from "./site";
import type { CustomSiteMenu, TableAvailability } from "./types";

/** The two React hooks this module needs, injected so the package has no React dependency. */
export type HookRuntime = {
  useState: <S>(initial: S | (() => S)) => [S, (next: S) => void];
  useEffect: (effect: () => void | (() => void), deps: readonly unknown[]) => void;
};

export type Resource<T> =
  | { state: "loading" }
  | { state: "ready"; data: T }
  | { state: "unavailable" }
  | { state: "error"; error: Error };

/**
 * Data hooks shared by custom frontends: loading/unavailable/error states
 * without imposing any markup. Pass React's hooks and a client once:
 *
 *     const hooks = createWebsiteHooks(React, createWebsiteClient());
 */
export function createWebsiteHooks(react: HookRuntime, client: WebsiteClient) {
  function useResource<T>(load: () => Promise<T>, deps: readonly unknown[]) {
    const [resource, setResource] = react.useState<Resource<T>>({
      state: "loading",
    });
    react.useEffect(() => {
      let live = true;
      setResource({ state: "loading" });
      load().then(
        (data) => live && setResource({ state: "ready", data }),
        (error: Error) =>
          live &&
          setResource(
            error instanceof SiteUnavailableError
              ? { state: "unavailable" }
              : { state: "error", error },
          ),
      );
      return () => {
        live = false;
      };
    }, deps);
    return resource;
  }

  return {
    useResource,
    /** Bootstrap, gated by this build's own frontend identity. */
    useSite(siteKey: string): Resource<SiteGate> {
      return useResource(
        async () => gateSite(await client.bootstrap(), siteKey),
        [siteKey],
      );
    },
    useMenu(enabled = true): Resource<CustomSiteMenu | null> {
      return useResource(
        async () => (enabled ? client.menu() : null),
        [enabled],
      );
    },
    useAvailability(date: string | null): Resource<TableAvailability[]> {
      return useResource(
        async () => (date ? client.availability(date) : []),
        [date],
      );
    },
  };
}
