import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { rm, mkdir } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import {
  CodexTakeoverQueueStore,
  type CodexTakeoverQueueItem,
} from "./codex-takeover-queue.js";

describe("CodexTakeoverQueueStore Tests", () => {
  let testDir: string;
  let testFilePath: string;
  let store: CodexTakeoverQueueStore;

  beforeEach(async () => {
    testDir = join(tmpdir(), `ccpocket-takeover-test-${randomUUID()}`);
    await mkdir(testDir, { recursive: true });
    testFilePath = join(testDir, "queue.json");
    store = new CodexTakeoverQueueStore(testFilePath);
    await store.init();
  });

  afterEach(async () => {
    try {
      await rm(testDir, { recursive: true, force: true });
    } catch {
      // Cleanup best effort
    }
  });

  it("enqueues items in strict FIFO order", async () => {
    const threadId = "thread-1";
    const res1 = await store.enqueue({
      threadId,
      projectPath: "/repo",
      clientId: "client-a",
      queuedCommand: "first command",
    });
    expect(res1.isNew).toBe(true);
    expect(res1.position).toBe(1);
    expect(res1.total).toBe(1);

    const res2 = await store.enqueue({
      threadId,
      projectPath: "/repo",
      clientId: "client-b",
      queuedCommand: "second command",
    });
    expect(res2.isNew).toBe(true);
    expect(res2.position).toBe(2);
    expect(res2.total).toBe(2);

    const pending = store.getPendingForThread(threadId);
    expect(pending.length).toBe(2);
    expect(pending[0].id).toBe(res1.item.id);
    expect(pending[1].id).toBe(res2.item.id);
  });

  it("deduplicates requests for the same thread and client", async () => {
    const threadId = "thread-dedup";
    const res1 = await store.enqueue({
      threadId,
      projectPath: "/repo",
      clientId: "client-x",
      queuedCommand: "inspect code",
    });
    expect(res1.isNew).toBe(true);
    expect(res1.position).toBe(1);

    const res2 = await store.enqueue({
      threadId,
      projectPath: "/repo",
      clientId: "client-x",
      queuedCommand: "inspect code",
    });
    expect(res2.isNew).toBe(false);
    expect(res2.item.id).toBe(res1.item.id);
    expect(res2.position).toBe(1);
    expect(res2.total).toBe(1);

    const pending = store.getPendingForThread(threadId);
    expect(pending.length).toBe(1);
  });

  it("cancels queued item properly", async () => {
    const threadId = "thread-cancel";
    const res1 = await store.enqueue({
      threadId,
      projectPath: "/repo",
      clientId: "c1",
      queuedCommand: "cmd 1",
    });
    const res2 = await store.enqueue({
      threadId,
      projectPath: "/repo",
      clientId: "c2",
      queuedCommand: "cmd 2",
    });

    expect(store.getPendingForThread(threadId).length).toBe(2);

    const cancelRes = await store.cancel({
      threadId,
      queueId: res1.item.id,
    });
    expect(cancelRes.cancelled).toBe(true);
    expect(cancelRes.remainingCount).toBe(1);

    const remaining = store.getPendingForThread(threadId);
    expect(remaining.length).toBe(1);
    expect(remaining[0].id).toBe(res2.item.id);
  });

  it("persists queue state and recovers after restart / reconnection", async () => {
    const threadId = "thread-recovery";
    await store.enqueue({
      threadId,
      projectPath: "/repo",
      clientId: "c1",
      queuedCommand: "persisted cmd",
    });

    // Create a new store pointing to same file to simulate bridge restart / client reconnect
    const reloadedStore = new CodexTakeoverQueueStore(testFilePath);
    await reloadedStore.init();

    const pending = reloadedStore.getPendingForThread(threadId);
    expect(pending.length).toBe(1);
    expect(pending[0].queuedCommand).toBe("persisted cmd");
    expect(pending[0].status).toBe("pending");
  });

  it("guarantees single resume and single command send on release", async () => {
    const threadId = "thread-single-exec";
    await store.enqueue({
      threadId,
      projectPath: "/repo",
      clientId: "c1",
      queuedCommand: "run turn",
    });

    const resumeFn = vi.fn().mockResolvedValue(true);
    const sendCommandFn = vi.fn().mockResolvedValue(undefined);

    // First process attempt (when writer released)
    const result1 = await store.processNextInQueue(threadId, {
      resumeThread: resumeFn,
      sendCommand: sendCommandFn,
    });

    expect(result1.dispatched).toBe(true);
    expect(resumeFn).toHaveBeenCalledTimes(1);
    expect(sendCommandFn).toHaveBeenCalledTimes(1);

    // Second process attempt immediately after should do nothing
    const result2 = await store.processNextInQueue(threadId, {
      resumeThread: resumeFn,
      sendCommand: sendCommandFn,
    });

    expect(result2.dispatched).toBe(false);
    expect(resumeFn).toHaveBeenCalledTimes(1);
    expect(sendCommandFn).toHaveBeenCalledTimes(1);

    // Verify queue is now empty
    expect(store.getPendingForThread(threadId).length).toBe(0);
  });

  it("handles normal control execution without active writer conflict", async () => {
    const threadId = "thread-normal-control";
    const resumeFn = vi.fn().mockResolvedValue(true);

    const result = await store.processNextInQueue(threadId, {
      resumeThread: resumeFn,
    });

    expect(result.dispatched).toBe(false);
    expect(resumeFn).not.toHaveBeenCalled();

    await store.enqueue({
      threadId,
      projectPath: "/repo",
      clientId: "c1",
    });

    const dispatchedResult = await store.processNextInQueue(threadId, {
      resumeThread: resumeFn,
    });

    expect(dispatchedResult.dispatched).toBe(true);
    expect(resumeFn).toHaveBeenCalledTimes(1);
  });

  it("fail-safe: unknown status must NEVER report as completed", () => {
    expect(CodexTakeoverQueueStore.isStatusCompleted("completed")).toBe(true);
    expect(CodexTakeoverQueueStore.isStatusCompleted("done")).toBe(true);
    expect(CodexTakeoverQueueStore.isStatusCompleted("success")).toBe(true);

    expect(CodexTakeoverQueueStore.isStatusCompleted("unknown")).toBe(false);
    expect(CodexTakeoverQueueStore.isStatusCompleted("failed")).toBe(false);
    expect(CodexTakeoverQueueStore.isStatusCompleted("running")).toBe(false);
    expect(CodexTakeoverQueueStore.isStatusCompleted("idle")).toBe(false);
    expect(CodexTakeoverQueueStore.isStatusCompleted("")).toBe(false);
    expect(CodexTakeoverQueueStore.isStatusCompleted(undefined)).toBe(false);
  });

  it("unprocessed approvals default decline", () => {
    const declined: string[] = [];
    const pending = [
      { requestId: "req-1", toolUseId: "t1" },
      { requestId: "req-2", toolUseId: "t2" },
    ];

    CodexTakeoverQueueStore.declineUnhandledApprovals(pending, (item) => {
      declined.push(String(item.requestId));
    });

    expect(declined).toEqual(["req-1", "req-2"]);
  });
});
