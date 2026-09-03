import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { authApi, configurePlatformApi } from "./api";
import { platformSession } from "./session";
import type { PlatformActor } from "./types";

type AuthStatus = "checking" | "authenticated" | "anonymous";

interface AuthContextValue {
  actor: PlatformActor | null;
  status: AuthStatus;
  login(email: string, password: string): Promise<void>;
  logout(): void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const [actor, setActor] = useState<PlatformActor | null>(null);
  const [status, setStatus] = useState<AuthStatus>(() =>
    platformSession.read() ? "checking" : "anonymous",
  );

  const logout = useCallback(() => {
    platformSession.clear();
    setActor(null);
    setStatus("anonymous");
    queryClient.clear();
  }, [queryClient]);

  configurePlatformApi({
    token: () => platformSession.read()?.token ?? null,
    onUnauthorized: logout,
  });

  useEffect(() => {
    let active = true;
    const stored = platformSession.read();
    if (!stored) {
      return () => {
        active = false;
      };
    }

    authApi
      .me()
      .then((principal) => {
        if (!active) return;
        setActor(principal);
        setStatus("authenticated");
      })
      .catch(() => {
        if (!active) return;
        logout();
      });
    return () => {
      active = false;
    };
  }, [logout]);

  const value = useMemo<AuthContextValue>(
    () => ({
      actor,
      status,
      async login(email, password) {
        const result = await authApi.login(email, password);
        platformSession.save(result.access_token, result.expiresIn);
        setActor(result.actor);
        setStatus("authenticated");
      },
      logout,
    }),
    [actor, logout, status],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth must be used inside AuthProvider");
  return value;
}
