import { existsSync, createReadStream } from "node:fs";
import { readFile, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import type { IncomingMessage, ServerResponse } from "node:http";

export interface ReleaseManifest {
  versionCode: number;
  versionName: string;
  sha256: string;
  size: number;
  buildTime: string;
  downloadPath: string;
  changelog?: string;
  certificateSha256?: string;
  minBridgeVersion?: string;
}

export class UpdateService {
  private releaseDir: string;

  constructor(releaseDir?: string) {
    this.releaseDir =
      releaseDir ??
      process.env.BRIDGE_RELEASE_DIR ??
      join(homedir(), ".anycoding", "releases");
  }

  getReleaseDirectory(): string {
    return this.releaseDir;
  }

  async getManifest(): Promise<ReleaseManifest | null> {
    const manifestPath = join(this.releaseDir, "manifest.json");
    if (!existsSync(manifestPath)) {
      return null;
    }

    try {
      const content = await readFile(manifestPath, "utf-8");
      const parsed = JSON.parse(content) as Partial<ReleaseManifest>;

      if (
        typeof parsed.versionCode !== "number" ||
        typeof parsed.versionName !== "string" ||
        typeof parsed.sha256 !== "string" ||
        typeof parsed.size !== "number"
      ) {
        return null;
      }

      return {
        versionCode: parsed.versionCode,
        versionName: parsed.versionName,
        sha256: parsed.sha256,
        size: parsed.size,
        buildTime: parsed.buildTime ?? new Date().toISOString(),
        downloadPath: parsed.downloadPath ?? "/api/update/download",
        changelog: parsed.changelog ?? "",
        certificateSha256: parsed.certificateSha256,
        minBridgeVersion: parsed.minBridgeVersion,
      };
    } catch {
      return null;
    }
  }

  async getApkPath(): Promise<string | null> {
    const manifest = await this.getManifest();
    if (manifest?.downloadPath) {
      const customName = basename(manifest.downloadPath);
      const customPath = join(this.releaseDir, customName);
      if (existsSync(customPath)) return customPath;
    }

    const candidates = [
      join(this.releaseDir, "anycoding.apk"),
      join(this.releaseDir, "app.apk"),
      join(this.releaseDir, "app-debug.apk"),
      join(this.releaseDir, "app-release.apk"),
    ];

    for (const c of candidates) {
      if (existsSync(c)) return c;
    }

    return null;
  }

  async handleManifestRequest(
    req: IncomingMessage,
    res: ServerResponse,
  ): Promise<boolean> {
    const url = req.url?.split("?")[0];
    if (
      (url === "/api/update/manifest" || url === "/update/manifest") &&
      req.method === "GET"
    ) {
      const manifest = await this.getManifest();
      if (!manifest) {
        res.writeHead(404, { "Content-Type": "application/json" });
        res.end(
          JSON.stringify({
            error: "No release manifest found",
            releaseDir: this.releaseDir,
          }),
        );
        return true;
      }

      res.writeHead(200, {
        "Content-Type": "application/json",
        "Cache-Control": "no-cache",
      });
      res.end(JSON.stringify(manifest));
      return true;
    }
    return false;
  }

  async handleDownloadRequest(
    req: IncomingMessage,
    res: ServerResponse,
  ): Promise<boolean> {
    const url = req.url?.split("?")[0];
    if (
      (url === "/api/update/download" || url === "/update/download") &&
      (req.method === "GET" || req.method === "HEAD")
    ) {
      const apkPath = await this.getApkPath();
      if (!apkPath || !existsSync(apkPath)) {
        res.writeHead(404, { "Content-Type": "application/json" });
        res.end(
          JSON.stringify({
            error: "APK binary not found in release directory",
          }),
        );
        return true;
      }

      let fileStat;
      try {
        fileStat = await stat(apkPath);
      } catch {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Failed to stat APK file" }));
        return true;
      }

      const totalSize = fileStat.size;
      const etag = `"${fileStat.size.toString(16)}-${Math.floor(fileStat.mtimeMs).toString(16)}"`;

      const baseHeaders: Record<string, string | number> = {
        "Content-Type": "application/vnd.android.package-archive",
        "Accept-Ranges": "bytes",
        "Content-Disposition": 'attachment; filename="anycoding.apk"',
        ETag: etag,
        "Last-Modified": fileStat.mtime.toUTCString(),
      };

      if (req.method === "HEAD") {
        res.writeHead(200, {
          ...baseHeaders,
          "Content-Length": totalSize,
        });
        res.end();
        return true;
      }

      const rangeHeader = req.headers.range;
      if (rangeHeader && rangeHeader.startsWith("bytes=")) {
        const parts = rangeHeader.replace(/bytes=/, "").split("-");
        const start = parseInt(parts[0], 10);
        const end = parts[1] ? parseInt(parts[1], 10) : totalSize - 1;

        if (isNaN(start) || isNaN(end) || start >= totalSize || end >= totalSize || start > end) {
          res.writeHead(416, {
            "Content-Range": `bytes */${totalSize}`,
          });
          res.end();
          return true;
        }

        const chunkSize = end - start + 1;
        res.writeHead(206, {
          ...baseHeaders,
          "Content-Range": `bytes ${start}-${end}/${totalSize}`,
          "Content-Length": chunkSize,
        });

        const stream = createReadStream(apkPath, { start, end });
        stream.pipe(res);
        return true;
      }

      res.writeHead(200, {
        ...baseHeaders,
        "Content-Length": totalSize,
      });

      const stream = createReadStream(apkPath);
      stream.pipe(res);
      return true;
    }

    return false;
  }

  async handleRequest(
    req: IncomingMessage,
    res: ServerResponse,
  ): Promise<boolean> {
    if (await this.handleManifestRequest(req, res)) return true;
    if (await this.handleDownloadRequest(req, res)) return true;
    return false;
  }
}
