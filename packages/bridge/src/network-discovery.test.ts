import { describe, it, expect } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadNetworkIdentity, networkRoutes } from "./network-discovery.js";

describe("network discovery", () => {
  const addresses = [
    { ip: "192.168.31.247", label: "LAN" },
    { ip: "2408:824e::6f1", label: "IPv6" },
    { ip: "100.64.0.1", label: "Tailscale" },
  ];
  it("advertises dual-stack addresses without exposing tunnel addresses", () => {
    expect(networkRoutes(8766, "::", addresses)).toEqual([
      "ws://192.168.31.247:8766", "ws://[2408:824e::6f1]:8766",
    ]);
  });
  it("does not advertise IPv6 on an IPv4-only listener", () => {
    expect(networkRoutes(8766, "0.0.0.0", addresses)).toHaveLength(1);
  });
  it("respects explicitly bound addresses and deduplicates", () => {
    expect(networkRoutes(8766, "192.168.31.247", [...addresses, ...addresses])).toEqual(["ws://192.168.31.247:8766"]);
    expect(networkRoutes(8766, "127.0.0.1", addresses)).toEqual([]);
  });
  it("preserves the installation identity across restarts", () => {
    const dir = mkdtempSync(join(tmpdir(), "anycoding-network-test-"));
    try {
      const path = join(dir, "network.id");
      expect(loadNetworkIdentity(path)).toBe(loadNetworkIdentity(path));
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
});
