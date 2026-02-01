import { beforeEach, afterEach, describe, it, expect, vi } from "vitest";
import { handleFirstUpdated } from "./app-lifecycle";
import { loadSettings } from "./storage";

describe("dev-config integration", () => {
  let originalFetch: typeof fetch | undefined;

  beforeEach(() => {
    originalFetch = (global as any).fetch;
  });

  afterEach(() => {
    (global as any).fetch = originalFetch;
    localStorage.clear();
  });

  it("applies gatewayUrl and token from /dev-config.json", async () => {
    const fake = {
      ok: true,
      json: async () => ({ gatewayPort: 19001, token: "dev-token-abc" }),
    } as unknown as Response;
    (global as any).fetch = vi.fn(async (url: string) => {
      if (url === "/dev-config.json") return fake;
      return { ok: false } as unknown as Response;
    });

    const host: any = {
      settings: loadSettings(),
      theme: "system",
      themeResolved: {} as any,
      applySessionKey: "main",
      sessionKey: "main",
      tab: "overview",
      connected: false,
      chatHasAutoScrolled: false,
      logsAtBottom: false,
      eventLog: [],
      eventLogBuffer: [],
      basePath: "",
      themeMedia: null,
      themeMediaHandler: null,
      pendingGatewayUrl: null,
    };

    await handleFirstUpdated(host);

    const proto = window.location.protocol === "https:" ? "wss" : "ws";
    const expected = `${proto}://${window.location.hostname}:19001`;
    expect(host.settings.gatewayUrl).toBe(expected);
    expect(host.settings.token).toBe("dev-token-abc");
  });
});
