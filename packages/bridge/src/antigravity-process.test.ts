import { describe, it, expect, vi } from "vitest";
import { AntigravityProcess } from "./antigravity-process.js";
import type { ServerMessage } from "./parser.js";

describe("AntigravityProcess Unit Tests", () => {
  it("discovers conversationId and emits system init event", () => {
    const proc = new AntigravityProcess("/tmp/workspace");
    const messages: ServerMessage[] = [];
    proc.on("message", (msg) => messages.push(msg));

    proc.processStreamLine(
      JSON.stringify({
        event: "init",
        conversation_id: "conv-12345",
        init: { model: "gemini-3.7-flash-high" },
      })
    );

    expect(proc.getConversationId()).toBe("conv-12345");
    expect(messages.length).toBe(1);
    expect(messages[0].type).toBe("system");
    expect(messages[0].sessionId).toBe("conv-12345");
    expect(messages[0].provider).toBe("antigravity");
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

  it("handles explicit interrupt via SIGTERM", () => {
    const proc = new AntigravityProcess("/tmp/workspace");
    // No active child: returns false and does not change status
    const didInterruptNoChild = proc.interrupt();
    expect(didInterruptNoChild).toBe(false);
    expect(proc.getTerminalStatus()).toBe("queued");

    // With active child
    (proc as any).child = {
      killed: false,
      kill: (sig: string) => {
        expect(sig).toBe("SIGTERM");
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
