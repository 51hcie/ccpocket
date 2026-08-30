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

  it("collects antigravity account quotas from TokenBar and masks identities", async () => {
    const monitoringService = new MonitoringService(Date.now(), 8766, () => null, {
      fetcher: async () => new Response(JSON.stringify({
        refreshed_at: "2026-08-30T01:00:00Z",
        agy_today: { totalInput: 1000, totalOutput: 200, totalMessages: 3, totalCost: 0.25 },
        agy_all: {
          totalInput: 40000,
          totalOutput: 2000,
          totalCacheRead: 90000,
          totalMessages: 91,
          totalCost: 8.5,
          entries: [
            {
              model: "gemini-3.7-flash",
              provider: "google",
              input: 30000,
              output: 1500,
              cacheRead: 80000,
              reasoning: 500,
              messageCount: 70,
            },
            {
              model: "claude-sonnet-4.6",
              provider: "anthropic",
              input: 10000,
              output: 500,
              cacheRead: 10000,
              reasoning: 0,
              messageCount: 21,
            },
          ],
        },
        cockpit_quota: [{
          email: "person@example.com",
          updatedAt: 1788051600000,
          groups: [{
            displayName: "Gemini Models",
            description: "Gemini model pool",
            buckets: [{
              bucketId: "gemini-weekly",
              displayName: "Weekly Limit Remaining",
              remainingFraction: 0.8797,
              resetTime: "2026-09-01T00:00:00Z",
              window: "weekly",
            }],
          }],
        }],
      }), { status: 200 }),
    });

    const agy = await monitoringService.collectAntigravityMetrics();
    expect(agy.model).toBe("gemini-3.7-flash-medium");
    expect(agy.quota).toBe("1 个账号额度已同步");
    expect(agy.accounts[0].account).toBe("per***n@example.com");
    expect(agy.accounts[0].account).not.toContain("person@");
    expect(agy.accounts[0].groups[0].buckets[0].remainingPercent).toBe(88);
    expect(agy.usage?.todayTokens).toBe(1200);
    expect(agy.usage?.allInputTokens).toBe(40000);
    expect(agy.usage?.allOutputTokens).toBe(2000);
    expect(agy.usage?.allCacheReadTokens).toBe(90000);
    expect(agy.usage?.allReasoningTokens).toBe(500);
    expect(agy.usage?.models).toHaveLength(2);
    expect(agy.usage?.models[0]).toMatchObject({
      model: "gemini-3.7-flash",
      totalTokens: 31500,
      messages: 70,
    });
    expect(agy.source).toBe("TokenBar Local API");
  });

  it("degrades truthfully when TokenBar is unavailable", async () => {
    const monitoringService = new MonitoringService(Date.now(), 8766, () => null, {
      fetcher: async () => { throw new Error("offline"); },
    });

    const agy = await monitoringService.collectAntigravityMetrics();
    expect(agy.quota).toBe("额度数据暂不可用");
    expect(agy.accounts).toEqual([]);
    expect(agy.error).toContain("offline");
    expect(agy.source).toBe("TokenBar Local API");
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
    expect(typeof response.body.antigravity.quota).toBe("string");
  }, 15000);
});
