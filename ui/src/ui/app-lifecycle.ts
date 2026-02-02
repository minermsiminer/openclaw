import type { Tab } from "./navigation";
import { connectGateway } from "./app-gateway";
import {
  startLogsPolling,
  startNodesPolling,
  stopLogsPolling,
  stopNodesPolling,
  startDebugPolling,
  stopDebugPolling,
} from "./app-polling";
import { observeTopbar, scheduleChatScroll, scheduleLogsScroll } from "./app-scroll";
import {
  applySettingsFromUrl,
  attachThemeListener,
  detachThemeListener,
  inferBasePath,
  syncTabWithLocation,
  syncThemeWithSettings,
} from "./app-settings";

type LifecycleHost = {
  basePath: string;
  tab: Tab;
  chatHasAutoScrolled: boolean;
  chatLoading: boolean;
  chatMessages: unknown[];
  chatToolMessages: unknown[];
  chatStream: string;
  logsAutoFollow: boolean;
  logsAtBottom: boolean;
  logsEntries: unknown[];
  popStateHandler: () => void;
  topbarObserver: ResizeObserver | null;
};

export function handleConnected(host: LifecycleHost) {
  host.basePath = inferBasePath();
  applySettingsFromUrl(host as unknown as Parameters<typeof applySettingsFromUrl>[0]);
  syncTabWithLocation(host as unknown as Parameters<typeof syncTabWithLocation>[0], true);
  syncThemeWithSettings(host as unknown as Parameters<typeof syncThemeWithSettings>[0]);
  attachThemeListener(host as unknown as Parameters<typeof attachThemeListener>[0]);
  window.addEventListener("popstate", host.popStateHandler);
  connectGateway(host as unknown as Parameters<typeof connectGateway>[0]);
  startNodesPolling(host as unknown as Parameters<typeof startNodesPolling>[0]);
  if (host.tab === "logs") {
    startLogsPolling(host as unknown as Parameters<typeof startLogsPolling>[0]);
  }
  if (host.tab === "debug") {
    startDebugPolling(host as unknown as Parameters<typeof startDebugPolling>[0]);
  }
}

export async function handleFirstUpdated(host: LifecycleHost) {
  observeTopbar(host as unknown as Parameters<typeof observeTopbar>[0]);

  // Dev-only: attempt to fetch a local UI dev config (written by .devcontainer/start-codespace.sh)
  try {
    const res = await fetch("/dev-config.json", { cache: "no-store" });
    if (res.ok) {
      const cfg = await res.json();
      const port = Number(cfg?.gatewayPort) || 19001;
      const token = typeof cfg?.token === "string" ? cfg.token : "";
      const preview = typeof cfg?.gatewayPreviewUrl === "string" && cfg.gatewayPreviewUrl.trim() ? cfg.gatewayPreviewUrl.trim() : null;
      if (preview || port || token) {
        // Prefer explicit preview URL (provided by Codespaces start script) because
        // Codespaces exposes ports with preview hostnames (e.g. <codespace>-19001.app.github.dev).
        const gatewayUrl = preview ?? (() => {
          const proto = window.location.protocol === "https:" ? "wss" : "ws";
          return `${proto}://${window.location.hostname}:${port}`;
        })();
        // Apply settings (gatewayUrl + token) so the UI connects automatically in Codespaces
        try {
          // applySettings is safe here; import at top to avoid circulars
          // eslint-disable-next-line @typescript-eslint/no-var-requires
          const { applySettings } = await import("./app-settings");
          applySettings(host as unknown as Parameters<typeof applySettings>[0], {
            ...host.settings,
            gatewayUrl,
            token,
          });
          console.log("[dev-config] applied gatewayUrl", gatewayUrl, "and token from /dev-config.json");
        } catch (e) {
          console.warn("[dev-config] failed to apply settings:", e);
        }
      }
    }
  } catch (e) {
    // Not an error in production; keep quiet
  }
}

export function handleDisconnected(host: LifecycleHost) {
  window.removeEventListener("popstate", host.popStateHandler);
  stopNodesPolling(host as unknown as Parameters<typeof stopNodesPolling>[0]);
  stopLogsPolling(host as unknown as Parameters<typeof stopLogsPolling>[0]);
  stopDebugPolling(host as unknown as Parameters<typeof stopDebugPolling>[0]);
  detachThemeListener(host as unknown as Parameters<typeof detachThemeListener>[0]);
  host.topbarObserver?.disconnect();
  host.topbarObserver = null;
}

export function handleUpdated(host: LifecycleHost, changed: Map<PropertyKey, unknown>) {
  if (
    host.tab === "chat" &&
    (changed.has("chatMessages") ||
      changed.has("chatToolMessages") ||
      changed.has("chatStream") ||
      changed.has("chatLoading") ||
      changed.has("tab"))
  ) {
    const forcedByTab = changed.has("tab");
    const forcedByLoad =
      changed.has("chatLoading") &&
      changed.get("chatLoading") === true &&
      host.chatLoading === false;
    scheduleChatScroll(
      host as unknown as Parameters<typeof scheduleChatScroll>[0],
      forcedByTab || forcedByLoad || !host.chatHasAutoScrolled,
    );
  }
  if (
    host.tab === "logs" &&
    (changed.has("logsEntries") || changed.has("logsAutoFollow") || changed.has("tab"))
  ) {
    if (host.logsAutoFollow && host.logsAtBottom) {
      scheduleLogsScroll(
        host as unknown as Parameters<typeof scheduleLogsScroll>[0],
        changed.has("tab") || changed.has("logsAutoFollow"),
      );
    }
  }
}
