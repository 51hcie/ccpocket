import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdir, writeFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createServer, request, type Server } from "node:http";
import { UpdateService, type ReleaseManifest } from "./update-service.js";
import { formatHttpUrl } from "./startup-info.js";

describe("UpdateService", () => {
  let testDir: string;
  let updateService: UpdateService;
  let server: Server;
  let port: number;

  beforeEach(async () => {
    testDir = join(
      tmpdir(),
      `update-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    );
    await mkdir(testDir, { recursive: true });
    updateService = new UpdateService(testDir);
  });

  afterEach(async () => {
    if (server) {
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }
    await rm(testDir, { recursive: true, force: true });
  });

  function startTestHttpServer(): Promise<number> {
    return new Promise((resolve) => {
      server = createServer(async (req, res) => {
        if (await updateService.handleRequest(req, res)) return;
        res.writeHead(404);
        res.end("Not Found");
      });
      server.listen(0, "127.0.0.1", () => {
        const addr = server.address();
        if (addr && typeof addr === "object") {
          port = addr.port;
          resolve(port);
        }
      });
    });
  }

  it("returns null when manifest does not exist", async () => {
    const manifest = await updateService.getManifest();
    expect(manifest).toBeNull();
  });

  it("parses valid manifest correctly", async () => {
    const sampleManifest: ReleaseManifest = {
      versionCode: 218,
      versionName: "1.115.3",
      sha256: "59186b6981215494ee6e21e8a988dc7a434eb7ffa40bfc226e9dbdbc585cb2d2",
      size: 1048576,
      buildTime: "2026-08-25T12:00:00.000Z",
      downloadPath: "/api/update/download",
      changelog: "Batch 2 release",
    };
    await writeFile(
      join(testDir, "manifest.json"),
      JSON.stringify(sampleManifest),
      "utf-8",
    );

    const manifest = await updateService.getManifest();
    expect(manifest).not.toBeNull();
    expect(manifest?.versionCode).toBe(218);
    expect(manifest?.versionName).toBe("1.115.3");
    expect(manifest?.sha256).toBe(sampleManifest.sha256);
    expect(manifest?.size).toBe(1048576);
  });

  it("handles corrupted manifest gracefully", async () => {
    await writeFile(
      join(testDir, "manifest.json"),
      JSON.stringify({ invalid: true }),
      "utf-8",
    );

    const manifest = await updateService.getManifest();
    expect(manifest).toBeNull();
  });

  it("serves GET /api/update/manifest via HTTP", async () => {
    const sampleManifest: ReleaseManifest = {
      versionCode: 218,
      versionName: "1.115.3",
      sha256: "abcdef1234567890",
      size: 2048,
      buildTime: "2026-08-25T12:00:00.000Z",
      downloadPath: "/api/update/download",
    };
    await writeFile(
      join(testDir, "manifest.json"),
      JSON.stringify(sampleManifest),
      "utf-8",
    );

    const testPort = await startTestHttpServer();

    const response = await new Promise<{ status: number; body: any }>(
      (resolve) => {
        request(`http://127.0.0.1:${testPort}/api/update/manifest`, (res) => {
          let data = "";
          res.on("data", (chunk) => (data += chunk));
          res.on("end", () => {
            resolve({
              status: res.statusCode || 0,
              body: JSON.parse(data),
            });
          });
        }).end();
      },
    );

    expect(response.status).toBe(200);
    expect(response.body.versionCode).toBe(218);
    expect(response.body.versionName).toBe("1.115.3");
  });

  it("serves HEAD /api/update/download with correct headers", async () => {
    const fakeApkContent = Buffer.from("PK-FAKE-APK-CONTENT-DATA-1234567890");
    await writeFile(join(testDir, "anycoding.apk"), fakeApkContent);

    const testPort = await startTestHttpServer();

    const response = await new Promise<{
      status: number;
      headers: Record<string, string | string[] | undefined>;
    }>((resolve) => {
      const req = request(
        `http://127.0.0.1:${testPort}/api/update/download`,
        { method: "HEAD" },
        (res) => {
          resolve({
            status: res.statusCode || 0,
            headers: res.headers,
          });
        },
      );
      req.end();
    });

    expect(response.status).toBe(200);
    expect(response.headers["content-length"]).toBe(
      fakeApkContent.length.toString(),
    );
    expect(response.headers["accept-ranges"]).toBe("bytes");
    expect(response.headers["content-type"]).toBe(
      "application/vnd.android.package-archive",
    );
  });

  it("serves GET /api/update/download with full content", async () => {
    const fakeApkContent = Buffer.from("PK-FULL-BINARY-PAYLOAD-ABCDEFG");
    await writeFile(join(testDir, "anycoding.apk"), fakeApkContent);

    const testPort = await startTestHttpServer();

    const response = await new Promise<{ status: number; body: Buffer }>(
      (resolve) => {
        request(`http://127.0.0.1:${testPort}/api/update/download`, (res) => {
          const chunks: Buffer[] = [];
          res.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
          res.on("end", () => {
            resolve({
              status: res.statusCode || 0,
              body: Buffer.concat(chunks),
            });
          });
        }).end();
      },
    );

    expect(response.status).toBe(200);
    expect(response.body.equals(fakeApkContent)).toBe(true);
  });

  it("serves GET /api/update/download with byte range (206 Partial Content)", async () => {
    const fakeApkContent = Buffer.from("0123456789ABCDEF");
    await writeFile(join(testDir, "anycoding.apk"), fakeApkContent);

    const testPort = await startTestHttpServer();

    const response = await new Promise<{
      status: number;
      body: Buffer;
      contentRange?: string;
    }>((resolve) => {
      const req = request(
        `http://127.0.0.1:${testPort}/api/update/download`,
        {
          headers: { Range: "bytes=0-3" },
        },
        (res) => {
          const chunks: Buffer[] = [];
          res.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
          res.on("end", () => {
            resolve({
              status: res.statusCode || 0,
              body: Buffer.concat(chunks),
              contentRange: res.headers["content-range"],
            });
          });
        },
      );
      req.end();
    });

    expect(response.status).toBe(206);
    expect(response.contentRange).toBe(`bytes 0-3/${fakeApkContent.length}`);
    expect(response.body.toString()).toBe("0123");
  });

  it("formats IPv4 and literal IPv6 URLs properly", () => {
    const ipv4Url = formatHttpUrl("192.168.1.100", 8766, "/api/update/manifest");
    expect(ipv4Url).toBe("http://192.168.1.100:8766/api/update/manifest");

    const ipv6Url = formatHttpUrl("2408:824e:158d:5a80::1", 8766, "/api/update/manifest");
    expect(ipv6Url).toBe("http://[2408:824e:158d:5a80::1]:8766/api/update/manifest");

    const bracketedIpv6Url = formatHttpUrl("[::1]", 8766, "/api/update/download");
    expect(bracketedIpv6Url).toBe("http://[::1]:8766/api/update/download");
  });
});
