import { WebSocket } from "ws";
import { spawn, type ChildProcess } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { homedir, tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = join(__filename, "..");

const NODE_PATH = process.env.NODE_PATH || process.execPath;
const CLI_PATH = process.env.BRIDGE_CLI_PATH || resolve(__dirname, "../dist/cli.js");
const PORT = Number(process.env.TEST_BRIDGE_PORT || "8899");
const WS_URL = `ws://127.0.0.1:${PORT}`;

// Dynamically setup dual test workspace fixtures
function ensureFixtureDirs(): { dualAPath: string; dualBPath: string } {
  const baseDir = process.env.TEST_FIXTURES_DIR || resolve(__dirname, "../../../fixtures");
  const dualAPath = join(baseDir, "dual-a");
  const dualBPath = join(baseDir, "dual-b");

  if (!existsSync(dualAPath)) {
    mkdirSync(dualAPath, { recursive: true });
    writeFileSync(join(dualAPath, "README.md"), "# Dual A Codex\n");
  }
  if (!existsSync(dualBPath)) {
    mkdirSync(dualBPath, { recursive: true });
    writeFileSync(join(dualBPath, "README.md"), "# Dual B Antigravity\n");
  }

  return { dualAPath, dualBPath };
}

interface Evidence {
  name: string;
  passed: boolean;
  details: any;
}

const evidences: Evidence[] = [];
const activeProcesses: ChildProcess[] = [];

function cleanupAllProcesses() {
  for (const child of activeProcesses) {
    if (child && !child.killed) {
      try {
        child.kill("SIGTERM");
      } catch {
        // ignore
      }
    }
  }
}

process.on("exit", cleanupAllProcesses);
process.on("SIGINT", () => {
  cleanupAllProcesses();
  process.exit(1);
});
process.on("SIGTERM", () => {
  cleanupAllProcesses();
  process.exit(1);
});

async function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function createBridgeProcess(port: number): ChildProcess {
  const env: NodeJS.ProcessEnv = {
    ...process.env,
  };

  // If local clash/mihomo proxy is available in environment or standard port
  if (!env.https_proxy && !env.HTTPS_PROXY) {
    env.https_proxy = "http://127.0.0.1:7897";
    env.http_proxy = "http://127.0.0.1:7897";
    env.all_proxy = "socks5://127.0.0.1:7897";
  }

  // Ensure PATH contains tools if available
  const extraPaths = [
    resolve(__dirname, "../../../../tools/bin"),
    resolve(homedir(), ".cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin"),
    resolve(homedir(), ".local/bin"),
  ].filter((p) => existsSync(p));

  if (extraPaths.length > 0) {
    env.PATH = `${extraPaths.join(":")}:${env.PATH || ""}`;
  }

  // Ensure NO BRIDGE_FORCE_PROVIDER is set!
  delete (env as any).BRIDGE_FORCE_PROVIDER;

  const child = spawn(NODE_PATH, [CLI_PATH, "--port", String(port)], {
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });

  activeProcesses.push(child);

  child.stdout?.on("data", (d) => {
    console.log(`[Bridge stdout] ${d.toString().trim()}`);
  });
  child.stderr?.on("data", (d) => {
    console.error(`[Bridge stderr] ${d.toString().trim()}`);
  });

  return child;
}

async function waitForServer(port: number, timeoutMs = 15000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const ws = new WebSocket(`ws://127.0.0.1:${port}`);
      await new Promise<void>((resolve, reject) => {
        ws.once("open", () => {
          ws.close();
          resolve();
        });
        ws.once("error", reject);
      });
      return;
    } catch {
      await sleep(200);
    }
  }
  throw new Error(`Server failed to start on port ${port} within ${timeoutMs}ms`);
}

class TestClient {
  private ws: WebSocket | null = null;
  public messages: any[] = [];

  async connect(url: string): Promise<void> {
    this.ws = new WebSocket(url);
    await new Promise<void>((resolve, reject) => {
      this.ws!.once("open", resolve);
      this.ws!.once("error", reject);
    });

    this.ws.on("message", (data) => {
      try {
        const parsed = JSON.parse(data.toString());
        console.log(`[Client RX] ${parsed.type}/${parsed.subtype || ""}:`, JSON.stringify(parsed).slice(0, 140));
        this.messages.push(parsed);
      } catch {
        // ignore
      }
    });
  }

  send(msg: any) {
    this.ws!.send(JSON.stringify(msg));
  }

  async waitForMessage(predicate: (msg: any) => boolean, timeoutMs = 60000): Promise<any> {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      for (const msg of this.messages) {
        if (predicate(msg)) {
          return msg;
        }
      }
      await sleep(100);
    }
    throw new Error(`Timeout waiting for message matching predicate after ${timeoutMs}ms`);
  }

  close() {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }
}

async function runAllValidations() {
  console.log("=== Starting Dual Engine Real Verification ===");

  const { dualAPath, dualBPath } = ensureFixtureDirs();
  console.log(`[Setup] Using dual-a: ${dualAPath}`);
  console.log(`[Setup] Using dual-b: ${dualBPath}`);

  let bridge = createBridgeProcess(PORT);
  await waitForServer(PORT);
  console.log(`[OK] Bridge started on port ${PORT} without provider hijacking`);

  let agySessionId = "";
  let agyConversationId = "";

  try {
    // -------------------------------------------------------------
    // Test A: Codex Baseline
    // -------------------------------------------------------------
    console.log("\n--- [Test A] Codex Baseline in project-a ---");
    {
      const client = new TestClient();
      await client.connect(WS_URL);

      client.send({
        type: "start",
        provider: "codex",
        projectPath: dualAPath,
      });

      const sessionCreated = await client.waitForMessage((m) => (m.type === "system" && m.subtype === "session_created") || m.type === "session_created");
      console.log(`[Test A] Codex session created: ${sessionCreated.sessionId}`);

      client.send({
        type: "input",
        sessionId: sessionCreated.sessionId,
        text: "Reply with exactly: CODEX_DUAL_PASS",
      });

      const result = await client.waitForMessage((m) => m.type === "result", 60000);
      console.log(`[Test A] Codex Result: ${result.result}`);

      const passed = result.result?.includes("CODEX_DUAL_PASS") && result.subtype === "success";
      evidences.push({
        name: "Test A: Codex Baseline (project-a)",
        passed,
        details: { result: result.result, subtype: result.subtype },
      });
      console.log(`[Test A] Status: ${passed ? "PASS" : "FAIL"}`);
      client.close();
    }

    // -------------------------------------------------------------
    // Test B: Antigravity New Task in Plan Mode
    // -------------------------------------------------------------
    console.log("\n--- [Test B] Antigravity New Task in project-b (Plan Mode) ---");
    {
      const client = new TestClient();
      await client.connect(WS_URL);

      client.send({
        type: "start",
        provider: "antigravity",
        mode: "plan",
        projectPath: dualBPath,
      });

      const sessionCreated = await client.waitForMessage((m) => (m.type === "system" && m.subtype === "session_created") || m.type === "session_created");
      agySessionId = sessionCreated.sessionId;
      console.log(`[Test B] Antigravity session created: bridgeSessionId=${agySessionId}`);

      client.send({
        type: "input",
        sessionId: agySessionId,
        text: "What is in README.md? Reply concisely in one sentence.",
      });

      const result = await client.waitForMessage((m) => m.type === "result", 60000);
      console.log(`[Test B] Antigravity Result received`);
      console.log(`[Test B] Content: ${result.result}`);

      // Check persistent store on disk
      const storeFile = join(homedir(), ".ccpocket", "antigravity-sessions", `${agySessionId}.json`);
      const storeExists = existsSync(storeFile);
      let storeRecord: any = null;
      if (storeExists) {
        storeRecord = JSON.parse(readFileSync(storeFile, "utf-8"));
      }
      agyConversationId = storeRecord?.antigravityConversationId;
      console.log(`[Test B] Extracted real antigravityConversationId: ${agyConversationId}`);

      const passed = storeExists && storeRecord?.provider === "antigravity" && storeRecord?.terminalStatus === "completed" && !!agyConversationId;
      evidences.push({
        name: "Test B: Antigravity New Task (Plan Mode)",
        passed,
        details: {
          bridgeSessionId: agySessionId,
          antigravityConversationId: agyConversationId,
          storeExists,
          storeRecord,
        },
      });
      console.log(`[Test B] Status: ${passed ? "PASS" : "FAIL"}`);
      client.close();
    }

    // -------------------------------------------------------------
    // Test C: Antigravity Follow-up in same session
    // -------------------------------------------------------------
    console.log("\n--- [Test C] Antigravity Follow-up in same session ---");
    {
      const client = new TestClient();
      await client.connect(WS_URL);

      // Send follow-up in existing session
      client.send({
        type: "input",
        sessionId: agySessionId,
        text: "Now reply with exactly: AGY_FOLLOWUP_PASS",
      });

      const result = await client.waitForMessage((m) => m.type === "result", 60000);
      const text = result.result || "";
      console.log(`[Test C] Follow-up Result: ${text}`);

      const storeFile = join(homedir(), ".ccpocket", "antigravity-sessions", `${agySessionId}.json`);
      const storeRecord = JSON.parse(readFileSync(storeFile, "utf-8"));

      const passed = text.includes("AGY_FOLLOWUP_PASS") && storeRecord.antigravityConversationId === agyConversationId && storeRecord.currentTurn >= 2;
      evidences.push({
        name: "Test C: Antigravity Follow-up in same conversation",
        passed,
        details: {
          sameConversationId: storeRecord.antigravityConversationId === agyConversationId,
          currentTurn: storeRecord.currentTurn,
          result: text,
        },
      });
      console.log(`[Test C] Status: ${passed ? "PASS" : "FAIL"}`);
      client.close();
    }

    // -------------------------------------------------------------
    // Test D: Antigravity Accept-Edits modifying files in project-b
    // -------------------------------------------------------------
    console.log("\n--- [Test D] Antigravity Accept-Edits File Modification ---");
    {
      const client = new TestClient();
      await client.connect(WS_URL);

      client.send({
        type: "start",
        provider: "antigravity",
        mode: "accept-edits",
        projectPath: dualBPath,
      });

      const sessionCreated = await client.waitForMessage((m) => (m.type === "system" && m.subtype === "session_created") || m.type === "session_created");
      const editSessionId = sessionCreated.sessionId;

      const editFilePath = join(dualBPath, "AGY_EDITED.txt");

      client.send({
        type: "input",
        sessionId: editSessionId,
        text: `Create a file named AGY_EDITED.txt with the content "DUAL_ENGINE_ACCEPT_EDITS_OK". Do not ask for confirmation.`,
      });

      const result = await client.waitForMessage((m) => m.type === "result", 60000);
      console.log(`[Test D] Accept-edits finished: ${result.result}`);

      await sleep(1000);
      const fileCreated = existsSync(editFilePath);
      const fileContent = fileCreated ? readFileSync(editFilePath, "utf-8") : "";

      const passed = fileCreated && fileContent.includes("DUAL_ENGINE_ACCEPT_EDITS_OK");
      evidences.push({
        name: "Test D: Antigravity Accept-Edits File Modification",
        passed,
        details: {
          fileCreated,
          fileContent,
          filePath: editFilePath,
        },
      });
      console.log(`[Test D] Status: ${passed ? "PASS" : "FAIL"}`);
      client.close();
    }

    // -------------------------------------------------------------
    // Test E: Antigravity Interrupt Flow
    // -------------------------------------------------------------
    console.log("\n--- [Test E] Antigravity Interrupt Flow ---");
    {
      const client = new TestClient();
      await client.connect(WS_URL);

      client.send({
        type: "start",
        provider: "antigravity",
        mode: "accept-edits",
        projectPath: dualBPath,
      });

      const sessionCreated = await client.waitForMessage((m) => (m.type === "system" && m.subtype === "session_created") || m.type === "session_created");
      const intSessionId = sessionCreated.sessionId;
      console.log(`[Test E] Started session for interrupt: ${intSessionId}`);

      client.send({
        type: "input",
        sessionId: intSessionId,
        text: "Write a detailed 3000-word essay about the history of computing with comprehensive details.",
      });

      // Wait briefly for process to start
      await sleep(1500);

      console.log(`[Test E] Sending interrupt...`);
      client.send({
        type: "interrupt",
        sessionId: intSessionId,
      });

      const result = await client.waitForMessage((m) => m.type === "result" && m.subtype === "interrupted", 30000);
      console.log(`[Test E] Interrupt result received:`, result);

      const storeFile = join(homedir(), ".ccpocket", "antigravity-sessions", `${intSessionId}.json`);
      const storeRecord = JSON.parse(readFileSync(storeFile, "utf-8"));

      const passed = result.subtype === "interrupted" && storeRecord.terminalStatus === "interrupted";
      evidences.push({
        name: "Test E: Antigravity Interrupt Flow",
        passed,
        details: {
          resultSubtype: result.subtype,
          persistedStatus: storeRecord.terminalStatus,
        },
      });
      console.log(`[Test E] Status: ${passed ? "PASS" : "FAIL"}`);
      client.close();
    }

    // -------------------------------------------------------------
    // Test F: Bridge Restart & Resume Antigravity Session
    // -------------------------------------------------------------
    console.log("\n--- [Test F] Bridge Restart & Resume Antigravity Session ---");
    {
      // Kill current bridge
      bridge.kill("SIGTERM");
      await sleep(1000);

      // Start new Bridge instance
      bridge = createBridgeProcess(PORT);
      await waitForServer(PORT);
      console.log(`[Test F] New Bridge instance started`);

      const client = new TestClient();
      await client.connect(WS_URL);

      // Query recent sessions
      client.send({
        type: "list_recent_sessions",
        provider: "antigravity",
      });

      const recentResp = await client.waitForMessage((m) => m.type === "recent_sessions");
      const foundSession = recentResp.sessions?.find((s: any) => s.sessionId === agySessionId || s.id === agySessionId);
      console.log(`[Test F] Found session in recent_sessions:`, !!foundSession, JSON.stringify(foundSession));

      // Resume session
      client.send({
        type: "resume_session",
        sessionId: agySessionId,
        projectPath: dualBPath,
        provider: "antigravity",
      });

      const resumeCreated = await client.waitForMessage((m) => (m.type === "system" && m.subtype === "session_created") || m.type === "session_created");
      const resumedSessionId = resumeCreated.sessionId;
      console.log(`[Test F] Resumed session created with id: ${resumedSessionId}`);

      // Send new turn on resumed session
      client.send({
        type: "input",
        sessionId: resumedSessionId,
        text: "Reply with exactly: RESUMED_AGY_PASS",
      });

      const result = await client.waitForMessage((m) => m.type === "result", 60000);
      const text = result.result || "";
      console.log(`[Test F] Resumed session result: ${text}`);

      const storeFile = join(homedir(), ".ccpocket", "antigravity-sessions", `${resumedSessionId}.json`);
      const storeRecord = existsSync(storeFile)
        ? JSON.parse(readFileSync(storeFile, "utf-8"))
        : JSON.parse(readFileSync(join(homedir(), ".ccpocket", "antigravity-sessions", `${agySessionId}.json`), "utf-8"));

      const passed = text.includes("RESUMED_AGY_PASS") && (storeRecord.antigravityConversationId === agyConversationId);
      evidences.push({
        name: "Test F: Bridge Restart & Resume Antigravity Session",
        passed,
        details: {
          foundInRecent: !!foundSession,
          resumedConversationId: storeRecord.antigravityConversationId,
          expectedConversationId: agyConversationId,
          result: text,
        },
      });
      console.log(`[Test F] Status: ${passed ? "PASS" : "FAIL"}`);
      client.close();
    }

    // -------------------------------------------------------------
    // Test G: Dual Engine Coexistence & Interleaving
    // -------------------------------------------------------------
    console.log("\n--- [Test G] Dual Engine Coexistence & Interleaving ---");
    {
      const clientCodex = new TestClient();
      await clientCodex.connect(WS_URL);

      // 1. Turn on Codex
      clientCodex.send({
        type: "start",
        provider: "codex",
        projectPath: dualAPath,
      });
      const cCreated = await clientCodex.waitForMessage((m) => (m.type === "system" && m.subtype === "session_created") || m.type === "session_created");
      clientCodex.send({
        type: "input",
        sessionId: cCreated.sessionId,
        text: "Reply with: DUAL_COEXIST_CODEX_OK",
      });
      const codexResult = await clientCodex.waitForMessage((m) => m.type === "result" && m.result?.includes("DUAL_COEXIST_CODEX_OK"), 45000);
      clientCodex.close();

      // 2. Turn on Antigravity
      const clientAgy = new TestClient();
      await clientAgy.connect(WS_URL);
      clientAgy.send({
        type: "start",
        provider: "antigravity",
        projectPath: dualBPath,
      });
      const aCreated = await clientAgy.waitForMessage((m) => (m.type === "system" && m.subtype === "session_created") || m.type === "session_created");
      clientAgy.send({
        type: "input",
        sessionId: aCreated.sessionId,
        text: "Reply with: DUAL_COEXIST_AGY_OK",
      });
      const agyResult = await clientAgy.waitForMessage((m) => m.type === "result" && m.result?.includes("DUAL_COEXIST_AGY_OK"), 60000);
      clientAgy.close();

      const passed = !!codexResult && !!agyResult;
      evidences.push({
        name: "Test G: Dual Engine Coexistence & Interleaving",
        passed,
        details: {
          codexResult: codexResult?.result,
          agyResult: agyResult?.result,
        },
      });
      console.log(`[Test G] Status: ${passed ? "PASS" : "FAIL"}`);
    }

  } finally {
    bridge.kill("SIGTERM");
    cleanupAllProcesses();
  }

  console.log("\n=== SUMMARY OF E2E DUAL ENGINE VALIDATIONS ===");
  let allPassed = true;
  for (const ev of evidences) {
    console.log(`- [${ev.passed ? "PASS" : "FAIL"}] ${ev.name}`);
    if (!ev.passed) allPassed = false;
  }
  console.log(`\nALL TESTS PASSED: ${allPassed}`);

  if (!allPassed) {
    process.exit(1);
  }
}

// Global safety timeout of 5 minutes
setTimeout(() => {
  console.error("FATAL: Overall test timeout exceeded (300s)");
  cleanupAllProcesses();
  process.exit(1);
}, 300000).unref();

runAllValidations().catch((err) => {
  console.error("FATAL ERROR IN VALIDATION:", err);
  cleanupAllProcesses();
  process.exit(1);
});
