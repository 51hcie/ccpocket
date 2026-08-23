import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mockNetworkInterfaces = vi.fn();
const mockQrToString = vi.fn();

vi.mock("node:os", () => ({
  default: {
    networkInterfaces: () => mockNetworkInterfaces(),
  },
}));

vi.mock("qrcode", () => ({
  default: {
    toString: (...args: unknown[]) => mockQrToString(...args),
  },
}));

const {
  buildConnectionUrl,
  printStartupInfo,
  validatePublicWsUrl,
  formatHostForUrl,
  formatWsUrl,
  formatHttpUrl,
  isGlobalIpv6,
} = await import("./startup-info.js");

describe("startup-info", () => {
  const originalEnv = process.env;
  const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
  const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

  beforeEach(() => {
    vi.clearAllMocks();
    process.env = { ...originalEnv };
    delete process.env.BRIDGE_PUBLIC_WS_URL;
    delete process.env.BRIDGE_DEMO_MODE;
    mockQrToString.mockResolvedValue("QR");
    mockNetworkInterfaces.mockReturnValue({
      en0: [
        { family: "IPv4", internal: false, address: "192.168.1.20" },
        { family: "IPv6", internal: false, address: "2408:824e:158d:5a80:875:122:45bf:5441" },
        { family: "IPv6", internal: false, address: "fe80::1c9d:a7a0:a569:83af" },
      ],
      utun4: [
        { family: "IPv4", internal: false, address: "100.64.0.2" },
        { family: "IPv6", internal: false, address: "fdfe:dcba:9876::1" },
      ],
      lo0: [
        { family: "IPv4", internal: true, address: "127.0.0.1" },
        { family: "IPv6", internal: true, address: "::1" },
      ],
    });
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  describe("formatHostForUrl & URL builders", () => {
    it("formats IPv4 and hostnames without brackets", () => {
      expect(formatHostForUrl("192.168.1.1")).toBe("192.168.1.1");
      expect(formatHostForUrl("localhost")).toBe("localhost");
      expect(formatWsUrl("192.168.1.1", 8766)).toBe("ws://192.168.1.1:8766");
      expect(formatHttpUrl("192.168.1.1", 8766, "/health")).toBe("http://192.168.1.1:8766/health");
    });

    it("formats IPv6 with brackets", () => {
      expect(formatHostForUrl("2001:db8::1")).toBe("[2001:db8::1]");
      expect(formatHostForUrl("[2001:db8::1]")).toBe("[2001:db8::1]");
      expect(formatWsUrl("2001:db8::1", 8766)).toBe("ws://[2001:db8::1]:8766");
      expect(formatWsUrl("[2001:db8::1]", 8766)).toBe("ws://[2001:db8::1]:8766");
      expect(formatHttpUrl("2001:db8::1", 8766, "/health")).toBe("http://[2001:db8::1]:8766/health");
      expect(formatHttpUrl("2001:db8::1", 8766, "health")).toBe("http://[2001:db8::1]:8766/health");
    });
  });

  describe("isGlobalIpv6 filtering", () => {
    it("excludes loopback, link-local, and ULA", () => {
      expect(isGlobalIpv6("::1")).toBe(false);
      expect(isGlobalIpv6("0:0:0:0:0:0:0:1")).toBe(false);
      expect(isGlobalIpv6("fe80::1c9d:a7a0:a569:83af")).toBe(false);
      expect(isGlobalIpv6("fdfe:dcba:9876::1")).toBe(false);
      expect(isGlobalIpv6("fc00::1")).toBe(false);
      expect(isGlobalIpv6("::ffff:192.168.1.1")).toBe(false);
    });

    it("accepts valid global unicast IPv6", () => {
      expect(isGlobalIpv6("2408:824e:158d:5a80:875:122:45bf:5441")).toBe(true);
      expect(isGlobalIpv6("2001:db8::1")).toBe(true);
      expect(isGlobalIpv6("2607:f8b0:4005:805::200e")).toBe(true);
    });
  });

  describe("validatePublicWsUrl", () => {
    it("returns trimmed url for valid wss url", () => {
      expect(validatePublicWsUrl("  wss://example.com/path?x=1  ")).toBe(
        "wss://example.com/path?x=1",
      );
    });

    it("accepts IPv6 public ws url", () => {
      expect(validatePublicWsUrl("ws://[2001:db8::1]:8766")).toBe(
        "ws://[2001:db8::1]:8766",
      );
    });

    it("returns undefined for invalid protocol", () => {
      expect(validatePublicWsUrl("https://example.com")).toBeUndefined();
    });
  });

  describe("buildConnectionUrl", () => {
    it("includes token when api key is provided", () => {
      expect(buildConnectionUrl("wss://example.com/bridge", "secret")).toBe(
        "ccpocket://connect?url=wss%3A%2F%2Fexample.com%2Fbridge&token=secret",
      );
    });

    it("encodes IPv6 ws url properly", () => {
      expect(buildConnectionUrl("ws://[2001:db8::1]:8766", "mytoken")).toBe(
        "ccpocket://connect?url=ws%3A%2F%2F%5B2001%3Adb8%3A%3A1%5D%3A8766&token=mytoken",
      );
    });

    it("omits token when api key is empty", () => {
      expect(buildConnectionUrl("ws://192.168.1.20:8765")).toBe(
        "ccpocket://connect?url=ws%3A%2F%2F192.168.1.20%3A8765",
      );
    });
  });

  describe("printStartupInfo", () => {
    it("displays both LAN and IPv6 addresses", async () => {
      await printStartupInfo(8765, "::", "test-token");

      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("LAN:         ws://192.168.1.20:8765"),
      );
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("IPv6:        ws://[2408:824e:158d:5a80:875:122:45bf:5441]:8765"),
      );
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("Tailscale:   ws://100.64.0.2:8765"),
      );
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining(
          "Deep Link: ccpocket://connect?url=ws%3A%2F%2F192.168.1.20%3A8765&token=test-token",
        ),
      );
    });

    it("uses public url for deep link and qr when configured", async () => {
      process.env.BRIDGE_PUBLIC_WS_URL = "wss://example.ngrok-free.app/ws";

      await printStartupInfo(8765, "0.0.0.0", "test-token");

      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("Public:      wss://example.ngrok-free.app/ws"),
      );
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining(
          "Deep Link: ccpocket://connect?url=wss%3A%2F%2Fexample.ngrok-free.app%2Fws&token=test-token",
        ),
      );
      expect(mockQrToString).toHaveBeenCalledWith(
        "ccpocket://connect?url=wss%3A%2F%2Fexample.ngrok-free.app%2Fws&token=test-token",
        expect.any(Object),
      );
    });

    it("omits token from public deep link in demo mode", async () => {
      process.env.BRIDGE_PUBLIC_WS_URL = "wss://example.ngrok-free.app";
      process.env.BRIDGE_DEMO_MODE = "1";

      await printStartupInfo(8765, "0.0.0.0", "test-token");

      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining(
          "Deep Link: ccpocket://connect?url=wss%3A%2F%2Fexample.ngrok-free.app",
        ),
      );
      expect(logSpy).not.toHaveBeenCalledWith(expect.stringContaining("token=test-token"));
      expect(logSpy).not.toHaveBeenCalledWith(
        expect.stringContaining("Tailscale:   ws://100.64.0.2:8765"),
      );
    });

    it("warns and falls back when public url is invalid", async () => {
      process.env.BRIDGE_PUBLIC_WS_URL = "https://example.com";

      await printStartupInfo(8765, "0.0.0.0", "test-token");

      expect(warnSpy).toHaveBeenCalledWith(
        "[bridge] Warning: ignoring invalid BRIDGE_PUBLIC_WS_URL: https://example.com",
      );
      expect(mockQrToString).toHaveBeenCalledWith(
        "ccpocket://connect?url=ws%3A%2F%2F192.168.1.20%3A8765&token=test-token",
        expect.any(Object),
      );
    });

    it("still prints public deep link when no local addresses are available", async () => {
      process.env.BRIDGE_PUBLIC_WS_URL = "wss://example.com";
      mockNetworkInterfaces.mockReturnValue({});

      await printStartupInfo(8765, "0.0.0.0", "test-token");

      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("Public:      wss://example.com"),
      );
      expect(mockQrToString).toHaveBeenCalled();
    });
  });
});
