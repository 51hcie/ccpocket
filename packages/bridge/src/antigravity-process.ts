import { spawn, type ChildProcess } from "node:child_process";
import { EventEmitter } from "node:events";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { randomUUID } from "node:crypto";
import type {
  ServerMessage,
  ProcessStatus,
  AssistantMessage,
  AssistantTextContent,
  AssistantToolUseContent,
} from "./parser.js";

export type AntigravityExecutionMode = "plan" | "accept-edits" | "execute";
export type AntigravityTerminalStatus =
  | "queued"
  | "running"
  | "waiting_for_input"
  | "completed"
  | "failed"
  | "interrupted"
  | "unknown";

export interface AntigravityStartOptions {
  sessionId?: string;
  conversationId?: string;
  workspacePath: string;
  prompt: string;
  mode?: AntigravityExecutionMode;
  model?: string;
}

export interface AntigravityProcessEvents {
  message: [ServerMessage];
  status: [ProcessStatus];
  exit: [number | null];
}

export class AntigravityProcess extends EventEmitter {
  private child: ChildProcess | null = null;
  private agyBinPath: string;
  private workspacePath: string;
  private currentMode: AntigravityExecutionMode = "plan";
  private currentModel: string = "gemini-3.7-flash-high";
  private conversationId: string | null = null;
  private turnId: string | null = null;
  private internalStatus: AntigravityTerminalStatus = "queued";
  private bridgeStatus: ProcessStatus = "idle";
  private hasStructuredResult = false;
  private structuredResultStatus: string | null = null;
  private failureCode: string | null = null;
  private failureMessage: string | null = null;
  private stdoutBuf = "";
  private currentAssistantMessageId: string | null = null;
  private isExplicitInterrupt = false;

  constructor(workspacePath: string, agyBin?: string) {
    super();
    this.workspacePath = workspacePath;
    this.agyBinPath = agyBin ?? this.findAgyBinary();
  }

  private findAgyBinary(): string {
    const candidates = [
      process.env.AGY_BIN_PATH,
      "/Users/lw/Windows_Projects/Macremote/tools/bin/agy",
      "/Users/lw/Windows_Projects/Macremote_spike/tools/bin/agy",
      resolve(process.cwd(), "../../../tools/bin/agy"),
      resolve(process.cwd(), "tools/bin/agy"),
    ].filter(Boolean) as string[];

    for (const c of candidates) {
      if (existsSync(c)) return c;
    }
    return "agy";
  }

  getConversationId(): string | null {
    return this.conversationId;
  }

  getTurnId(): string | null {
    return this.turnId;
  }

  setConversationId(id: string) {
    this.conversationId = id;
  }

  getMode(): AntigravityExecutionMode {
    return this.currentMode;
  }

  getModel(): string {
    return this.currentModel;
  }

  getTerminalStatus(): AntigravityTerminalStatus {
    return this.internalStatus;
  }

  getBridgeStatus(): ProcessStatus {
    return this.bridgeStatus;
  }

  isRunning(): boolean {
    return this.internalStatus === "running" && this.child !== null && !this.child.killed;
  }

  /**
   * Spawns a turn of agy.
   * Delivers prompt strictly via --print to avoid duplicate prompt submission.
   */
  async start(options: AntigravityStartOptions): Promise<void> {
    this.workspacePath = options.workspacePath || this.workspacePath;
    this.currentMode = options.mode ?? this.currentMode;
    this.currentModel =
      options.model ??
      process.env.BRIDGE_AGY_MODEL ??
      process.env.MACREMOTE_AGY_MODEL ??
      "gemini-3.7-flash-high";
    if (options.conversationId) {
      this.conversationId = options.conversationId;
    }

    if (options.prompt && options.prompt.trim().length > 0) {
      await this.spawnTurn(options.prompt);
    } else {
      this.internalStatus = "waiting_for_input";
      this.bridgeStatus = "idle";
      this.emit("status", "idle");
    }
  }

  async sendInput(text: string): Promise<void> {
    if (this.isRunning()) {
      throw new Error("Cannot send input while turn is still running");
    }
    await this.spawnTurn(text);
  }

  private async spawnTurn(prompt: string): Promise<void> {
    this.isExplicitInterrupt = false;
    this.hasStructuredResult = false;
    this.structuredResultStatus = null;
    this.failureCode = null;
    this.failureMessage = null;
    this.stdoutBuf = "";
    this.turnId = randomUUID();

    const args = [
      "--add-dir",
      this.workspacePath,
      "--dangerously-skip-permissions",
      "--output-format",
      "stream-json",
      "--mode",
      this.currentMode === "accept-edits" || this.currentMode === "execute"
        ? "accept-edits"
        : "plan",
      "--model",
      this.currentModel,
      "--print",
      prompt,
    ];

    if (this.conversationId) {
      args.push("--conversation", this.conversationId);
    }

    this.internalStatus = "running";
    this.bridgeStatus = "running";
    this.emit("status", "running");

    try {
      this.child = spawn(this.agyBinPath, args, {
        cwd: this.workspacePath,
        stdio: ["ignore", "pipe", "pipe"],
        env: {
          ...process.env,
          PATH: `${resolve(this.workspacePath, "tools/bin")}:${process.env.PATH}`,
        },
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      this.internalStatus = "failed";
      this.bridgeStatus = "idle";
      this.failureCode = "SPAWN_ERROR";
      this.failureMessage = msg;
      this.emit("status", "idle");
      this.emit("message", {
        type: "result",
        subtype: "error",
        error: msg,
      } as ServerMessage);
      return;
    }

    this.child.stdout?.on("data", (chunk: Buffer) => {
      this.stdoutBuf += chunk.toString("utf8");
      const lines = this.stdoutBuf.split("\n");
      this.stdoutBuf = lines.pop() ?? "";

      for (const line of lines) {
        this.processStreamLine(line);
      }
    });

    this.child.stderr?.on("data", (chunk: Buffer) => {
      const errText = chunk.toString("utf8");
      if (errText.includes("ERROR") || errText.includes("error")) {
        this.failureMessage = errText.trim();
      }
    });

    this.child.on("error", (err) => {
      this.internalStatus = "failed";
      this.bridgeStatus = "idle";
      this.failureCode = "PROCESS_ERROR";
      this.failureMessage = err.message;
      this.emit("status", "idle");
      this.emit("exit", 1);
    });

    this.child.on("exit", (code, signal) => {
      if (this.stdoutBuf.trim()) {
        this.processStreamLine(this.stdoutBuf);
        this.stdoutBuf = "";
      }

      if (this.isExplicitInterrupt || signal === "SIGTERM" || signal === "SIGINT" || code === 143 || code === 130) {
        this.internalStatus = "interrupted";
        this.bridgeStatus = "idle";
        if (!this.hasStructuredResult) {
          this.emit("message", {
            type: "result",
            subtype: "interrupted",
            sessionId: this.conversationId,
          } as ServerMessage);
        }
      } else if (this.hasStructuredResult && (this.structuredResultStatus === "SUCCESS" || this.structuredResultStatus === "completed")) {
        this.internalStatus = "completed";
        this.bridgeStatus = "idle";
      } else if (this.hasStructuredResult) {
        this.internalStatus = "failed";
        this.bridgeStatus = "idle";
      } else {
        this.internalStatus = "failed";
        this.bridgeStatus = "idle";
        this.failureCode = "NO_STRUCTURED_RESULT";
        this.failureMessage = `Process exited with code ${code} without structured completion result`;
      }

      this.emit("status", "idle");
      this.emit("exit", code);
    });
  }

  processStreamLine(line: string): void {
    const trimmed = line.trim();
    if (!trimmed) return;

    let evt: Record<string, unknown>;
    try {
      evt = JSON.parse(trimmed);
    } catch {
      return;
    }

    if (evt.event === "init" && typeof evt.init === "object" && evt.init !== null) {
      const initObj = evt.init as Record<string, unknown>;
      if (typeof evt.conversation_id === "string") {
        this.conversationId = evt.conversation_id;
      }
      this.emit("message", {
        type: "system",
        subtype: "init",
        sessionId: this.conversationId ?? undefined,
        provider: "antigravity",
        model: (initObj.model as string) || this.currentModel,
        projectPath: this.workspacePath,
      } as ServerMessage);
      return;
    }

    if (evt.event === "step_update" && typeof evt.step_update === "object" && evt.step_update !== null) {
      const su = evt.step_update as Record<string, unknown>;
      if (typeof su.conversation_id === "string" && !this.conversationId) {
        this.conversationId = su.conversation_id;
      }

      const stepType = su.step_type as string | undefined;

      if (stepType === "agent_response" && typeof su.text_delta === "string") {
        if (!this.currentAssistantMessageId) {
          this.currentAssistantMessageId = randomUUID();
        }
        const textContent: AssistantTextContent = {
          type: "text",
          text: su.text_delta,
        };
        const assistantMsg: AssistantMessage = {
          id: this.currentAssistantMessageId,
          role: "assistant",
          content: [textContent],
          model: this.currentModel,
        };
        this.emit("message", {
          type: "assistant",
          message: assistantMsg,
        } as ServerMessage);
        return;
      }

      if (stepType === "tool") {
        const toolName = (su.tool_name as string) || "tool";
        const toolInfo = (su.tool_info as Record<string, unknown>) || {};
        const params = (toolInfo.parameters as Record<string, unknown>) || {};
        const toolId = randomUUID();

        const toolContent: AssistantToolUseContent = {
          type: "tool_use",
          id: toolId,
          name: toolName,
          input: params,
        };
        const assistantMsg: AssistantMessage = {
          id: randomUUID(),
          role: "assistant",
          content: [toolContent],
          model: this.currentModel,
        };
        this.emit("message", {
          type: "assistant",
          message: assistantMsg,
        } as ServerMessage);
        return;
      }
    }

    if (evt.event === "result" && typeof evt.result === "object" && evt.result !== null) {
      const res = evt.result as Record<string, unknown>;
      this.hasStructuredResult = true;

      const rawStatus = String(res.status ?? "").toUpperCase();
      const rawError = String(res.error ?? "");

      const isCanceled =
        this.isExplicitInterrupt ||
        rawStatus === "INTERRUPTED" ||
        rawStatus === "CANCELED" ||
        rawError.includes("context canceled") ||
        rawError.includes("interrupt");

      const isSuccess = !isCanceled && (rawStatus === "SUCCESS" || rawStatus === "COMPLETED");

      if (isCanceled) {
        this.internalStatus = "interrupted";
        this.structuredResultStatus = "INTERRUPTED";
      } else if (isSuccess) {
        this.internalStatus = "completed";
        this.structuredResultStatus = "SUCCESS";
      } else {
        this.internalStatus = "failed";
        this.structuredResultStatus = rawStatus || "ERROR";
        this.failureCode = (res.error_code as string) || "TASK_ERROR";
        this.failureMessage = rawError || "Task execution failed";
      }

      const responseText = typeof res.response === "string" ? res.response.trim() : "";
      if (responseText) {
        const textContent: AssistantTextContent = {
          type: "text",
          text: responseText,
        };
        const assistantMsg: AssistantMessage = {
          id: randomUUID(),
          role: "assistant",
          content: [textContent],
          model: this.currentModel,
        };
        this.emit("message", {
          type: "assistant",
          message: assistantMsg,
        } as ServerMessage);
      }

      this.emit("message", {
        type: "result",
        subtype: isSuccess ? "success" : isCanceled ? "interrupted" : "error",
        result: responseText,
        duration: typeof res.duration_seconds === "number" ? Math.round(res.duration_seconds * 1000) : undefined,
        sessionId: this.conversationId,
        error: isSuccess ? undefined : (res.error ? String(res.error) : undefined),
      } as ServerMessage);
    }
  }

  get isWaitingForInput(): boolean {
    return this.internalStatus === "waiting_for_input" || this.internalStatus === "completed" || this.internalStatus === "queued";
  }

  stop(): void {
    this.interrupt();
  }

  interrupt(): boolean {
    if (!this.child || this.child.killed) {
      return false;
    }
    this.isExplicitInterrupt = true;
    this.internalStatus = "interrupting";
    try {
      this.child.kill("SIGTERM");
      return true;
    } catch {
      return false;
    }
  }
}
