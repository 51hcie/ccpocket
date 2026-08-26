import {
  existsSync,
  lstatSync,
  realpathSync,
  readlinkSync,
  symlinkSync,
  unlinkSync,
  accessSync,
  constants as fsConstants,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { homedir } from "node:os";
import { execSync } from "node:child_process";

export interface CodexCodeModeStatus {
  available: boolean;
  codexPath?: string;
  hostPath?: string;
  repaired?: boolean;
  downgraded?: boolean;
  error?: string;
}

/**
 * Safely resolves realpath if the file exists.
 */
function safeRealpath(p: string): string {
  try {
    return realpathSync(p);
  } catch {
    return p;
  }
}

/**
 * Returns candidate directories where codex symlinks or tools might reside.
 */
function getCandidateToolDirs(customHome?: string): string[] {
  const home = customHome ?? homedir();
  const dirs: string[] = [];

  const macremoteTools = join(home, "Windows_Projects", "Macremote", "tools", "bin");
  if (existsSync(macremoteTools)) dirs.push(macremoteTools);

  const spikeCandidatesTools = join(home, "Windows_Projects", "Macremote_spike", "tools", "bin");
  if (existsSync(spikeCandidatesTools)) dirs.push(spikeCandidatesTools);

  const spikeTools = resolve(process.cwd(), "../../tools/bin");
  if (existsSync(spikeTools)) dirs.push(spikeTools);

  const localBin = join(home, ".local", "bin");
  if (existsSync(localBin)) dirs.push(localBin);

  return dirs;
}

/**
 * Resolve the path to the codex executable.
 */
export function resolveCodexExecutable(customPath?: string, customHome?: string): string | null {
  if (customPath && existsSync(customPath)) {
    return customPath;
  }
  if (process.env.CODEX_PATH && existsSync(process.env.CODEX_PATH)) {
    return process.env.CODEX_PATH;
  }

  const home = customHome ?? homedir();
  // 1. Check primary plugin installation first
  const pluginCodex = join(home, ".codex", "plugins", ".plugin-appserver", "codex");
  if (existsSync(pluginCodex)) {
    return pluginCodex;
  }

  // 2. Check candidate tools directories
  for (const dir of getCandidateToolDirs(home)) {
    const candidate = join(dir, process.platform === "win32" ? "codex.exe" : "codex");
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  // 3. Check `which codex` (only in default home)
  if (!customHome) {
    try {
      const whichOut = execSync("which codex", {
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "pipe"],
      }).trim().split("\n")[0];
      if (whichOut && existsSync(whichOut)) {
        return whichOut;
      }
    } catch {
      // Ignore which failure
    }
  }

  // 4. Check fallback locations
  const fallbacks = [
    "/usr/local/bin/codex",
    "/Applications/ChatGPT.app/Contents/Resources/codex",
  ];

  for (const candidate of fallbacks) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  return null;
}

/**
 * Find the real codex-code-mode-host binary from codex realpath or plugin dirs.
 */
export function findRealCodexHost(codexBinPath: string, customHome?: string): string | null {
  const exeName = process.platform === "win32" ? "codex-code-mode-host.exe" : "codex-code-mode-host";
  const home = customHome ?? homedir();

  // 1. Try relative to realpath of codex
  try {
    if (existsSync(codexBinPath)) {
      const realCodexPath = realpathSync(codexBinPath);
      const realDir = dirname(realCodexPath);
      const candidate1 = join(realDir, exeName);
      if (existsSync(candidate1)) {
        try {
          accessSync(candidate1, fsConstants.X_OK);
          return candidate1;
        } catch {
          return candidate1;
        }
      }
    }
  } catch {
    // Ignore realpath error
  }

  // 2. Try standard plugin directory in user home
  const pluginDirHost = join(home, ".codex", "plugins", ".plugin-appserver", exeName);
  if (existsSync(pluginDirHost)) {
    return pluginDirHost;
  }

  // 3. Try which codex-code-mode-host (only if not customized home)
  if (!customHome) {
    try {
      const whichHost = execSync(`which ${exeName}`, {
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "pipe"],
      }).trim().split("\n")[0];
      if (whichHost && existsSync(whichHost)) {
        return whichHost;
      }
    } catch {
      // Ignore which failure
    }
  }

  // 4. Try macOS app bundle (only if not customized home)
  if (!customHome && process.platform === "darwin") {
    const appBundleHost = `/Applications/ChatGPT.app/Contents/Resources/${exeName}`;
    if (existsSync(appBundleHost)) {
      return appBundleHost;
    }
  }

  return null;
}

/**
 * Checks if a directory contains a valid, working host binary or valid symlink.
 */
function isHostValidInDir(dirHost: string, realHost: string): boolean {
  if (!existsSync(dirHost)) {
    return false;
  }
  try {
    const stat = lstatSync(dirHost);
    if (stat.isSymbolicLink()) {
      const target = readlinkSync(dirHost);
      const resolvedTarget = resolve(dirname(dirHost), target);
      return existsSync(resolvedTarget) && safeRealpath(resolvedTarget) === safeRealpath(realHost);
    }
    return safeRealpath(dirHost) === safeRealpath(realHost);
  } catch {
    return false;
  }
}

/**
 * Ensures codex-code-mode-host is discovered, symlinks are healthy and created/repaired,
 * or explicitly reports downgrade when missing.
 */
export function ensureCodexCodeModeHost(options?: {
  codexPath?: string;
  codexBinDir?: string;
  toolsBinDirs?: string[];
  autoRepair?: boolean;
  homeDir?: string;
}): CodexCodeModeStatus {
  const autoRepair = options?.autoRepair !== false;
  const homeDir = options?.homeDir;
  const codexPath = options?.codexPath ?? resolveCodexExecutable(undefined, homeDir);

  if (!codexPath) {
    return {
      available: false,
      downgraded: true,
      error: "Codex binary not found on system",
    };
  }

  const defaultRealHost = findRealCodexHost(codexPath, homeDir);
  if (!defaultRealHost) {
    return {
      available: false,
      codexPath,
      downgraded: true,
      error: "codex-code-mode-host binary not found in Codex installation or plugin directories",
    };
  }

  let repaired = false;
  const exeName = process.platform === "win32" ? "codex-code-mode-host.exe" : "codex-code-mode-host";
  const criticalDir = dirname(codexPath);

  // 1. Process and verify the critical directory first
  if (existsSync(criticalDir)) {
    const criticalCodex = join(criticalDir, process.platform === "win32" ? "codex.exe" : "codex");
    const criticalHost = join(criticalDir, exeName);
    const criticalTargetRealHost = (existsSync(criticalCodex) ? findRealCodexHost(criticalCodex, homeDir) : null) ?? defaultRealHost;

    if (!isHostValidInDir(criticalHost, criticalTargetRealHost)) {
      if (autoRepair) {
        try {
          try {
            unlinkSync(criticalHost);
          } catch {
            // Ignore if file didn't exist
          }
          symlinkSync(criticalTargetRealHost, criticalHost);
          repaired = true;
        } catch (linkErr) {
          return {
            available: false,
            codexPath,
            hostPath: defaultRealHost,
            repaired: false,
            downgraded: true,
            error: `Failed to link codex-code-mode-host in critical directory ${criticalDir}: ${
              linkErr instanceof Error ? linkErr.message : String(linkErr)
            }`,
          };
        }
      }

      // Re-verify after repair attempt
      if (!isHostValidInDir(criticalHost, criticalTargetRealHost)) {
        return {
          available: false,
          codexPath,
          hostPath: defaultRealHost,
          repaired: false,
          downgraded: true,
          error: `Critical directory ${criticalDir} does not have a working codex-code-mode-host link to ${criticalTargetRealHost}`,
        };
      }
    }
  }

  // 2. Process non-critical candidate tool directories
  const candidateDirs = new Set<string>();
  if (options?.codexBinDir && options.codexBinDir !== criticalDir) {
    candidateDirs.add(options.codexBinDir);
  }
  if (options?.toolsBinDirs) {
    for (const d of options.toolsBinDirs) {
      if (d !== criticalDir) candidateDirs.add(d);
    }
  } else {
    for (const d of getCandidateToolDirs(homeDir)) {
      if (d !== criticalDir) candidateDirs.add(d);
    }
  }

  for (const dir of candidateDirs) {
    if (!existsSync(dir)) continue;

    const dirCodex = join(dir, process.platform === "win32" ? "codex.exe" : "codex");
    const dirHost = join(dir, exeName);

    if (existsSync(dirCodex)) {
      const targetRealHost = findRealCodexHost(dirCodex, homeDir) ?? defaultRealHost;
      if (!isHostValidInDir(dirHost, targetRealHost)) {
        if (autoRepair) {
          try {
            try {
              unlinkSync(dirHost);
            } catch {}
            symlinkSync(targetRealHost, dirHost);
            repaired = true;
          } catch (nonCriticalErr) {
            console.warn(
              `[codex-host-helper] Non-critical directory symlink failed for ${dir}:`,
              nonCriticalErr,
            );
          }
        }
      }
    }
  }

  return {
    available: true,
    codexPath,
    hostPath: defaultRealHost,
    repaired,
    downgraded: false,
  };
}
