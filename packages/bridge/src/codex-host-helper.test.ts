import { describe, it, expect, beforeEach, afterEach } from "vitest";
import {
  mkdirSync,
  writeFileSync,
  symlinkSync,
  unlinkSync,
  rmSync,
  existsSync,
  readlinkSync,
  realpathSync,
  chmodSync,
} from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { randomUUID } from "node:crypto";
import {
  resolveCodexExecutable,
  findRealCodexHost,
  ensureCodexCodeModeHost,
} from "./codex-host-helper.js";
import { CodexProcess } from "./codex-process.js";

describe("codex-host-helper", () => {
  let testRoot: string;
  let fakeHome: string;
  let pluginDir: string;
  let toolsBinDir: string;
  let realCodexBin: string;
  let realHostBin: string;
  let toolsCodexSymlink: string;
  let toolsHostSymlink: string;

  beforeEach(() => {
    testRoot = join(tmpdir(), `codex-host-test-${randomUUID()}`);
    fakeHome = join(testRoot, "home");
    pluginDir = join(fakeHome, ".codex", "plugins", ".plugin-appserver");
    toolsBinDir = join(fakeHome, "Windows_Projects", "Macremote", "tools", "bin");

    mkdirSync(pluginDir, { recursive: true });
    mkdirSync(toolsBinDir, { recursive: true });

    realCodexBin = join(pluginDir, "codex");
    realHostBin = join(pluginDir, "codex-code-mode-host");
    toolsCodexSymlink = join(toolsBinDir, "codex");
    toolsHostSymlink = join(toolsBinDir, "codex-code-mode-host");

    writeFileSync(realCodexBin, "#!/bin/sh\necho codex\n", { mode: 0o755 });
    writeFileSync(realHostBin, "#!/bin/sh\necho host\n", { mode: 0o755 });
    symlinkSync(realCodexBin, toolsCodexSymlink);
  });

  afterEach(() => {
    try {
      chmodSync(toolsBinDir, 0o755);
    } catch {}
    try {
      rmSync(testRoot, { recursive: true, force: true });
    } catch {}
  });

  it("Case 1: existing/valid - discovers real host and creates/verifies symlink in tools/bin", () => {
    const status = ensureCodexCodeModeHost({
      codexPath: toolsCodexSymlink,
      codexBinDir: toolsBinDir,
      toolsBinDirs: [toolsBinDir],
      autoRepair: true,
      homeDir: fakeHome,
    });

    expect(status.available).toBe(true);
    expect(status.downgraded).toBe(false);
    expect(existsSync(toolsHostSymlink)).toBe(true);

    const target = readlinkSync(toolsHostSymlink);
    expect(realpathSync(target)).toBe(realpathSync(realHostBin));
  });

  it("Case 2: stale symlink - repairs broken/outdated symlink to the real host binary", () => {
    // Create a stale symlink pointing to a non-existent file
    const fakeStaleTarget = join(testRoot, "nonexistent-old-host");
    symlinkSync(fakeStaleTarget, toolsHostSymlink);
    expect(existsSync(toolsHostSymlink)).toBe(false); // Broken symlink

    const status = ensureCodexCodeModeHost({
      codexPath: toolsCodexSymlink,
      codexBinDir: toolsBinDir,
      toolsBinDirs: [toolsBinDir],
      autoRepair: true,
      homeDir: fakeHome,
    });

    expect(status.available).toBe(true);
    expect(status.repaired).toBe(true);
    expect(existsSync(toolsHostSymlink)).toBe(true);

    const target = readlinkSync(toolsHostSymlink);
    expect(realpathSync(target)).toBe(realpathSync(realHostBin));
  });

  it("Case 3: missing source - unconditionally reports available=false and downgraded=true when source host is missing", () => {
    const isolatedHome = join(testRoot, "isolated-home");
    const isolatedDir = join(isolatedHome, "tools", "bin");
    mkdirSync(isolatedDir, { recursive: true });
    const isolatedCodex = join(isolatedDir, "codex");
    writeFileSync(isolatedCodex, "#!/bin/sh\n", { mode: 0o755 });

    const status = ensureCodexCodeModeHost({
      codexPath: isolatedCodex,
      codexBinDir: isolatedDir,
      toolsBinDirs: [isolatedDir],
      autoRepair: true,
      homeDir: isolatedHome,
    });

    expect(status.available).toBe(false);
    expect(status.downgraded).toBe(true);
    expect(status.error).toContain("codex-code-mode-host binary not found");
  });

  it("Case 4: critical directory symlink creation failure - unconditionally reports available=false and downgraded=true", () => {
    // Make critical directory read-only so symlink creation fails
    chmodSync(toolsBinDir, 0o555);

    const status = ensureCodexCodeModeHost({
      codexPath: toolsCodexSymlink,
      codexBinDir: toolsBinDir,
      toolsBinDirs: [toolsBinDir],
      autoRepair: true,
      homeDir: fakeHome,
    });

    expect(status.available).toBe(false);
    expect(status.downgraded).toBe(true);
    expect(status.repaired).toBe(false);
    expect(status.error).toContain("Failed to link codex-code-mode-host in critical directory");
  });

  it("findRealCodexHost locates host in dirname(realpath) and returns null when missing", () => {
    expect(realpathSync(findRealCodexHost(toolsCodexSymlink, fakeHome)!)).toBe(realpathSync(realHostBin));

    // When host binary is missing in isolated home
    const isolatedHome = join(testRoot, "isolated-home-2");
    const isolatedDir = join(isolatedHome, "tools", "bin");
    mkdirSync(isolatedDir, { recursive: true });
    const isolatedCodex = join(isolatedDir, "codex");
    writeFileSync(isolatedCodex, "#!/bin/sh\n", { mode: 0o755 });

    const missing = findRealCodexHost(isolatedCodex, isolatedHome);
    expect(missing).toBeNull();
  });

  it("conservative semantics: real CodexProcess instance defaults codeModeAvailable=false before start and true after launch", async () => {
    const cp = new CodexProcess({
      onMessage: () => {},
      onError: () => {},
      onStatusChange: () => {},
    });

    expect(cp.codeModeStatus).toBeUndefined();
    expect(cp.codeModeAvailable).toBe(false);

    // Start with test plugin dir
    await cp.start(pluginDir);
    expect(cp.codeModeStatus).toBeDefined();
    expect(cp.codeModeAvailable).toBe(true);
    await cp.stop();
  });
});
