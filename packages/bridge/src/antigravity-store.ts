import { mkdir, readFile, writeFile, readdir, unlink } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";
import { randomUUID } from "node:crypto";
import type { SessionIndexEntry, GetRecentSessionsOptions } from "./sessions-index.js";

export interface AntigravitySessionRecord {
  bridgeSessionId: string;
  antigravityConversationId?: string;
  provider: "antigravity";
  workspacePath: string;
  mode: "plan" | "accept-edits" | "execute";
  model: string;
  terminalStatus: "queued" | "running" | "interrupting" | "interrupted" | "completed" | "failed" | "unknown";
  turnId?: string;
  currentTurn: number;
  firstPrompt: string;
  lastPrompt?: string;
  finalResult?: string;
  failureCode?: string | null;
  failureMessage?: string | null;
  name?: string;
  createdAt: string;
  updatedAt: string;
  lastActivityAt: string;
}

export class AntigravityStore {
  private readonly dirPath: string;
  private memoryCache: Map<string, AntigravitySessionRecord> = new Map();
  private initPromise: Promise<void> | null = null;

  constructor(customDir?: string) {
    this.dirPath = customDir ?? join(homedir(), ".ccpocket", "antigravity-sessions");
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
    await mkdir(this.dirPath, { recursive: true });
    try {
      const files = await readdir(this.dirPath);
      for (const file of files) {
        if (!file.endsWith(".json")) continue;
        try {
          const raw = await readFile(join(this.dirPath, file), "utf-8");
          const record = JSON.parse(raw) as AntigravitySessionRecord;
          if (record.bridgeSessionId) {
            // On startup, uncompleted running/interrupting sessions become unknown
            if (record.terminalStatus === "running" || record.terminalStatus === "interrupting") {
              record.terminalStatus = "unknown";
              record.updatedAt = new Date().toISOString();
              await this.saveSession(record);
            }
            this.memoryCache.set(record.bridgeSessionId, record);
            if (record.antigravityConversationId) {
              this.memoryCache.set(record.antigravityConversationId, record);
            }
          }
        } catch {
          // Ignore corrupted single file
        }
      }
    } catch {
      // Directory read failed
    }
    console.log(`[antigravity-store] Loaded ${new Set(this.memoryCache.values()).size} Antigravity session(s) from ${this.dirPath}`);
  }

  async saveSession(record: AntigravitySessionRecord): Promise<void> {
    record.updatedAt = new Date().toISOString();
    record.lastActivityAt = record.updatedAt;
    this.memoryCache.set(record.bridgeSessionId, record);
    if (record.antigravityConversationId) {
      this.memoryCache.set(record.antigravityConversationId, record);
    }

    await mkdir(this.dirPath, { recursive: true });
    const targetFile = join(this.dirPath, `${record.bridgeSessionId}.json`);
    const tmpFile = join(this.dirPath, `${record.bridgeSessionId}.${randomUUID()}.tmp`);
    await writeFile(tmpFile, JSON.stringify(record, null, 2), "utf-8");
    const { rename } = await import("node:fs/promises");
    await rename(tmpFile, targetFile);
  }

  getSession(id: string): AntigravitySessionRecord | undefined {
    return this.memoryCache.get(id);
  }

  getAllSessions(): AntigravitySessionRecord[] {
    return Array.from(new Set(this.memoryCache.values()));
  }

  async deleteSession(sessionId: string): Promise<void> {
    const record = this.memoryCache.get(sessionId);
    if (record) {
      this.memoryCache.delete(record.bridgeSessionId);
      if (record.antigravityConversationId) {
        this.memoryCache.delete(record.antigravityConversationId);
      }
      try {
        await unlink(join(this.dirPath, `${record.bridgeSessionId}.json`));
      } catch {
        // File may not exist
      }
    }
  }

  listRecentSessions(options: GetRecentSessionsOptions = {}): SessionIndexEntry[] {
    const records = this.getAllSessions();
    const results: SessionIndexEntry[] = [];

    for (const rec of records) {
      if (options.projectPath && rec.workspacePath !== options.projectPath) {
        continue;
      }
      if (options.sessionId && rec.bridgeSessionId !== options.sessionId && rec.antigravityConversationId !== options.sessionId) {
        continue;
      }
      if (options.archivedSessionIds && options.archivedSessionIds.has(rec.bridgeSessionId)) {
        continue;
      }
      if (options.provider && options.provider !== "antigravity") {
        continue;
      }
      if (options.namedOnly && !rec.name) {
        continue;
      }
      if (options.searchQuery) {
        const q = options.searchQuery.toLowerCase();
        const matches =
          (rec.name && rec.name.toLowerCase().includes(q)) ||
          rec.firstPrompt.toLowerCase().includes(q) ||
          (rec.lastPrompt && rec.lastPrompt.toLowerCase().includes(q)) ||
          (rec.finalResult && rec.finalResult.toLowerCase().includes(q));
        if (!matches) continue;
      }

      results.push({
        sessionId: rec.bridgeSessionId,
        provider: "antigravity",
        name: rec.name,
        firstPrompt: rec.firstPrompt || "Antigravity Session",
        lastPrompt: rec.lastPrompt,
        summary: rec.finalResult ? rec.finalResult.slice(0, 120) : undefined,
        created: rec.createdAt,
        modified: rec.lastActivityAt || rec.updatedAt || rec.createdAt,
        gitBranch: "main",
        projectPath: rec.workspacePath,
        resumeCwd: rec.workspacePath,
        permissionMode: rec.mode === "accept-edits" ? "acceptEdits" : "plan",
        isSidechain: false,
      });
    }

    results.sort((a, b) => new Date(b.modified).getTime() - new Date(a.modified).getTime());
    return results;
  }
}

export const globalAntigravityStore = new AntigravityStore();
