import { describe, it, expect } from "vitest";
import { createServer, request, type Server } from "node:http";
import { MonitoringService } from "./monitoring.js";

describe("MonitoringService", () => {
  it("collects truthful system metrics with provenance labels", async () => {
    const monitoringService = new MonitoringService(
      Date.now() - 60000,
      8766,
      () => null,
    );

    const system = await monitoringService.collectSystemMetrics();
    expect(system.available).toBe(true);
    expect(system.hostname).toBeTruthy();
    expect(system.os).toBeTruthy();
    expect(system.systemUptime).toBeGreaterThan(0);
    expect(system.cpu.cores).toBeGreaterThan(0);
    expect(system.memory.totalBytes).toBeGreaterThan(0);
    expect(system.memory.usedPercent).toBeGreaterThanOrEqual(0);
    expect(system.source).toBe("macOS Kernel / OS Runtime");
    expect(system.loadAverage).toHaveLength(3);
  });

  it("calculates disk metrics with mathematical consistency", async () => {
    const monitoringService = new MonitoringService(Date.now(), 8766, () => null);
    const system = await monitoringService.collectSystemMetrics();
    if (system.disk.available) {
      expect(system.disk.totalBytes).toBeGreaterThan(0);
      expect(system.disk.freeBytes).toBeGreaterThanOrEqual(0);
      expect(system.disk.usedBytes).toBeGreaterThanOrEqual(0);
      // Assert usedBytes + freeBytes == totalBytes
      expect(system.disk.freeBytes + system.disk.usedBytes).toBe(system.disk.totalBytes);
      // Assert usedPercent agrees with usedBytes / totalBytes
      const expectedPercent = Math.round((system.disk.usedBytes / system.disk.totalBytes) * 1000) / 10;
      expect(system.disk.usedPercent).toBeCloseTo(expectedPercent, 1);
    }
  });

  it("collects bridge metrics with task counts", () => {
    const startedAt = Date.now() - 120000;
    const monitoringService = new MonitoringService(startedAt, 8766, () => null);

    const bridge = monitoringService.collectBridgeMetrics();
    expect(bridge.available).toBe(true);
    expect(bridge.port).toBe(8766);
    expect(bridge.uptime).toBeGreaterThanOrEqual(120);
    expect(bridge.connectedClients).toBe(0);
    expect(bridge.taskCounts).toBeDefined();
    expect(bridge.taskCounts.running).toBe(0);
    expect(bridge.source).toBe("AnyCoding Bridge Runtime");
  });

  it("collects codex metrics with masked account identifiers", async () => {
    const monitoringService = new MonitoringService(Date.now(), 8766, () => null);

    const codex = await monitoringService.collectCodexMetrics();
    expect(codex.account).toMatch(/(\*\*\*|codex_local_user)/);
    expect(codex.account).not.toContain("sk-");
    expect(codex.account).not.toContain("sess-");
    expect(codex.source).toBe("Codex App Server / Local Sessions");
  });

  it("collects antigravity metrics with truthful fallback and no fabricated quota", () => {
    const monitoringService = new MonitoringService(Date.now(), 8766, () => null);

    const agy = monitoringService.collectAntigravityMetrics();
    expect(agy.available).toBe(true);
    expect(agy.model).toBe("gemini-3.7-flash-high");
    expect(agy.quota).toBe("当前版本暂不可获取");
    expect(agy.note).toContain("不提供实时配额查询");
    expect(agy.source).toBe("Antigravity CLI (Local)");
  });

  it("serves GET /api/monitor over HTTP with complete structure", async () => {
    const monitoringService = new MonitoringService(Date.now(), 8766, () => null);

    const server: Server = createServer(async (req, res) => {
      if (await monitoringService.handleRequest(req, res)) return;
      res.writeHead(404);
      res.end();
    });

    const testPort = await new Promise<number>((resolve) => {
      server.listen(0, "127.0.0.1", () => {
        const addr = server.address();
        if (addr && typeof addr === "object") resolve(addr.port);
      });
    });

    const response = await new Promise<{ status: number; body: any }>(
      (resolve) => {
        request(`http://127.0.0.1:${testPort}/api/monitor`, (res) => {
          let data = "";
          res.on("data", (chunk) => (data += chunk));
          res.on("end", () => {
            resolve({
              status: res.statusCode || 0,
              body: JSON.parse(data),
            });
          });
        }).end();
      },
    );

    server.close();

    expect(response.status).toBe(200);
    expect(response.body.timestamp).toBeDefined();
    expect(response.body.system.hostname).toBeDefined();
    expect(response.body.bridge.port).toBe(8766);
    expect(response.body.codex.source).toBeDefined();
    expect(response.body.antigravity.quota).toBe("当前版本暂不可获取");
  });
});
