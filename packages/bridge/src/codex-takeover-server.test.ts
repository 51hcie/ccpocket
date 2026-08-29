import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { createServer, type Server } from "node:http";
import WebSocket from "ws";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { rm, mkdir } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { BridgeWebSocketServer } from "./websocket.js";
import { CodexTakeoverQueueStore } from "./codex-takeover-queue.js";
import { CodexProcess, CodexRpcError } from "./codex-process.js";
import type { SessionInfo } from "./session.js";

describe("BridgeWebSocketServer Codex Takeover Queue Integration", () => {
  let testDir: string;
  let queueFilePath: string;
  let server: Server;
  let bridge: BridgeWebSocketServer;
  let port: number;
  let queueStore: CodexTakeoverQueueStore;

  beforeEach(async () => {
    testDir = join(tmpdir(), `ccpocket-takeover-bridge-${randomUUID()}`);
    await mkdir(testDir, { recursive: true });
    queueFilePath = join(testDir, "queue.json");
    queueStore = new CodexTakeoverQueueStore(queueFilePath);
    await queueStore.init();

    server = createServer();
    bridge = new BridgeWebSocketServer({
      server,
      allowedDirs: ["/repo"],
      codexTakeoverQueueStore: queueStore,
    });

    vi.spyOn(CodexProcess.prototype, "start").mockImplementation(function (
      this: CodexProcess,
      projectPath: string,
      options?: any,
    ) {
      (this as any).prepareLaunch(projectPath, options);
    });

    await new Promise<void>((resolve) => {
      server.listen(0, "127.0.0.1", () => {
        const addr = server.address();
        port = typeof addr === "object" && addr ? addr.port : 8768;
        resolve();
      });
    });
  });

  afterEach(async () => {
    vi.restoreAllMocks();
    bridge.close();
    server.close();
    try {
      await rm(testDir, { recursive: true, force: true });
    } catch {
      // cleanup best effort
    }
  });

  async function connectClient(): Promise<{
    ws: WebSocket;
    received: any[];
    waitForMessage: (
      predicate: (msg: any) => boolean,
      timeoutMs?: number,
    ) => Promise<any>;
  }> {
    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    const received: any[] = [];
    ws.on("message", (data) => {
      try {
        received.push(JSON.parse(data.toString()));
      } catch (_) {}
    });
    await new Promise((res) => ws.on("open", res));

    const waitForMessage = (
      predicate: (msg: any) => boolean,
      timeoutMs = 3000,
    ) =>
      new Promise<any>((resolve, reject) => {
        const existing = received.find(predicate);
        if (existing) return resolve(existing);
        const timer = setTimeout(() => {
          reject(
            new Error(
              `Timed out waiting for message matching predicate. Received: ${JSON.stringify(received)}`,
            ),
          );
        }, timeoutMs);
        const handler = (data: any) => {
          try {
            const parsed = JSON.parse(data.toString());
            if (predicate(parsed)) {
              clearTimeout(timer);
              ws.off("message", handler);
              resolve(parsed);
            }
          } catch (_) {}
        };
        ws.on("message", handler);
      });

    return { ws, received, waitForMessage };
  }

  it("enqueues takeover via WebSocket and invokes runtime resume with real ready verification", async () => {
    const { ws, waitForMessage } = await connectClient();
    const threadId = "thread-runtime-1";

    // Mock getCodexThreadHistory (readThread) to always succeed
    const getHistorySpy = vi
      .spyOn(bridge as any, "getCodexThreadHistory")
      .mockResolvedValue([{ type: "user", text: "hello history" }]);

    // Mock CodexProcess.prototype.waitForReady to simulate real successful resume RPC + input ready
    const readySpy = vi
      .spyOn(CodexProcess.prototype, "waitForReady")
      .mockImplementation(async function (this: CodexProcess) {
        // Mark inputResolve available so input can be drained
        (this as any).inputResolve = vi.fn();
        this.emit("input_ready");
      });

    ws.send(
      JSON.stringify({
        type: "enqueue_codex_takeover",
        threadId,
        projectPath: "/repo",
        clientId: "client-1",
        queuedCommand: "execute first task",
      }),
    );

    // Should receive initial queued status
    const queuedMsg = await waitForMessage(
      (m) => m.type === "codex_takeover_queue_status" && m.status === "queued",
    );
    expect(queuedMsg.threadId).toBe(threadId);
    expect(queuedMsg.position).toBe(1);
    expect(queuedMsg.total).toBe(1);
    expect(queuedMsg.queueId).toBeDefined();

    // Should process queue and broadcast resumed
    const resumedMsg = await waitForMessage(
      (m) => m.type === "codex_takeover_queue_status" && m.status === "resumed",
    );
    expect(resumedMsg.threadId).toBe(threadId);
    expect(resumedMsg.queueId).toBe(queuedMsg.queueId);
    expect(resumedMsg.sessionId).toBeDefined();

    expect(readySpy).toHaveBeenCalled();

    // Verify pending queue is now empty in store
    const pending = queueStore.getPendingForThread(threadId);
    expect(pending.length).toBe(0);

    ws.close();
  });

  it("simulates readThread always succeeding but thread/resume failing twice with active-writer conflict and succeeding on third attempt", async () => {
    const { ws, waitForMessage, received } = await connectClient();
    const threadId = "thread-writer-conflict-3x";

    // 1. readThread / getCodexThreadHistory ALWAYS succeeds (read does NOT acquire writer)
    const getHistorySpy = vi
      .spyOn(bridge as any, "getCodexThreadHistory")
      .mockResolvedValue([{ type: "user", text: "past turn" }]);

    let resumeAttempts = 0;
    const readySpy = vi
      .spyOn(CodexProcess.prototype, "waitForReady")
      .mockImplementation(async function (this: CodexProcess) {
        resumeAttempts++;
        if (resumeAttempts === 1) {
          throw new CodexRpcError("thread/resume", {
            code: -32600,
            message: "thread is running with an active writer in another client",
          });
        }
        if (resumeAttempts === 2) {
          throw new CodexRpcError("thread/resume", {
            code: -32600,
            message: "thread is running with a live local writer in another process",
          });
        }
        // 3rd attempt: writer released! Real ready!
        (this as any).inputResolve = vi.fn();
        this.emit("input_ready");
      });

    ws.send(
      JSON.stringify({
        type: "enqueue_codex_takeover",
        threadId,
        projectPath: "/repo",
        clientId: "client-conflict-3x",
        queuedCommand: "queued command after 2 conflicts",
      }),
    );

    // Initial queued status received
    await waitForMessage(
      (m) => m.type === "codex_takeover_queue_status" && m.status === "queued",
    );

    // Wait for the third attempt to succeed and broadcast resumed
    const resumedMsg = await waitForMessage(
      (m) => m.type === "codex_takeover_queue_status" && m.status === "resumed",
      6000,
    );

    expect(resumeAttempts).toBe(3);
    expect(resumedMsg.threadId).toBe(threadId);
    expect(resumedMsg.sessionId).toBeDefined();

    // Assert that before the 3rd attempt, NO "resumed" status was broadcasted
    const resumedBroadcasts = received.filter(
      (m) => m.type === "codex_takeover_queue_status" && m.status === "resumed",
    );
    expect(resumedBroadcasts.length).toBe(1);

    // Assert that temporary sessions from attempts 1 and 2 were cleaned up (no zombies)
    const activeSessions = Array.from(
      (bridge["sessionManager"] as any).sessions.values(),
    );
    expect(activeSessions.length).toBe(1);
    expect((activeSessions[0] as SessionInfo).id).toBe(resumedMsg.sessionId);

    // Assert that the command was sent exactly once
    const session = bridge["sessionManager"].get(resumedMsg.sessionId);
    expect(session).toBeDefined();
    const userInputs = session!.historyEntries.filter(
      (e: any) =>
        e.message.type === "user_input" &&
        e.message.text === "queued command after 2 conflicts",
    );
    expect(userInputs.length).toBe(1);

    // Assert store is dispatched exactly once
    const pending = queueStore.getPendingForThread(threadId);
    expect(pending.length).toBe(0);

    ws.close();
  });

  it("buffers command before input_ready and drains exactly once when ready", async () => {
    const threadId = "thread-queue-drain";
    await queueStore.enqueue({
      threadId,
      projectPath: "/repo",
      clientId: "client-drain",
      queuedCommand: "command before input ready",
    });

    let sendInputCalledWith: string | null = null;

    vi.spyOn(CodexProcess.prototype, "waitForReady").mockImplementation(
      async function (this: CodexProcess) {
        // waitForReady resolves, but input_ready is not emitted yet
      },
    );

    vi.spyOn(CodexProcess.prototype, "sendInputStructured").mockImplementation(
      function (this: CodexProcess, text: string) {
        sendInputCalledWith = text;
      },
    );

    // Process the takeover queue
    const result = await bridge.processTakeoverQueueForThread(threadId);
    expect(result).toBe(true);

    const pending = queueStore.getPendingForThread(threadId);
    expect(pending.length).toBe(0);

    // Find the created session
    const sessions = Array.from(
      (bridge["sessionManager"] as any).sessions.values(),
    ) as SessionInfo[];
    expect(sessions.length).toBe(1);
    const session = sessions[0];

    // Now emit input_ready on the process (with inputResolve ready)
    (session.process as any).inputResolve = vi.fn();
    (session.process as CodexProcess).emit("input_ready");

    // The queued input should now be drained and cleared
    expect(session.codexQueuedInput).toBeUndefined();
    expect(sendInputCalledWith).toBe("command before input ready");

    // User message is in session history exactly once
    const userInputs = session.historyEntries.filter(
      (e: any) =>
        e.message.type === "user_input" &&
        e.message.text === "command before input ready",
    );
    expect(userInputs.length).toBe(1);
  });

  it("bootstrap non-conflict failure does not mark dispatched and leaves no zombie", async () => {
    const threadId = "thread-non-conflict-err";
    await queueStore.enqueue({
      threadId,
      projectPath: "/repo",
      clientId: "client-err",
      queuedCommand: "retryable command",
    });

    vi.spyOn(CodexProcess.prototype, "waitForReady").mockRejectedValue(
      new CodexRpcError("thread/resume", {
        code: -32603,
        message: "Internal server error: database locked",
      }),
    );

    const result = await bridge.processTakeoverQueueForThread(threadId);
    expect(result).toBe(false);

    // Item must remain pending in store (NOT marked dispatched)
    const pending = queueStore.getPendingForThread(threadId);
    expect(pending.length).toBe(1);
    expect(pending[0].status).toBe("pending");

    // No zombie session left in sessionManager
    const activeSessions = Array.from(
      (bridge["sessionManager"] as any).sessions.values(),
    );
    expect(activeSessions.length).toBe(0);
  });

  it("queries real queue position and queueId accurately", async () => {
    const { ws, waitForMessage } = await connectClient();
    const threadId = "thread-pos-query";

    // Simulate busy writer so items stay queued
    vi.spyOn(CodexProcess.prototype, "waitForReady").mockRejectedValue(
      new CodexRpcError("thread/resume", {
        code: -32600,
        message: "active writer conflict",
      }),
    );

    ws.send(
      JSON.stringify({
        type: "enqueue_codex_takeover",
        threadId,
        projectPath: "/repo",
        clientId: "client-A",
        queuedCommand: "cmd 1",
      }),
    );
    const q1 = await waitForMessage(
      (m) => m.type === "codex_takeover_queue_status" && m.position === 1,
    );

    ws.send(
      JSON.stringify({
        type: "enqueue_codex_takeover",
        threadId,
        projectPath: "/repo",
        clientId: "client-B",
        queuedCommand: "cmd 2",
      }),
    );
    const q2 = await waitForMessage(
      (m) => m.type === "codex_takeover_queue_status" && m.position === 2,
    );

    expect(q1.position).toBe(1);
    expect(q2.position).toBe(2);
    expect(q2.total).toBe(2);

    // Query for client-B position
    ws.send(
      JSON.stringify({
        type: "get_codex_takeover_queue",
        threadId,
        clientId: "client-B",
      }),
    );
    const queryResB = await waitForMessage(
      (m) =>
        m.type === "codex_takeover_queue_status" &&
        m.queueId === q2.queueId &&
        m.position === 2,
    );
    expect(queryResB.position).toBe(2);
    expect(queryResB.total).toBe(2);
    expect(queryResB.status).toBe("queued");

    // Query for unknown client
    ws.send(
      JSON.stringify({
        type: "get_codex_takeover_queue",
        threadId,
        clientId: "client-unknown",
      }),
    );
    const queryResUnknown = await waitForMessage(
      (m) =>
        m.type === "codex_takeover_queue_status" &&
        m.status === "not_queued",
    );
    expect(queryResUnknown.position).toBe(0);
    expect(queryResUnknown.total).toBe(2);

    ws.close();
  });

  it("cancelling queue item stops further processing", async () => {
    const { ws, waitForMessage } = await connectClient();
    const threadId = "thread-cancel-test";

    vi.spyOn(CodexProcess.prototype, "waitForReady").mockRejectedValue(
      new CodexRpcError("thread/resume", {
        code: -32600,
        message: "active writer conflict",
      }),
    );

    ws.send(
      JSON.stringify({
        type: "enqueue_codex_takeover",
        threadId,
        projectPath: "/repo",
        clientId: "client-cancelling",
        queuedCommand: "never execute",
      }),
    );

    const queuedMsg = await waitForMessage(
      (m) => m.type === "codex_takeover_queue_status" && m.status === "queued",
    );

    ws.send(
      JSON.stringify({
        type: "cancel_codex_takeover",
        threadId,
        queueId: queuedMsg.queueId,
      }),
    );

    const cancelMsg = await waitForMessage(
      (m) =>
        m.type === "codex_takeover_queue_status" &&
        m.status === "cancelled",
    );
    expect(cancelMsg.status).toBe("cancelled");
    expect(cancelMsg.total).toBe(0);

    const pending = queueStore.getPendingForThread(threadId);
    expect(pending.length).toBe(0);

    ws.close();
  });

  it("recovers pending items across bridge restarts", async () => {
    const threadId = "thread-restart-recovery";
    // Pre-populate queue file with a pending item
    await queueStore.enqueue({
      threadId,
      projectPath: "/repo",
      clientId: "restarted-client",
      queuedCommand: "restart-cmd",
    });

    // Close first bridge
    bridge.close();
    server.close();

    // Create second bridge pointing to same store file
    const secondServer = createServer();
    const secondStore = new CodexTakeoverQueueStore(queueFilePath);

    const readySpy = vi
      .spyOn(CodexProcess.prototype, "waitForReady")
      .mockImplementation(async function (this: CodexProcess) {
        (this as any).inputResolve = vi.fn();
        this.emit("input_ready");
      });

    const secondBridge = new BridgeWebSocketServer({
      server: secondServer,
      allowedDirs: ["/repo"],
      codexTakeoverQueueStore: secondStore,
    });

    await new Promise<void>((resolve) => {
      secondServer.listen(0, "127.0.0.1", () => {
        const addr = secondServer.address();
        port = typeof addr === "object" && addr ? addr.port : 8769;
        resolve();
      });
    });

    // Wait for startup recovery processing to run
    await new Promise((r) => setTimeout(r, 400));

    expect(readySpy).toHaveBeenCalled();
    const pendingAfter = secondStore.getPendingForThread(threadId);
    expect(pendingAfter.length).toBe(0);

    secondBridge.close();
    secondServer.close();
  });

  it("broadcasts queued -> running -> completed status with the same queueId and exactly-once command dispatch", async () => {
    const { ws, waitForMessage } = await connectClient();
    const threadId = "thread-full-lifecycle";

    vi.spyOn(bridge as any, "getCodexThreadHistory").mockResolvedValue([
      { type: "user", text: "initial turn" },
    ]);

    let commandSentCount = 0;
    const readySpy = vi
      .spyOn(CodexProcess.prototype, "waitForReady")
      .mockImplementation(async function (this: CodexProcess) {
        (this as any).inputResolve = vi.fn();
        this.emit("input_ready");
      });

    vi.spyOn(CodexProcess.prototype, "sendInputStructured").mockImplementation(
      function (this: CodexProcess) {
        commandSentCount++;
      },
    );

    ws.send(
      JSON.stringify({
        type: "enqueue_codex_takeover",
        threadId,
        projectPath: "/repo",
        clientId: "client-lifecycle",
        queuedCommand: "echo takeover_verified",
      }),
    );

    // 1. Receives queued status
    const queuedMsg = await waitForMessage(
      (m) =>
        m.type === "codex_takeover_queue_status" && m.status === "queued",
    );
    expect(queuedMsg.queueId).toBeDefined();
    const queueId = queuedMsg.queueId;

    // 2. Receives resumed/running status with SAME queueId
    const runningMsg = await waitForMessage(
      (m) =>
        m.type === "codex_takeover_queue_status" &&
        m.status === "running" &&
        m.queueId === queueId,
    );
    expect(runningMsg.queueId).toBe(queueId);
    expect(runningMsg.sessionId).toBeDefined();

    // 3. Simulate turn completion (session becomes idle)
    (bridge as any).broadcastSessionMessage(runningMsg.sessionId, {
      type: "status",
      status: "idle",
      sessionId: runningMsg.sessionId,
    });

    // 4. Receives completed status with SAME queueId
    const completedMsg = await waitForMessage(
      (m) =>
        m.type === "codex_takeover_queue_status" &&
        m.status === "completed" &&
        m.queueId === queueId,
    );
    expect(completedMsg.queueId).toBe(queueId);

    // 5. Command was dispatched exactly once
    expect(commandSentCount).toBe(1);

    ws.close();
  });

  it("does not hijack active writer session while open, and automatically claims and runs after writer releases", async () => {
    const { ws, waitForMessage, received } = await connectClient();
    const threadId = "thread-writer-release-auto";

    vi.spyOn(bridge as any, "getCodexThreadHistory").mockResolvedValue([
      { type: "user", text: "initial turn" },
    ]);

    let commandSentCount = 0;
    vi.spyOn(CodexProcess.prototype, "waitForReady").mockImplementation(
      async function (this: CodexProcess) {
        (this as any).inputResolve = vi.fn();
        this.emit("input_ready");
      },
    );

    vi.spyOn(CodexProcess.prototype, "sendInputStructured").mockImplementation(
      function (this: CodexProcess) {
        commandSentCount++;
      },
    );

    // 1. Client A starts an active writer session on this thread
    const writerSessionId = (bridge["sessionManager"] as any).create(
      "/repo",
      undefined,
      undefined,
      undefined,
      "codex",
      { threadId },
    );
    const writerSession = (bridge["sessionManager"] as any).get(writerSessionId);
    expect(writerSession).toBeDefined();

    // 2. Client B enqueues a takeover
    ws.send(
      JSON.stringify({
        type: "enqueue_codex_takeover",
        threadId,
        projectPath: "/repo",
        clientId: "client-b-waiting",
        queuedCommand: "post-release command",
      }),
    );

    // 3. Receives queued status
    const queuedMsg = await waitForMessage(
      (m) =>
        m.type === "codex_takeover_queue_status" && m.status === "queued",
    );
    const queueId = queuedMsg.queueId;
    expect(queueId).toBeDefined();

    // 4. While Client A's session is alive, queue processing MUST NOT claim it
    await new Promise((r) => setTimeout(r, 100));
    const pendingBeforeRelease = queueStore.getPendingForThread(threadId);
    expect(pendingBeforeRelease.length).toBe(1);
    expect(pendingBeforeRelease[0].status).toBe("pending");

    // No running or completed messages broadcasted yet
    const runningBefore = received.filter(
      (m) =>
        m.type === "codex_takeover_queue_status" &&
        (m.status === "running" || m.status === "completed"),
    );
    expect(runningBefore.length).toBe(0);
    expect(commandSentCount).toBe(0);

    // 5. Now release writer session via stop_session
    ws.send(
      JSON.stringify({
        type: "stop_session",
        sessionId: writerSessionId,
      }),
    );

    // 6. Should automatically claim and broadcast running with SAME queueId
    const runningMsg = await waitForMessage(
      (m) =>
        m.type === "codex_takeover_queue_status" &&
        m.status === "running" &&
        m.queueId === queueId,
      5000,
    );
    expect(runningMsg.queueId).toBe(queueId);
    expect(runningMsg.sessionId).not.toBe(writerSessionId);

    // 7. Complete the turn
    (bridge as any).broadcastSessionMessage(runningMsg.sessionId, {
      type: "status",
      status: "idle",
      sessionId: runningMsg.sessionId,
    });

    // 8. Receives completed status with SAME queueId
    const completedMsg = await waitForMessage(
      (m) =>
        m.type === "codex_takeover_queue_status" &&
        m.status === "completed" &&
        m.queueId === queueId,
    );
    expect(completedMsg.queueId).toBe(queueId);
    expect(completedMsg.dispatchCount).toBe(1);
    expect(completedMsg.dispatchMarker).toBeDefined();
    expect(commandSentCount).toBe(1);

    ws.close();
  });

  it("get_codex_takeover_queue looks up by queueId fallback and returns dispatchCount", async () => {
    const threadId = "thread-fallback-test";
    const { item } = await queueStore.enqueue({
      threadId,
      projectPath: "/repo",
      clientId: "client-fallback",
      queuedCommand: "echo fallback",
    });

    await queueStore.markRunning(item.id, "session-123", "marker-xyz");

    const { ws, waitForMessage } = await connectClient();

    // Query with queueId only on different alias thread
    ws.send(
      JSON.stringify({
        type: "get_codex_takeover_queue",
        threadId: "different-thread-or-session-alias",
        queueId: item.id,
      }),
    );

    const statusMsg = await waitForMessage(
      (m) =>
        m.type === "codex_takeover_queue_status" && m.queueId === item.id,
    );

    expect(statusMsg.queueId).toBe(item.id);
    expect(statusMsg.status).toBe("running");
    expect(statusMsg.dispatchCount).toBe(1);
    expect(statusMsg.dispatchMarker).toBe("marker-xyz");

    ws.close();
  });

  it("broadcastTakeoverStatus broadcasts exactly once with dispatch metadata", async () => {
    const threadId = "thread-single-broadcast-test";

    const { ws, received, waitForMessage } = await connectClient();

    (bridge as any).broadcastTakeoverStatus({
      type: "codex_takeover_queue_status",
      threadId,
      queueId: "q-single-1",
      position: 0,
      total: 0,
      status: "running",
      dispatchCount: 1,
      dispatchMarker: "marker-abc",
    });

    const msg = await waitForMessage(
      (m) =>
        m.type === "codex_takeover_queue_status" &&
        m.queueId === "q-single-1" &&
        m.status === "running",
    );
    expect(msg.queueId).toBe("q-single-1");
    expect(msg.dispatchCount).toBe(1);
    expect(msg.dispatchMarker).toBe("marker-abc");

    // Ensure exactly 1 message was broadcasted
    await new Promise((r) => setTimeout(r, 50));
    const all = received.filter(
      (m) =>
        m.type === "codex_takeover_queue_status" &&
        m.queueId === "q-single-1",
    );
    expect(all.length).toBe(1);

    ws.close();
  });

  it("get_history on active-writer conflict thread classifies as active_writer_conflict, falls back to local history, and allows takeover", async () => {
    const threadId = "01a00976-b3f1-7831-8e03-b61c86acfac7";
    const { ws, waitForMessage, received } = await connectClient();

    // Mock RPC history failure with real app-server active-writer error text
    const getRpcHistorySpy = vi
      .spyOn(bridge as any, "getCodexThreadHistoryFromRpc")
      .mockRejectedValue(
        new CodexRpcError("thread/read", {
          code: -32603,
          message: `thread ${threadId} already has an active writer`,
        }),
      );

    // Mock local history fallback returning user and assistant turns
    const getLocalHistorySpy = vi
      .spyOn(bridge as any, "getCodexThreadHistory")
      .mockImplementation(async (id: string) => {
        if (id === threadId) {
          throw new CodexRpcError("thread/read", {
            code: -32603,
            message: `thread ${threadId} already has an active writer`,
          });
        }
        return [];
      });

    ws.send(JSON.stringify({ type: "get_history", sessionId: threadId }));

    // 1. Conflict message is received with canQueue: true
    const conflictMsg = await waitForMessage(
      (m) => m.type === "codex_takeover_conflict" && m.threadId === threadId,
    );
    expect(conflictMsg.canQueue).toBe(true);

    // 2. Error message has structured errorCode 'active_writer_conflict'
    const errorMsg = await waitForMessage(
      (m) =>
        m.type === "error" &&
        m.sessionId === threadId &&
        m.errorCode === "active_writer_conflict",
    );
    expect(errorMsg.errorCode).toBe("active_writer_conflict");
    expect(errorMsg.message).not.toContain("codex app-server is not running");

    // 3. Client can now queue takeover on this conflicting thread
    ws.send(
      JSON.stringify({
        type: "enqueue_codex_takeover",
        threadId,
        projectPath: "/repo",
        clientId: "client-after-conflict",
        queuedCommand: "queued command after history conflict",
      }),
    );

    const queuedMsg = await waitForMessage(
      (m) =>
        m.type === "codex_takeover_queue_status" &&
        m.threadId === threadId &&
        m.status === "queued",
    );
    expect(queuedMsg.status).toBe("queued");

    getRpcHistorySpy.mockRestore();
    getLocalHistorySpy.mockRestore();
    ws.close();
  });
});
