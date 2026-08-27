import { mkdir, readFile, writeFile, rename } from "node:fs/promises";
import { join, dirname } from "node:path";
import { homedir } from "node:os";
import { randomUUID } from "node:crypto";

export type CodexTakeoverQueueItemStatus =
  | "pending"
  | "resumed"
  | "running"
  | "completed"
  | "dispatched"
  | "cancelled"
  | "failed";

export interface CodexTakeoverQueueItem {
  id: string;
  threadId: string;
  projectPath: string;
  enqueuedAt: string;
  clientId?: string;
  queuedCommand?: string;
  options?: Record<string, unknown>;
  status: CodexTakeoverQueueItemStatus;
  dispatchedAt?: string;
  completedAt?: string;
  sessionId?: string;
  result?: string;
}

export interface CodexTakeoverQueueState {
  items: CodexTakeoverQueueItem[];
}

export class CodexTakeoverQueueStore {
  private readonly filePath: string;
  private items: CodexTakeoverQueueItem[] = [];
  private initPromise: Promise<void> | null = null;
  private dispatchingThreads = new Set<string>();

  constructor(customFilePath?: string) {
    this.filePath =
      customFilePath ??
      join(homedir(), ".ccpocket", "codex-takeover-queue.json");
  }

  async init(): Promise<void> {
    if (!this.initPromise) {
      this.initPromise = this._doInit();
    }
    return this.initPromise;
  }

  async ensureInitialized(): Promise<void> {
    return this.init();
  }

  private async _doInit(): Promise<void> {
    try {
      await mkdir(dirname(this.filePath), { recursive: true });
      const raw = await readFile(this.filePath, "utf-8");
      const data = JSON.parse(raw) as CodexTakeoverQueueState;
      if (Array.isArray(data.items)) {
        const clean = (s: string) => s.replace(/^codex-/, "");
        const seenPending = new Set<string>();
        const restored: CodexTakeoverQueueItem[] = [];

        // Sort items chronologically
        const sorted = data.items
          .filter((item) => item && typeof item.threadId === "string")
          .sort(
            (a, b) =>
              new Date(a.enqueuedAt).getTime() -
              new Date(b.enqueuedAt).getTime(),
          );

        for (const item of sorted) {
          if (item.status === "pending") {
            const threadKey = clean(item.threadId);
            const dedupKey = item.clientId
              ? `${threadKey}:${item.clientId}`
              : threadKey;
            if (seenPending.has(dedupKey)) {
              // Reconcile and eliminate duplicate pending items on disk
              restored.push({ ...item, status: "cancelled" });
            } else {
              seenPending.add(dedupKey);
              restored.push({ ...item, status: "pending" });
            }
          } else {
            restored.push(item);
          }
        }
        this.items = restored;
      }
    } catch {
      // File doesn't exist yet or is empty
      this.items = [];
    }
  }

  private async save(): Promise<void> {
    try {
      await mkdir(dirname(this.filePath), { recursive: true });
      const tmpPath = `${this.filePath}.${randomUUID()}.tmp`;
      const data: CodexTakeoverQueueState = {
        items: this.items,
      };
      await writeFile(tmpPath, JSON.stringify(data, null, 2), "utf-8");
      await rename(tmpPath, this.filePath);
    } catch (err) {
      console.error("[codex-takeover-queue] Failed to persist queue:", err);
    }
  }

  /**
   * Enqueues a takeover request for a Codex thread.
   * Performs deduplication: if an item with status === 'pending' already exists
   * for the same threadId and (same clientId or same queuedCommand), returns the existing item.
   */
  async enqueue(params: {
    threadId: string;
    projectPath: string;
    clientId?: string;
    queuedCommand?: string;
    options?: Record<string, unknown>;
  }): Promise<{
    item: CodexTakeoverQueueItem;
    isNew: boolean;
    position: number;
    total: number;
  }> {
    await this.ensureInitialized();
    const { threadId, projectPath, clientId, queuedCommand, options } = params;

    // Check deduplication
    const clean = (s: string) => s.replace(/^codex-/, "");
    const target = clean(threadId);
    const existing = this.items.find(
      (it) =>
        (it.threadId === threadId || clean(it.threadId) === target) &&
        it.status === "pending" &&
        (!clientId || !it.clientId || it.clientId === clientId),
    );

    if (existing) {
      if (queuedCommand && !existing.queuedCommand) {
        existing.queuedCommand = queuedCommand;
        await this.save();
      }
      const threadPending = this.getPendingForThread(threadId);
      const pos = threadPending.findIndex((it) => it.id === existing.id) + 1;
      return {
        item: existing,
        isNew: false,
        position: pos > 0 ? pos : 1,
        total: threadPending.length,
      };
    }

    const newItem: CodexTakeoverQueueItem = {
      id: randomUUID().slice(0, 8),
      threadId,
      projectPath,
      enqueuedAt: new Date().toISOString(),
      clientId,
      queuedCommand,
      options,
      status: "pending",
    };

    this.items.push(newItem);
    await this.save();

    const threadPending = this.getPendingForThread(threadId);
    const pos = threadPending.findIndex((it) => it.id === newItem.id) + 1;
    return {
      item: newItem,
      isNew: true,
      position: pos > 0 ? pos : threadPending.length,
      total: threadPending.length,
    };
  }

  /**
   * Cancels a pending queue item by queueId or threadId (+ clientId).
   */
  async cancel(params: {
    threadId: string;
    queueId?: string;
    clientId?: string;
  }): Promise<{ cancelled: boolean; remainingCount: number }> {
    await this.ensureInitialized();
    const { threadId, queueId, clientId } = params;

    const clean = (s: string) => s.replace(/^codex-/, "");
    const target = clean(threadId);
    let matched = false;
    for (const item of this.items) {
      if (
        (item.threadId !== threadId && clean(item.threadId) !== target) ||
        item.status !== "pending"
      ) {
        continue;
      }
      if (queueId && item.id === queueId) {
        item.status = "cancelled";
        matched = true;
        break;
      }
      if (!queueId && clientId && item.clientId === clientId) {
        item.status = "cancelled";
        matched = true;
        break;
      }
      if (!queueId && !clientId) {
        item.status = "cancelled";
        matched = true;
      }
    }

    if (matched) {
      await this.save();
    }

    const remaining = this.getPendingForThread(threadId).length;
    return { cancelled: matched, remainingCount: remaining };
  }

  /**
   * Returns all pending items for a specific thread, in strict FIFO order.
   */
  getPendingForThread(threadId: string): CodexTakeoverQueueItem[] {
    const clean = (s: string) => s.replace(/^codex-/, "");
    const target = clean(threadId);
    return this.items
      .filter(
        (it) =>
          (it.threadId === threadId || clean(it.threadId) === target) &&
          it.status === "pending",
      )
      .sort(
        (a, b) =>
          new Date(a.enqueuedAt).getTime() - new Date(b.enqueuedAt).getTime(),
      );
  }

  /**
   * Returns all threadIds that currently have pending items.
   */
  getPendingThreadIds(): string[] {
    const set = new Set<string>();
    for (const item of this.items) {
      if (item.status === "pending") {
        set.add(item.threadId);
      }
    }
    return Array.from(set);
  }

  /**
   * Gets position (1-indexed) and total for a queue item by queueId or clientId.
   */
  getItemPosition(
    threadId: string,
    queueIdOrClientId: string,
  ): { position: number; total: number; item: CodexTakeoverQueueItem } | null {
    const pending = this.getPendingForThread(threadId);
    const idx = pending.findIndex(
      (it) => it.id === queueIdOrClientId || it.clientId === queueIdOrClientId,
    );
    if (idx === -1) return null;
    return {
      position: idx + 1,
      total: pending.length,
      item: pending[idx],
    };
  }

  /**
   * Resolves queue status for a query.
   */
  getQueueStatus(params: {
    threadId: string;
    queueId?: string;
    clientId?: string;
  }): {
    queueId?: string;
    position: number;
    total: number;
    status: "queued" | "running" | "completed" | "cancelled" | "not_queued";
    item?: CodexTakeoverQueueItem;
  } {
    const clean = (s: string) => s.replace(/^codex-/, "");
    const target = clean(params.threadId);
    const pending = this.getPendingForThread(params.threadId);

    // 1. If explicit queueId specified, check that specific item
    if (params.queueId) {
      const item = this.items.find(
        (it) =>
          (it.threadId === params.threadId || clean(it.threadId) === target) &&
          it.id === params.queueId,
      );
      if (item) {
        if (item.status === "pending") {
          const idx = pending.findIndex((it) => it.id === item.id);
          return {
            queueId: item.id,
            position: idx >= 0 ? idx + 1 : 1,
            total: pending.length,
            status: "queued",
            item,
          };
        }
        if (
          item.status === "running" ||
          item.status === "resumed" ||
          item.status === "dispatched"
        ) {
          return {
            queueId: item.id,
            position: 0,
            total: 0,
            status: "running",
            item,
          };
        }
        if (item.status === "completed") {
          return {
            queueId: item.id,
            position: 0,
            total: 0,
            status: "completed",
            item,
          };
        }
        if (item.status === "cancelled") {
          return {
            queueId: item.id,
            position: 0,
            total: pending.length,
            status: "not_queued",
            item,
          };
        }
      } else {
        return {
          queueId: params.queueId,
          position: 0,
          total: pending.length,
          status: "not_queued",
        };
      }
    }

    // 2. If explicit clientId specified
    if (params.clientId) {
      const item = pending.find((it) => it.clientId === params.clientId);
      if (item) {
        const idx = pending.findIndex((it) => it.id === item.id);
        return {
          queueId: item.id,
          position: idx >= 0 ? idx + 1 : 1,
          total: pending.length,
          status: "queued",
          item,
        };
      } else {
        return {
          queueId: undefined,
          position: 0,
          total: pending.length,
          status: "not_queued",
        };
      }
    }

    // 3. If there are pending items for this thread
    if (pending.length > 0) {
      const item = pending[0];
      return {
        queueId: item.id,
        position: 1,
        total: pending.length,
        status: "queued",
        item,
      };
    }

    // 4. Check for recently running or completed item
    const recent = this.items
      .slice()
      .reverse()
      .find(
        (it) =>
          (it.threadId === params.threadId || clean(it.threadId) === target) &&
          (it.status === "running" ||
            it.status === "completed" ||
            it.status === "resumed" ||
            it.status === "dispatched"),
      );
    if (recent) {
      return {
        queueId: recent.id,
        position: 0,
        total: 0,
        status: recent.status === "completed" ? "completed" : "running",
        item: recent,
      };
    }

    return {
      queueId: undefined,
      position: 0,
      total: 0,
      status: "not_queued",
    };
  }

  /**
   * Marks a queue item as dispatched / running.
   */
  async markDispatched(queueId: string): Promise<boolean> {
    await this.ensureInitialized();
    const item = this.items.find((it) => it.id === queueId);
    if (item && item.status === "pending") {
      item.status = "dispatched";
      item.dispatchedAt = new Date().toISOString();
      await this.save();
      return true;
    }
    return false;
  }

  /**
   * Marks a queue item as running with associated session id.
   */
  async markRunning(queueId: string, sessionId?: string): Promise<boolean> {
    await this.ensureInitialized();
    const item = this.items.find((it) => it.id === queueId);
    if (
      item &&
      (item.status === "pending" ||
        item.status === "resumed" ||
        item.status === "dispatched")
    ) {
      item.status = "running";
      item.dispatchedAt = item.dispatchedAt ?? new Date().toISOString();
      if (sessionId) item.sessionId = sessionId;
      await this.save();
      return true;
    }
    return false;
  }

  /**
   * Marks a queue item as completed with optional result.
   */
  async markCompleted(queueId: string, result?: string): Promise<boolean> {
    await this.ensureInitialized();
    const item = this.items.find((it) => it.id === queueId);
    if (item && item.status !== "completed" && item.status !== "cancelled") {
      item.status = "completed";
      item.completedAt = new Date().toISOString();
      if (result) item.result = result;
      await this.save();
      return true;
    }
    return false;
  }

  /**
   * Marks the most recent active/running queue item for a thread as completed.
   */
  async markCompletedForThread(
    threadId: string,
    result?: string,
  ): Promise<CodexTakeoverQueueItem | null> {
    await this.ensureInitialized();
    const clean = (s: string) => s.replace(/^codex-/, "");
    const target = clean(threadId);
    const item = this.items
      .slice()
      .reverse()
      .find(
        (it) =>
          (it.threadId === threadId || clean(it.threadId) === target) &&
          (it.status === "running" ||
            it.status === "resumed" ||
            it.status === "dispatched"),
      );
    if (item) {
      item.status = "completed";
      item.completedAt = new Date().toISOString();
      if (result) item.result = result;
      await this.save();
      return item;
    }
    return null;
  }

  /**
   * Attempts to dispatch the next item in queue for a thread.
   * Guarantees at most ONE resume call and at most ONE command dispatch per queued item.
   */
  async processNextInQueue(
    threadId: string,
    executor: {
      resumeThread: (item: CodexTakeoverQueueItem) => Promise<boolean>;
      sendCommand?: (item: CodexTakeoverQueueItem) => Promise<void>;
    },
  ): Promise<{ dispatched: boolean; item?: CodexTakeoverQueueItem }> {
    await this.ensureInitialized();
    if (this.dispatchingThreads.has(threadId)) {
      return { dispatched: false };
    }

    const pending = this.getPendingForThread(threadId);
    if (pending.length === 0) {
      return { dispatched: false };
    }

    const nextItem = pending[0];
    this.dispatchingThreads.add(threadId);

    try {
      // 1. Attempt resume AT MOST ONCE
      const resumed = await executor.resumeThread(nextItem);
      if (!resumed) {
        return { dispatched: false };
      }

      // 2. Mark dispatched immediately to prevent duplicate dispatch
      await this.markDispatched(nextItem.id);

      // 3. If there is a queued command, dispatch it AT MOST ONCE
      if (nextItem.queuedCommand && executor.sendCommand) {
        await executor.sendCommand(nextItem);
      }

      return { dispatched: true, item: nextItem };
    } finally {
      this.dispatchingThreads.delete(threadId);
    }
  }

  /**
   * Fail-safe check: unknown status MUST NEVER report as completed.
   */
  static isStatusCompleted(status: string | undefined): boolean {
    if (!status) return false;
    const s = status.trim().toLowerCase();
    return s === "completed" || s === "done" || s === "success";
  }

  /**
   * Default decline helper for unprocessed tool approvals or user questions.
   */
  static declineUnhandledApprovals<T extends { toolUseId?: string; requestId?: string | number }>(
    unhandled: T[],
    declineFn: (item: T) => void,
  ): void {
    for (const item of unhandled) {
      try {
        declineFn(item);
      } catch (err) {
        console.warn("[codex-takeover-queue] Error declining unhandled approval:", err);
      }
    }
  }
}
