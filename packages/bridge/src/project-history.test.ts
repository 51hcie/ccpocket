import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { rm, mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { randomUUID } from "node:crypto";
import { ProjectHistory } from "./project-history.js";

let tempDir: string;
let historyFile: string;

beforeEach(async () => {
  tempDir = join(tmpdir(), `ph-test-${randomUUID().slice(0, 8)}`);
  await mkdir(tempDir, { recursive: true });
  historyFile = join(tempDir, "project-history.json");
});

afterEach(async () => {
  await rm(tempDir, { recursive: true, force: true });
});

describe("ProjectHistory", () => {
  it("init creates directory and starts with empty projects", async () => {
    const ph = new ProjectHistory(historyFile);
    await ph.init();
    expect(ph.getProjects()).toEqual([]);
  });

  it("addProject adds a project to the front", async () => {
    const ph = new ProjectHistory(historyFile);
    await ph.init();
    ph.addProject("/Users/test/project-a");
    ph.addProject("/Users/test/project-b");
    expect(ph.getProjects()).toEqual(["/Users/test/project-b", "/Users/test/project-a"]);
  });

  it("addProject moves existing project to front", async () => {
    const ph = new ProjectHistory(historyFile);
    await ph.init();
    ph.addProject("/Users/test/project-a");
    ph.addProject("/Users/test/project-b");
    ph.addProject("/Users/test/project-a");
    expect(ph.getProjects()).toEqual(["/Users/test/project-a", "/Users/test/project-b"]);
  });

  it("addProject enforces max 20 projects", async () => {
    const ph = new ProjectHistory(historyFile);
    await ph.init();
    for (let i = 0; i < 25; i++) {
      ph.addProject(`/Users/test/project-${i}`);
    }
    const projects = ph.getProjects();
    expect(projects.length).toBe(20);
    // Most recent should be first
    expect(projects[0]).toBe("/Users/test/project-24");
    expect(projects[19]).toBe("/Users/test/project-5");
  });

  it("removeProject removes a project", async () => {
    const ph = new ProjectHistory(historyFile);
    await ph.init();
    ph.addProject("/Users/test/project-a");
    ph.addProject("/Users/test/project-b");
    ph.removeProject("/Users/test/project-a");
    expect(ph.getProjects()).toEqual(["/Users/test/project-b"]);
  });

  it("removeProject is a no-op for non-existent path", async () => {
    const ph = new ProjectHistory(historyFile);
    await ph.init();
    ph.addProject("/Users/test/project-a");
    ph.removeProject("/Users/test/nonexistent");
    expect(ph.getProjects()).toEqual(["/Users/test/project-a"]);
  });

  it("getProjects returns a copy (not a reference)", async () => {
    const ph = new ProjectHistory(historyFile);
    await ph.init();
    ph.addProject("/Users/test/project-a");
    const projects = ph.getProjects();
    projects.push("/Users/test/mutated");
    expect(ph.getProjects()).toEqual(["/Users/test/project-a"]);
  });

  it("rejects invalid project paths", async () => {
    const ph = new ProjectHistory(historyFile);
    await ph.init();
    ph.addProject("/path/a"); // too shallow
    ph.addProject("relative/path/project"); // not absolute
    ph.addProject(""); // empty
    ph.addProject("/Users/test/valid-project"); // valid
    expect(ph.getProjects()).toEqual(["/Users/test/valid-project"]);
  });

  it("filters out invalid paths on init", async () => {
    // Write a file with mixed valid and invalid paths
    await writeFile(
      historyFile,
      JSON.stringify(["/path/bad", "/Users/test/good-project", "/also/bad"]),
      "utf-8",
    );
    const ph = new ProjectHistory(historyFile);
    await ph.init();
    expect(ph.getProjects()).toEqual(["/Users/test/good-project"]);
  });

  it("handles corrupt file gracefully", async () => {
    await writeFile(historyFile, "not valid json", "utf-8");

    const ph = new ProjectHistory(historyFile);
    await ph.init();
    expect(ph.getProjects()).toEqual([]);
  });

  describe("Project Catalog discovery & union", () => {
    it("discovers projects under configured roots matching project markers", async () => {
      const rootDir = join(tempDir, "workspace");
      const projA = join(rootDir, "proj-a");
      const projB = join(rootDir, "proj-b");
      const ignoredDir = join(rootDir, "node_modules", "some-dep");
      const noMarkerDir = join(rootDir, "plain-dir");

      await mkdir(projA, { recursive: true });
      await mkdir(projB, { recursive: true });
      await mkdir(ignoredDir, { recursive: true });
      await mkdir(noMarkerDir, { recursive: true });

      await writeFile(join(projA, "pubspec.yaml"), "name: proj_a\n");
      await writeFile(join(projB, "package.json"), '{"name":"proj_b"}\n');
      await writeFile(join(ignoredDir, "package.json"), '{"name":"ignored"}\n');

      const ph = new ProjectHistory({
        filePath: historyFile,
        projectRoots: [rootDir],
        sessionLoader: async () => [],
      });
      await ph.init();

      const projects = ph.getProjects();
      expect(projects).toContain(projA);
      expect(projects).toContain(projB);
      expect(projects).not.toContain(ignoredDir);
      expect(projects).not.toContain(noMarkerDir);
    });

    it("unions explicit history, session paths and discovered roots with deduplication", async () => {
      const rootDir = join(tempDir, "workspace");
      const projDiscovered = join(rootDir, "discovered-proj");
      const projSession = join(rootDir, "session-proj");
      const projExplicit = join(rootDir, "explicit-proj");

      await mkdir(projDiscovered, { recursive: true });
      await mkdir(projSession, { recursive: true });
      await mkdir(projExplicit, { recursive: true });

      await writeFile(join(projDiscovered, "Cargo.toml"), "[package]\nname = 'disc'\n");
      await writeFile(join(projSession, "pyproject.toml"), "[tool.poetry]\n");
      await writeFile(join(projExplicit, ".git"), "gitdir: ../.git/worktrees/explicit\n");

      // Write explicit history
      await writeFile(historyFile, JSON.stringify([projExplicit]), "utf-8");

      const ph = new ProjectHistory({
        filePath: historyFile,
        projectRoots: [rootDir],
        sessionLoader: async () => [projSession, projExplicit], // session contains explicit proj too
      });
      await ph.init();

      const projects = ph.getProjects();
      // Explicit history comes first
      expect(projects[0]).toBe(projExplicit);
      expect(projects).toContain(projSession);
      expect(projects).toContain(projDiscovered);
      // Deduplicated
      const uniqueCount = new Set(projects).size;
      expect(projects.length).toBe(uniqueCount);
    });

    it("respects maxDiscoveredProjects and maxDepth bounds", async () => {
      const rootDir = join(tempDir, "workspace");
      const deepDir = join(rootDir, "level1", "level2", "level3", "deep-proj");
      await mkdir(deepDir, { recursive: true });
      await writeFile(join(deepDir, "package.json"), "{}");

      const shallowDir = join(rootDir, "level1", "shallow-proj");
      await mkdir(shallowDir, { recursive: true });
      await writeFile(join(shallowDir, "package.json"), "{}");

      const ph = new ProjectHistory({
        filePath: historyFile,
        projectRoots: [rootDir],
        maxDepth: 2, // deepDir is at depth 4, so it should be skipped
        sessionLoader: async () => [],
      });
      await ph.init();

      const projects = ph.getProjects();
      expect(projects).toContain(shallowDir);
      expect(projects).not.toContain(deepDir);
    });

    it("handles symlink loops safely without infinite recursion", async () => {
      const rootDir = join(tempDir, "workspace");
      const subDir = join(rootDir, "sub");
      await mkdir(subDir, { recursive: true });
      await writeFile(join(subDir, "package.json"), "{}");

      // Create symlink loop: sub/loop -> rootDir
      const loopLink = join(subDir, "loop");
      try {
        const { symlink } = await import("node:fs/promises");
        await symlink(rootDir, loopLink, "dir");
      } catch {}

      const ph = new ProjectHistory({
        filePath: historyFile,
        projectRoots: [rootDir],
        sessionLoader: async () => [],
      });
      await ph.init();

      const projects = ph.getProjects();
      expect(projects).toContain(subDir);
    });

    it("refresh updates catalog when new projects are created", async () => {
      const rootDir = join(tempDir, "workspace");
      const projA = join(rootDir, "proj-a");
      await mkdir(projA, { recursive: true });
      await writeFile(join(projA, "package.json"), "{}");

      const ph = new ProjectHistory({
        filePath: historyFile,
        projectRoots: [rootDir],
        sessionLoader: async () => [],
      });
      await ph.init();
      expect(ph.getProjects()).toEqual([projA]);

      // Add a new project on disk
      const projB = join(rootDir, "proj-b");
      await mkdir(projB, { recursive: true });
      await writeFile(join(projB, "go.mod"), "module projb\n");

      await ph.refresh();
      expect(ph.getProjects()).toContain(projA);
      expect(ph.getProjects()).toContain(projB);
    });
  });
});
