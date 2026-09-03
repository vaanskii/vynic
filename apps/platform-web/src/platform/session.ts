interface StoredSession {
  token: string;
  expiresAt: number;
}

const SESSION_KEY = "vynic.platform.session.v1";

export const platformSession = {
  read(): StoredSession | null {
    try {
      const raw = sessionStorage.getItem(SESSION_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw) as Partial<StoredSession>;
      if (
        typeof parsed.token !== "string" ||
        typeof parsed.expiresAt !== "number" ||
        parsed.expiresAt <= Date.now()
      ) {
        this.clear();
        return null;
      }
      return { token: parsed.token, expiresAt: parsed.expiresAt };
    } catch {
      this.clear();
      return null;
    }
  },
  save(token: string, expiresInSeconds: number) {
    const value: StoredSession = {
      token,
      expiresAt: Date.now() + expiresInSeconds * 1000,
    };
    sessionStorage.setItem(SESSION_KEY, JSON.stringify(value));
  },
  clear() {
    sessionStorage.removeItem(SESSION_KEY);
  },
};
