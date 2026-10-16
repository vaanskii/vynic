import { useEffect, useState, type ReactNode } from "react";
import { useLocation } from "react-router-dom";
import api from "../services/api";
import {
  readWebsiteInfo,
  type WebsiteInfoState,
} from "../services/website-info";
import { websiteInfoContext } from "./WebsiteInfoContext";

export function WebsiteInfoProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<WebsiteInfoState>({ kind: "loading" });
  const [revision, setRevision] = useState(0);
  const { pathname } = useLocation();
  useEffect(() => {
    let active = true;
    const controller = new AbortController();
    setState({ kind: "loading" });
    void api
      .get<unknown>("/website/venue", {
        signal: controller.signal,
        adapter: "fetch",
        fetchOptions: { cache: "no-cache" },
      })
      .then(({ data }) => {
        if (active) setState(readWebsiteInfo(data));
      })
      .catch(() => {
        if (active) setState({ kind: "unavailable" });
      });
    return () => {
      active = false;
      controller.abort();
    };
  }, [pathname, revision]);
  useEffect(() => {
    const refresh = () => setRevision((value) => value + 1);
    window.addEventListener("focus", refresh);
    return () => window.removeEventListener("focus", refresh);
  }, []);
  return (
    <websiteInfoContext.Provider
      value={{ state, reload: () => setRevision((value) => value + 1) }}
    >
      {children}
    </websiteInfoContext.Provider>
  );
}
