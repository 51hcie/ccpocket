import os from "node:os";
import { execSync } from "node:child_process";
import { existsSync, readFileSync, statfsSync } from "node:fs";
import { join } from "node:path";
import type { IncomingMessage, ServerResponse } from "node:http";
import type { BridgeWebSocketServer } from "./websocket.js";
import { fetchCodexUsage } from "./usage.js";

export interface SystemMetrics {
  available: boolean;
  hostname: string;
  os: string;
  systemUptime: number; // seconds
  cpu: {
    model: string;
    cores: number;
    speedMHz: number;
    loadPercent: number;
  };
  memory: {
    totalBytes: number;
    freeBytes: number;
    usedBytes: number;
    usedPercent: number;
  };
  disk: {
    available: boolean;
    totalBytes: number;
    freeBytes: number;
    usedBytes: number;
    usedPercent: number;
    mountPoint: string;
    error?: string;
  };
  loadAverage: [number, number, number];
  source: string;
  error?: string;
}

export interface BridgeMetrics {
  available: boolean;
  uptime: number; // seconds
  port: number;
  connectedClients: number;
  taskCounts: {
    running: number;
    queued: number;
    completed: number;
    failed: number;
  };
  source: string;
}

export interface CodexProviderMetrics {
  available: boolean;
  account: string; // Masked identifier
  plan: string;
  fiveHourWindow: {
    usedPercent: number;
    resetsAt: string;
  } | null;
  sevenDayWindow: {
    usedPercent: number;
    resetsAt: string;
  } | null;
  tokenUsage?: {
    inputTokens: number;
    outputTokens: number;
    totalTokens: number;
  } | null;
  source: string;
  error?: string;
}

export interface AntigravityProviderMetrics {
  available: boolean;
  model: string;
  status: "Ready" | "Supported" | "Unavailable";
  quota: string;
  note: string;
  source: string;
}

export interface MonitoringPayload {
  timestamp: string;
  system: SystemMetrics;
  bridge: BridgeMetrics;
  codex: CodexProviderMetrics;
  antigravity: AntigravityProviderMetrics;
}

export class MonitoringService {
  private startedAt: number;
  private port: number;
  private wsServerGetter: () => BridgeWebSocketServer | null;

  constructor(
    startedAt: number,
    port: number,
    wsServerGetter: () => BridgeWebSocketServer | null,
  ) {
    this.startedAt = startedAt;
    this.port = port;
    this.wsServerGetter = wsServerGetter;
  }

  private getOsDescription(): string {
    if (process.platform === "darwin") {
      try {
        const out = execSync("sw_vers -productVersion", {
          encoding: "utf-8",
          timeout: 1000,
          stdio: ["pipe", "pipe", "pipe"],
        }).trim();
        return `macOS ${out} (${os.arch()})`;
      } catch {
        return `macOS ${os.release()} (${os.arch()})`;
      }
    }
    return `${os.type()} ${os.release()} (${os.arch()})`;
  }

  private getDiskMetrics(): SystemMetrics["disk"] {
    try {
      if (typeof statfsSync === "function") {
        const stats = statfsSync("/");
        const totalBytes = Number(stats.blocks) * Number(stats.bsize);
        const freeBytes = Number(stats.bavail) * Number(stats.bsize);
        const usedBytes = Math.max(0, totalBytes - freeBytes);
        const usedPercent = totalBytes > 0 ? Math.round((usedBytes / totalBytes) * 1000) / 10 : 0;
        return {
          available: true,
          totalBytes,
          freeBytes,
          usedBytes,
          usedPercent,
          mountPoint: "/",
        };
      }
    } catch {
      // Fall through to df -k /
    }

    try {
      const out = execSync("df -k /", {
        encoding: "utf-8",
        timeout: 1500,
        stdio: ["pipe", "pipe", "pipe"],
      }).trim();
      const lines = out.split("\n");
      if (lines.length >= 2) {
        const parts = lines[1].trim().split(/\s+/);
        if (parts.length >= 4) {
          const totalKb = parseInt(parts[1], 10);
          const availKb = parseInt(parts[3], 10);
          if (!isNaN(totalKb) && !isNaN(availKb) && totalKb > 0) {
            const totalBytes = totalKb * 1024;
            const freeBytes = availKb * 1024;
            const usedBytes = Math.max(0, totalBytes - freeBytes);
            const usedPercent = Math.round((usedBytes / totalBytes) * 1000) / 10;
            return {
              available: true,
              totalBytes,
              freeBytes,
              usedBytes,
              usedPercent,
              mountPoint: "/",
            };
          }
        }
      }
      return {
        available: false,
        totalBytes: 0,
        freeBytes: 0,
        usedBytes: 0,
        usedPercent: 0,
        mountPoint: "/",
        error: "Unrecognized df output format",
      };
    } catch (err) {
      return {
        available: false,
        totalBytes: 0,
        freeBytes: 0,
        usedBytes: 0,
        usedPercent: 0,
        mountPoint: "/",
        error: err instanceof Error ? err.message : String(err),
      };
    }
  }

  async collectSystemMetrics(): Promise<SystemMetrics> {
    try {
      const cpus = os.cpus();
      const loadAvg = os.loadavg() as [number, number, number];
      const cpuCount = cpus.length || 1;
      const loadPercent = Math.min(100, Math.round((loadAvg[0] / cpuCount) * 1000) / 10);

      const totalMem = os.totalmem();
      const freeMem = os.freemem();
      const usedMem = totalMem - freeMem;
      const memPercent = Math.round((usedMem / totalMem) * 1000) / 10;

      const disk = this.getDiskMetrics();

      return {
        available: true,
        hostname: os.hostname(),
        os: this.getOsDescription(),
        systemUptime: Math.floor(os.uptime()),
        cpu: {
          model: cpus[0]?.model || "Apple Silicon / Generic CPU",
          cores: cpuCount,
          speedMHz: cpus[0]?.speed || 0,
          loadPercent,
        },
        memory: {
          totalBytes: totalMem,
          freeBytes: freeMem,
          usedBytes: usedMem,
          usedPercent: memPercent,
        },
        disk,
        loadAverage: [
          Math.round(loadAvg[0] * 100) / 100,
          Math.round(loadAvg[1] * 100) / 100,
          Math.round(loadAvg[2] * 100) / 100,
        ],
        source: "macOS Kernel / OS Runtime",
      };
    } catch (err) {
      return {
        available: false,
        hostname: os.hostname(),
        os: `${os.type()} ${os.arch()}`,
        systemUptime: 0,
        cpu: { model: "Unknown", cores: 1, speedMHz: 0, loadPercent: 0 },
        memory: { totalBytes: 0, freeBytes: 0, usedBytes: 0, usedPercent: 0 },
        disk: { available: false, totalBytes: 0, freeBytes: 0, usedBytes: 0, usedPercent: 0, mountPoint: "/" },
        loadAverage: [0, 0, 0],
        source: "macOS Kernel / OS Runtime",
        error: err instanceof Error ? err.message : String(err),
      };
    }
  }

  collectBridgeMetrics(): BridgeMetrics {
    const wsServer = this.wsServerGetter();
    const uptime = Math.floor((Date.now() - this.startedAt) / 1000);
    const connectedClients = wsServer?.clientCount ?? 0;

    let taskCounts = { running: 0, queued: 0, completed: 0, failed: 0 };
    try {
      if (wsServer && typeof (wsServer as any).getTaskCounts === "function") {
        taskCounts = (wsServer as any).getTaskCounts();
      }
    } catch {
      // Degrade gracefully
    }

    return {
      available: true,
      uptime,
      port: this.port,
      connectedClients,
      taskCounts,
      source: "AnyCoding Bridge Runtime",
    };
  }

  private getAuthoritativeCodexPlan(): string {
    try {
      const authFile = join(os.homedir(), ".codex", "auth.json");
      if (existsSync(authFile)) {
        const raw = readFileSync(authFile, "utf-8");
        const data = JSON.parse(raw);
        if (data.tokens?.id_token) {
          const parts = data.tokens.id_token.split(".");
          if (parts.length === 3) {
            const payload = JSON.parse(Buffer.from(parts[1], "base64").toString("utf-8"));
            const authClaim = payload["https://api.openai.com/auth"];
            if (
              authClaim &&
              typeof authClaim.chatgpt_plan_type === "string" &&
              authClaim.chatgpt_plan_type.trim().length > 0
            ) {
              return authClaim.chatgpt_plan_type.trim();
            }
          }
        }
      }
    } catch {}
    return "unknown";
  }

  async collectCodexMetrics(): Promise<CodexProviderMetrics> {
    try {
      const usage = await fetchCodexUsage();
      const hasFiveHour = usage.fiveHour !== null;
      const hasSevenDay = usage.sevenDay !== null;

      // Mask account identifier
      const authFile = join(os.homedir(), ".codex", "auth.json");
      let maskedAccount = "codex_local_user";
      if (existsSync(authFile)) {
        maskedAccount = "user_***";
      }

      const plan = this.getAuthoritativeCodexPlan();

      return {
        available: !usage.error || hasFiveHour || hasSevenDay,
        account: maskedAccount,
        plan,
        fiveHourWindow: usage.fiveHour
          ? {
              usedPercent: usage.fiveHour.utilization,
              resetsAt: usage.fiveHour.resetsAt,
            }
          : null,
        sevenDayWindow: usage.sevenDay
          ? {
              usedPercent: usage.sevenDay.utilization,
              resetsAt: usage.sevenDay.resetsAt,
            }
          : null,
        tokenUsage: null,
        source: "Codex App Server / Local Sessions",
        error: usage.error,
      };
    } catch (err) {
      return {
        available: false,
        account: "user_***",
        plan: "unknown",
        fiveHourWindow: null,
        sevenDayWindow: null,
        tokenUsage: null,
        source: "Codex App Server / Local Sessions",
        error: err instanceof Error ? err.message : String(err),
      };
    }
  }

  collectAntigravityMetrics(): AntigravityProviderMetrics {
    const candidates = [
      process.env.AGY_BIN_PATH,
      "/Users/lw/Windows_Projects/Macremote/tools/bin/agy",
      "/Users/lw/Windows_Projects/Macremote_spike/tools/bin/agy",
    ].filter(Boolean) as string[];

    let status: AntigravityProviderMetrics["status"] = "Supported";
    for (const c of candidates) {
      if (existsSync(c)) {
        status = "Ready";
        break;
      }
    }

    return {
      available: true,
      model: "gemini-3.7-flash-high",
      status,
      quota: "当前版本暂不可获取",
      note: "Antigravity CLI 本地接口当前不提供实时配额查询，按实际执行计费",
      source: "Antigravity CLI (Local)",
    };
  }

  async getMonitoringPayload(): Promise<MonitoringPayload> {
    const [system, codex] = await Promise.all([
      this.collectSystemMetrics(),
      this.collectCodexMetrics(),
    ]);
    const bridge = this.collectBridgeMetrics();
    const antigravity = this.collectAntigravityMetrics();

    return {
      timestamp: new Date().toISOString(),
      system,
      bridge,
      codex,
      antigravity,
    };
  }

  async handleRequest(
    req: IncomingMessage,
    res: ServerResponse,
  ): Promise<boolean> {
    const url = req.url?.split("?")[0];
    if (
      (url === "/api/monitor" ||
        url === "/monitor" ||
        url === "/api/monitoring") &&
      req.method === "GET"
    ) {
      try {
        const payload = await this.getMonitoringPayload();
        res.writeHead(200, {
          "Content-Type": "application/json",
          "Cache-Control": "no-cache",
        });
        res.end(JSON.stringify(payload));
      } catch (err) {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(
          JSON.stringify({
            error: err instanceof Error ? err.message : String(err),
          }),
        );
      }
      return true;
    }
    return false;
  }
}
