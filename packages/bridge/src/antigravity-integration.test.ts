import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { BridgeWebSocketServer } from "./websocket.js";
import { createServer, type Server } from "node:http";
import WebSocket from "ws";

describe("Bridge Antigravity Real Integration Probe", () => {
  let server: Server;
  let bridgeWs: BridgeWebSocketServer;
  let port: number;

  beforeAll(async () => {
    server = createServer();
    bridgeWs = new BridgeWebSocketServer({
      server,
      allowedDirs: [
        "/Users/lw/Windows_Projects/Macremote_spike/fixtures/project-a",
        "/Users/lw/Windows_Projects/Macremote_spike/fixtures/project-b",
      ],
    });
    await new Promise<void>((resolve) => {
      server.listen(0, "127.0.0.1", () => {
        const addr = server.address();
        port = typeof addr === "object" && addr ? addr.port : 8767;
        resolve();
      });
    });
  });

  afterAll(async () => {
    bridgeWs.close();
    server.close();
  });

  it("completes start turn with real agy CLI", async () => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    await new Promise((res) => ws.on("open", res));

    const received: any[] = [];
    ws.on("message", (data) => {
      try {
        received.push(JSON.parse(data.toString()));
      } catch (_) {}
    });

    // 1. Send start
    ws.send(
      JSON.stringify({
        type: "start",
        projectPath: "/Users/lw/Windows_Projects/Macremote_spike/fixtures/project-a",
        provider: "antigravity",
        planMode: true,
      })
    );

    // Wait for session_created
    let sessionId = "";
    const startWait = Date.now();
    while (Date.now() - startWait < 5000) {
      const cr = received.find(
        (m) => m.type === "system" && m.subtype === "session_created"
      );
      if (cr) {
        sessionId = cr.sessionId;
        break;
      }
      await new Promise((r) => setTimeout(r, 100));
    }

    expect(sessionId).toBeTruthy();

    // 2. Send input
    ws.send(
      JSON.stringify({
        type: "input",
        sessionId,
        text: "Read package.json and print its name",
      })
    );

    // Wait for result
    let resultMsg: any = null;
    const inputWait = Date.now();
    while (Date.now() - inputWait < 45000) {
      resultMsg = received.find((m) => m.type === "result");
      if (resultMsg) break;
      await new Promise((r) => setTimeout(r, 500));
    }

    expect(resultMsg).toBeTruthy();
    expect(resultMsg.subtype).toBe("success");
    expect(resultMsg.result).toContain("fixture-project-a");

    ws.close();
  }, 60000);
});
