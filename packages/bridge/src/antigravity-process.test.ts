import { describe, it, expect, vi } from "vitest";
import {
  AntigravityProcess,
  ANTIGRAVITY_DEFAULT_MODEL,
  ANTIGRAVITY_SUPPORTED_MODELS,
} from "./antigravity-process.js";
import type { ServerMessage } from "./parser.js";

describe("AntigravityProcess Unit Tests", () => {
  it("defaults to gemini-3.7-flash-medium and supports default model", async () => {
    const proc = new AntigravityProcess("/tmp/workspace");
    expect(proc.getModel()).toBe(ANTIGRAVITY_DEFAULT_MODEL);
    expect(proc.getModel()).toBe("gemini-3.7-flash-medium");

    await proc.start({
      workspacePath: "/tmp/workspace",
      prompt: "",
    });
    expect(proc.getModel()).toBe("gemini-3.7-flash-medium");
  });

  it("contains and supports all 14 official Antigravity models without overriding to high", async () => {
    const expectedModels = [
      "gemini-3.7-flash-high",
      "gemini-3.7-flash-medium",
      "gemini-3.7-flash-low",
      "gemini-3.6-flash-high",
      "gemini-3.6-flash-medium",
      "gemini-3.6-flash-low",
      "gemini-3.5-flash-high",
      "gemini-3.5-flash-medium",
      "gemini-3.5-flash-low",
      "gemini-3.1-pro-high",
      "gemini-3.1-pro-low",
      "claude-sonnet-4-6",
      "claude-opus-4-6-thinking",
      "gpt-oss-120b-medium",
    ];

    expect(ANTIGRAVITY_SUPPORTED_MODELS).toEqual(expectedModels);

    for (const m of expectedModels) {
      const proc = new AntigravityProcess("/tmp/workspace");
      await proc.start({
        workspacePath: "/tmp/workspace",
        prompt: "",
        model: m,
      });
      expect(proc.getModel()).toBe(m);
    }
  });

  it("discovers conversationId and emits system init event", () => {
    const proc = new AntigravityProcess("/tmp/workspace");
    const messages: ServerMessage[] = [];
    proc.on("message", (msg) => messages.push(msg));

    proc.processStreamLine(
      JSON.stringify({
        event: "init",
        conversation_id: "conv-12345",
        init: { model: "gemini-3.7-flash-medium" },
      })
    );

    expect(proc.getConversationId()).toBe("conv-12345");
    expect(messages.length).toBe(1);
    expect(messages[0].type).toBe("system");
    expect(messages[0].sessionId).toBe("conv-12345");
    expect(messages[0].provider).toBe("antigravity");
    expect((messages[0] as any).model).toBe("gemini-3.7-flash-medium");
  });

  it("measures turn wall-clock duration rather than accumulated conversation duration_seconds", async () => {
    const proc = new AntigravityProcess("/tmp/workspace");
    const messages: ServerMessage[] = [];
    proc.on("message", (msg) => messages.push(msg));

    // Manually set turnStartTime to simulate 250ms elapsed
    (proc as any).turnStartTime = Date.now() - 250;

    proc.processStreamLine(
      JSON.stringify({
        event: "result",
        result: {
          conversation_id: "conv-res",
          status: "SUCCESS",
          response: "Turn 2 completed",
          duration_seconds: 120.5, // Cumulative session time from AGY
          num_turns: 5,
        },
      })
    );

    expect(messages.length).toBe(2);
    const resMsg = messages[1] as any;
    expect(resMsg.type).toBe("result");
    expect(resMsg.duration).toBeGreaterThanOrEqual(200);
    expect(resMsg.duration).toBeLessThan(5000); // Must NOT be 120500ms
  });

  it("supports persistent multi-turn process reuse without respawning child", async () => {
    const proc = new AntigravityProcess("/tmp/workspace");
    const messages: ServerMessage[] = [];
    proc.on("message", (msg) => messages.push(msg));

    const writtenChunks: string[] = [];
    const mockStdin = {
      writable: true,
      write: (data: string) => {
        writtenChunks.push(data);
        return true;
      },
    };

    // Attach mock child
    (proc as any).child = {
      killed: false,
      stdin: mockStdin,
      kill: vi.fn(),
    };
    (proc as any).conversationId = "conv-multi";

    // Turn 1
    await proc.sendInput("Hello turn 1");
    expect(proc.isRunning()).toBe(true);
    expect(writtenChunks.length).toBe(1);
    expect(JSON.parse(writtenChunks[0])).toEqual({
      event: "user",
      message: { content: "Hello turn 1" },
    });

    // Complete Turn 1
    proc.processStreamLine(
      JSON.stringify({
        event: "result",
        result: {
          conversation_id: "conv-multi",
          status: "SUCCESS",
          response: "Turn 1 response",
          duration_seconds: 2.0,
        },
      })
    );
    expect(proc.isRunning()).toBe(false);
    expect(proc.getTerminalStatus()).toBe("completed");

    // Turn 2 reuses the same child process without respawning
    await proc.sendInput("Hello turn 2");
    expect(proc.isRunning()).toBe(true);
    expect(writtenChunks.length).toBe(2);
    expect(JSON.parse(writtenChunks[1])).toEqual({
      event: "user",
      message: { content: "Hello turn 2" },
    });

    // Complete Turn 2
    proc.processStreamLine(
      JSON.stringify({
        event: "result",
        result: {
          conversation_id: "conv-multi",
          status: "SUCCESS",
          response: "Turn 2 response",
          duration_seconds: 5.0,
        },
      })
    );
    expect(proc.isRunning()).toBe(false);
    expect(proc.getTerminalStatus()).toBe("completed");
    expect(proc.getConversationId()).toBe("conv-multi");
  });

  it("handles process abnormal exit and safely restarts on subsequent turn", async () => {
    const proc = new AntigravityProcess("/tmp/workspace");
    proc.setConversationId("conv-restart");

    // Simulate child process that exited with error
    const spawnSpy = vi.spyOn(proc as any, "spawnProcess").mockImplementation(async () => {});

    // First turn with dead child triggers spawnProcess
    (proc as any).child = null;
    await proc.sendInput("Retry after crash");

    expect(spawnSpy).toHaveBeenCalledWith("Retry after crash");
    expect(proc.getConversationId()).toBe("conv-restart");
  });

  it("handles split JSON lines correctly across chunks", () => {
    const proc = new AntigravityProcess("/tmp/workspace");
    const messages: ServerMessage[] = [];
    proc.on("message", (msg) => messages.push(msg));

    const line = JSON.stringify({
      event: "step_update",
      step_update: {
        conversation_id: "conv-split",
        step_type: "agent_response",
        text_delta: "streaming token",
      },
    });

    const half1 = line.slice(0, 20);
    const half2 = line.slice(20);

    proc.processStreamLine(half1); // Incomplete - should not throw or emit
    expect(messages.length).toBe(0);

    proc.processStreamLine(half1 + half2); // Complete
    expect(messages.length).toBe(1);
    expect(messages[0].type).toBe("assistant");
  });

  it("tolerates malformed JSON safely without throwing", () => {
    const proc = new AntigravityProcess("/tmp/workspace");
    expect(() => {
      proc.processStreamLine("NOT_JSON_DATA_CORRUPTED");
      proc.processStreamLine("{\"broken\": ");
    }).not.toThrow();
  });

  it("processes structured tool calls and creates tool_use assistant messages", () => {
    const proc = new AntigravityProcess("/tmp/workspace");
    const messages: ServerMessage[] = [];
    proc.on("message", (msg) => messages.push(msg));

    proc.processStreamLine(
      JSON.stringify({
        event: "step_update",
        step_update: {
          conversation_id: "conv-tool",
          step_type: "tool",
          tool_name: "write_to_file",
          tool_info: {
            parameters: {
              TargetFile: "test.txt",
            },
          },
        },
      })
    );

    expect(messages.length).toBe(1);
    expect(messages[0].type).toBe("assistant");
    const assistantMsg = messages[0].message;
    expect(assistantMsg.content[0].type).toBe("tool_use");
    expect((assistantMsg.content[0] as any).name).toBe("write_to_file");
  });

  it("processes SUCCESS result and updates terminal status to completed", () => {
    const proc = new AntigravityProcess("/tmp/workspace");
    const messages: ServerMessage[] = [];
    proc.on("message", (msg) => messages.push(msg));

    proc.processStreamLine(
      JSON.stringify({
        event: "result",
        result: {
          conversation_id: "conv-res",
          status: "SUCCESS",
          response: "Final plan response content",
          duration_seconds: 5.2,
          num_turns: 1,
        },
      })
    );

    expect(proc.getTerminalStatus()).toBe("completed");
    expect(messages.length).toBe(2); // 1 assistant text message + 1 result message
    expect(messages[0].type).toBe("assistant");
    expect(messages[1].type).toBe("result");
    expect((messages[1] as any).subtype).toBe("success");
    expect((messages[1] as any).result).toBe("Final plan response content");
  });

  it("handles canceled / interrupted result correctly", () => {
    const proc = new AntigravityProcess("/tmp/workspace");
    const messages: ServerMessage[] = [];
    proc.on("message", (msg) => messages.push(msg));

    proc.processStreamLine(
      JSON.stringify({
        event: "result",
        result: {
          conversation_id: "conv-int",
          status: "ERROR",
          error: "context canceled",
          duration_seconds: 1.0,
          num_turns: 0,
        },
      })
    );

    expect(proc.getTerminalStatus()).toBe("interrupted");
    expect(messages.length).toBe(1);
    expect(messages[0].type).toBe("result");
    expect((messages[0] as any).subtype).toBe("interrupted");
  });

  it("handles explicit interrupt via SIGINT / SIGTERM", () => {
    const proc = new AntigravityProcess("/tmp/workspace");
    // No active child: returns false and does not change status
    const didInterruptNoChild = proc.interrupt();
    expect(didInterruptNoChild).toBe(false);
    expect(proc.getTerminalStatus()).toBe("queued");

    // With active child
    (proc as any).child = {
      killed: false,
      kill: (sig: string) => {
        expect(sig).toBe("SIGINT");
        return true;
      },
    };
    (proc as any).internalStatus = "running";
    const didInterruptActive = proc.interrupt();
    expect(didInterruptActive).toBe(true);
    expect(proc.getTerminalStatus()).toBe("interrupting");
  });

  it("workspace isolation and conversation persistence", () => {
    const procA = new AntigravityProcess("/tmp/project-a");
    const procB = new AntigravityProcess("/tmp/project-b");

    procA.setConversationId("conv-a");
    procB.setConversationId("conv-b");

    expect(procA.getConversationId()).toBe("conv-a");
    expect(procB.getConversationId()).toBe("conv-b");
    expect(procA.getConversationId()).not.toBe(procB.getConversationId());
  });
});
