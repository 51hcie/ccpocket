import { readFile, writeFile, mkdir, readdir, realpath, stat } from "node:fs/promises";
import { join, dirname, resolve } from "node:path";
import { homedir } from "node:os";
import { normalizeWorktreePath, getAllRecentSessions } from "./sessions-index.js";

const DEFAULT_HISTORY_FILE = join(homedir(), ".ccpocket", "project-history.json");
const MAX_EXPLICIT_PROJECTS = 20;
const MAX_DISCOVERED_PROJECTS = 200;
const MAX_SCAN_DEPTH = 3;

/** Minimum path depth to be considered a valid project path (e.g. /Users/name/project = 3). */
const MIN_PATH_SEGMENTS = 3;

export function isValidProjectPath(path: string): boolean {
  if (!path.startsWith("/")) return false;
  const segments = path.split("/").filter(Boolean);
  return segments.length >= MIN_PATH_SEGMENTS;
}

export const PROJECT_MARKERS = [
  ".git",
  "pubspec.yaml",
  "package.json",
  "pyproject.toml",
  "Cargo.toml",
  "go.mod",
  ".codex",
  "pom.xml",
  "build.gradle",
  "build.gradle.kts",
  "CMakeLists.txt",
  "Makefile",
  "requirements.txt",
];

export const IGNORED_DIR_NAMES = new Set([
  "node_modules",
  "build",
  "dist",
  "out",
  "target",
  "vendor",
  "pods",
  "deriveddata",
  ".dart_tool",
  "bin",
  "obj",
  "venv",
  ".venv",
  "env",
  "__pycache__",
  "library",
  "applications",
  "system",
  "private",
  "tmp",
  "var",
  ".cache",
  ".npm",
  ".cargo",
  ".rustup",
  ".gradle",
  ".idea",
  ".vscode",
  ".git",
  ".ccpocket",
  ".antigravity",
  ".trash",
]);

export async function isProjectDirectory(dirPath: string): Promise<boolean> {
  try {
    const entries = await readdir(dirPath, { withFileTypes: true });
    for (const entry of entries) {
      if (PROJECT_MARKERS.includes(entry.name)) {
        return true;
      }
    }
  } catch {
    return false;
  }
  return false;
}

export async function discoverProjectsUnderRoots(
  roots: string[],
  maxDepth = MAX_SCAN_DEPTH,
  maxCount = MAX_DISCOVERED_PROJECTS,
): Promise<string[]> {
  const discovered: string[] = [];
  const visitedRealpaths = new Set<string>();

  for (const root of roots) {
    if (!root || typeof root !== "string") continue;
    const resolvedRoot = resolve(root.trim());
    if (discovered.length >= maxCount) break;

    try {
      const rootStat = await stat(resolvedRoot);
      if (!rootStat.isDirectory()) continue;
      const realRoot = await realpath(resolvedRoot);
      if (visitedRealpaths.has(realRoot)) continue;
      visitedRealpaths.add(realRoot);

      if (await isProjectDirectory(resolvedRoot)) {
        const norm = normalizeWorktreePath(resolvedRoot);
        if (isValidProjectPath(norm) && !discovered.includes(norm)) {
          discovered.push(norm);
        }
      }

      await scanDirectory(resolvedRoot, 0);
    } catch {
      // Unreadable or nonexistent root
      continue;
    }
  }

  async function scanDirectory(currentDir: string, depth: number): Promise<void> {
    if (depth >= maxDepth || discovered.length >= maxCount) return;

    let dirents;
    try {
      dirents = await readdir(currentDir, { withFileTypes: true });
    } catch {
      return;
    }

    for (const dirent of dirents) {
      if (discovered.length >= maxCount) break;
      if (!dirent.isDirectory() && !dirent.isSymbolicLink()) continue;

      const name = dirent.name;
      if (name.startsWith(".") || IGNORED_DIR_NAMES.has(name.toLowerCase())) {
        continue;
      }

      const fullPath = join(currentDir, name);
      try {
        const dirStat = await stat(fullPath);
        if (!dirStat.isDirectory()) continue;

        const real = await realpath(fullPath);
        if (visitedRealpaths.has(real)) continue;
        visitedRealpaths.add(real);

        if (await isProjectDirectory(fullPath)) {
          const norm = normalizeWorktreePath(fullPath);
          if (isValidProjectPath(norm) && !discovered.includes(norm)) {
            discovered.push(norm);
          }
          continue;
        }

        if (depth + 1 < maxDepth) {
          await scanDirectory(fullPath, depth + 1);
        }
      } catch {
        continue;
      }
    }
  }

  return discovered;
}

export interface ProjectHistoryOptions {
  filePath?: string;
  projectRoots?: string[] | string;
  maxExplicitProjects?: number;
  maxDiscoveredProjects?: number;
  maxDepth?: number;
  sessionLoader?: () => Promise<string[]>;
}

export class ProjectHistory {
  private explicitProjects: string[] = [];
  private sessionProjects: string[] = [];
  private discoveredProjects: string[] = [];
  private allProjects: string[] = [];
  private readonly removedProjects: Set<string> = new Set();
  private readonly filePath: string;
  private readonly projectRoots: string[];
  private readonly maxExplicit: number;
  private readonly maxDiscovered: number;
  private readonly maxDepth: number;
  private readonly sessionLoader?: () => Promise<string[]>;

  constructor(options?: string | ProjectHistoryOptions) {
    if (typeof options === "string") {
      this.filePath = options;
      this.projectRoots = [];
      this.maxExplicit = MAX_EXPLICIT_PROJECTS;
      this.maxDiscovered = MAX_DISCOVERED_PROJECTS;
      this.maxDepth = MAX_SCAN_DEPTH;
      this.sessionLoader = undefined;
    } else {
      this.filePath = options?.filePath ?? DEFAULT_HISTORY_FILE;
      this.projectRoots = this.parseRoots(options?.projectRoots ?? process.env.BRIDGE_PROJECT_ROOTS);
      this.maxExplicit = options?.maxExplicitProjects ?? MAX_EXPLICIT_PROJECTS;
      this.maxDiscovered = options?.maxDiscoveredProjects ?? MAX_DISCOVERED_PROJECTS;
      this.maxDepth = options?.maxDepth ?? MAX_SCAN_DEPTH;
      this.sessionLoader = options?.sessionLoader !== undefined
        ? options.sessionLoader
        : (options === undefined ? () => this.loadDefaultSessionPaths() : undefined);
    }
  }

  private parseRoots(roots?: string[] | string): string[] {
    if (!roots) return [];
    if (Array.isArray(roots)) {
      return roots.map((r) => r.trim()).filter(Boolean);
    }
    return roots.split(",").map((r) => r.trim()).filter(Boolean);
  }

  async init(): Promise<void> {
    await mkdir(dirname(this.filePath), { recursive: true });
    try {
      const data = await readFile(this.filePath, "utf-8");
      const parsed = JSON.parse(data);
      if (Array.isArray(parsed)) {
        const raw = parsed.filter((p): p is string => typeof p === "string");
        const seen = new Set<string>();
        this.explicitProjects = raw
          .map(normalizeWorktreePath)
          .filter(isValidProjectPath)
          .filter((p) => (seen.has(p) ? false : (seen.add(p), true)));
        if (this.explicitProjects.length < raw.length) {
          this.saveIndex().catch(() => {});
        }
      }
    } catch {
      this.explicitProjects = [];
    }
    await this.refresh();
  }

  async refresh(): Promise<string[]> {
    if (this.sessionLoader) {
      try {
        const sessionPaths = await this.sessionLoader();
        this.sessionProjects = sessionPaths
          .map(normalizeWorktreePath)
          .filter(isValidProjectPath);
      } catch {
        this.sessionProjects = [];
      }
    }

    if (this.projectRoots.length > 0) {
      try {
        const discovered = await discoverProjectsUnderRoots(
          this.projectRoots,
          this.maxDepth,
          this.maxDiscovered,
        );
        this.discoveredProjects = discovered
          .map(normalizeWorktreePath)
          .filter(isValidProjectPath);
      } catch {
        this.discoveredProjects = [];
      }
    }

    this.rebuildAllProjects();
    return [...this.allProjects];
  }

  private rebuildAllProjects(): void {
    const seen = new Set<string>();
    const combined: string[] = [];

    // 1. Explicit history (MRU order)
    for (const p of this.explicitProjects) {
      if (!this.removedProjects.has(p) && !seen.has(p) && isValidProjectPath(p)) {
        seen.add(p);
        combined.push(p);
      }
    }

    // 2. Session projects
    for (const p of this.sessionProjects) {
      if (!this.removedProjects.has(p) && !seen.has(p) && isValidProjectPath(p)) {
        seen.add(p);
        combined.push(p);
      }
    }

    // 3. Discovered projects
    for (const p of this.discoveredProjects) {
      if (!this.removedProjects.has(p) && !seen.has(p) && isValidProjectPath(p)) {
        seen.add(p);
        combined.push(p);
      }
    }

    this.allProjects = combined;
  }

  private async loadDefaultSessionPaths(): Promise<string[]> {
    const paths: string[] = [];
    try {
      const result = await getAllRecentSessions({ limit: 100 });
      for (const s of result.sessions) {
        if (s.projectPath) paths.push(s.projectPath);
        if (s.resumeCwd) paths.push(s.resumeCwd);
      }
    } catch {}
    return paths;
  }

  addProject(path: string): void {
    const normalized = normalizeWorktreePath(path);
    if (!isValidProjectPath(normalized)) return;
    this.removedProjects.delete(normalized);

    this.explicitProjects = this.explicitProjects.filter((p) => p !== normalized);
    this.explicitProjects.unshift(normalized);
    if (this.explicitProjects.length > this.maxExplicit) {
      this.explicitProjects = this.explicitProjects.slice(0, this.maxExplicit);
    }

    this.rebuildAllProjects();

    this.saveIndex().catch((err) => {
      console.error("[project-history] Failed to save:", err);
    });
  }

  getProjects(): string[] {
    return [...this.allProjects];
  }

  getExplicitProjects(): string[] {
    return [...this.explicitProjects];
  }

  removeProject(path: string): void {
    const normalized = normalizeWorktreePath(path);
    this.removedProjects.add(path);
    this.removedProjects.add(normalized);
    this.explicitProjects = this.explicitProjects.filter((p) => p !== path && p !== normalized);
    this.sessionProjects = this.sessionProjects.filter((p) => p !== path && p !== normalized);
    this.discoveredProjects = this.discoveredProjects.filter((p) => p !== path && p !== normalized);
    this.rebuildAllProjects();
    this.saveIndex().catch((err) => {
      console.error("[project-history] Failed to save:", err);
    });
  }

  private async saveIndex(): Promise<void> {
    await writeFile(this.filePath, JSON.stringify(this.explicitProjects, null, 2), "utf-8");
  }
}
