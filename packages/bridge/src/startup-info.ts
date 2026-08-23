import os from "node:os";
import { execSync } from "node:child_process";
import QRCode from "qrcode";

export interface NetworkAddress {
  ip: string;
  label: string;
}

export function formatHostForUrl(host: string): string {
  const trimmed = host.trim();
  if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
    return trimmed;
  }
  if (trimmed.includes(":")) {
    return `[${trimmed}]`;
  }
  return trimmed;
}

export function formatWsUrl(host: string, port: number): string {
  return `ws://${formatHostForUrl(host)}:${port}`;
}

export function formatHttpUrl(host: string, port: number, path = ""): string {
  const cleanPath = path.startsWith("/") ? path : `/${path}`;
  return `http://${formatHostForUrl(host)}:${port}${cleanPath}`;
}

export function validatePublicWsUrl(rawUrl?: string): string | undefined {
  const trimmed = rawUrl?.trim();
  if (!trimmed) return undefined;

  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    return undefined;
  }

  if ((parsed.protocol !== "ws:" && parsed.protocol !== "wss:") || !parsed.host) {
    return undefined;
  }

  return trimmed;
}

export function isGlobalIpv6(addr: string): boolean {
  const lower = addr.toLowerCase().trim();
  // Exclude loopback
  if (lower === "::1" || lower === "0:0:0:0:0:0:0:1") return false;
  // Exclude link-local fe80::/10 (fe80, fe90, fea0, feb0...)
  if (
    lower.startsWith("fe8") ||
    lower.startsWith("fe9") ||
    lower.startsWith("fea") ||
    lower.startsWith("feb")
  ) {
    return false;
  }
  // Exclude IPv4-mapped IPv6 ::ffff:0:0/96
  if (lower.startsWith("::ffff:")) return false;
  // Exclude unique local addresses (fc00::/7 -> fc00..fdff)
  if (lower.startsWith("fc") || lower.startsWith("fd")) return false;
  // Exclude multicast ff00::/8
  if (lower.startsWith("ff")) return false;
  // Exclude unspecified ::
  if (lower === "::" || lower === "0:0:0:0:0:0:0:0") return false;

  return true;
}

export function getDeprecatedIpv6Addresses(): Set<string> {
  const deprecated = new Set<string>();
  if (process.platform === "darwin") {
    try {
      const out = execSync("ifconfig", { encoding: "utf-8", timeout: 1000 });
      for (const line of out.split("\n")) {
        if (line.includes("inet6") && line.includes("deprecated")) {
          const match = line.trim().match(/^inet6\s+([0-9a-fA-F:]+)/);
          if (match) deprecated.add(match[1].toLowerCase());
        }
      }
    } catch {
      // ignore
    }
  } else if (process.platform === "linux") {
    try {
      const out = execSync("ip -6 addr show", { encoding: "utf-8", timeout: 1000 });
      for (const line of out.split("\n")) {
        if (line.includes("deprecated")) {
          const match = line.trim().match(/inet6\s+([0-9a-fA-F:]+)/);
          if (match) deprecated.add(match[1].toLowerCase());
        }
      }
    } catch {
      // ignore
    }
  }
  return deprecated;
}

export function getReachableAddresses(): NetworkAddress[] {
  const interfaces = os.networkInterfaces();
  const addresses: NetworkAddress[] = [];
  const deprecatedIpv6 = getDeprecatedIpv6Addresses();

  for (const [name, ifaces] of Object.entries(interfaces)) {
    if (!ifaces) continue;
    for (const iface of ifaces) {
      if (iface.internal) continue;

      if (iface.family === "IPv4") {
        let label = "LAN";
        if (
          iface.address.startsWith("100.") ||
          name.startsWith("utun") ||
          name.toLowerCase().includes("tailscale")
        ) {
          label = "Tailscale";
        }
        addresses.push({ ip: iface.address, label });
      } else if (iface.family === "IPv6") {
        if (isGlobalIpv6(iface.address) && !deprecatedIpv6.has(iface.address.toLowerCase())) {
          addresses.push({ ip: iface.address, label: "IPv6" });
        }
      }
    }
  }

  return addresses;
}

export function buildConnectionUrl(
  wsUrl: string,
  apiKey?: string,
): string {
  const params = new URLSearchParams({ url: wsUrl });
  if (apiKey) {
    params.set("token", apiKey);
  }
  return `ccpocket://connect?${params.toString()}`;
}

export async function printStartupInfo(
  port: number,
  _host: string,
  apiKey?: string,
): Promise<void> {
  const addresses = getReachableAddresses();
  const demoMode = !!process.env.BRIDGE_DEMO_MODE;
  const rawPublicWsUrl = process.env.BRIDGE_PUBLIC_WS_URL;
  const publicWsUrl = validatePublicWsUrl(rawPublicWsUrl);

  if (rawPublicWsUrl && !publicWsUrl) {
    console.warn(
      `[bridge] Warning: ignoring invalid BRIDGE_PUBLIC_WS_URL: ${rawPublicWsUrl}`,
    );
  }

  // Demo mode: exclude Tailscale and public IPv6 addresses for video recording
  const displayAddresses = demoMode
    ? addresses.filter((a) => a.label !== "Tailscale" && a.label !== "IPv6")
    : addresses;

  if (displayAddresses.length === 0 && !publicWsUrl) return;

  const lines: string[] = [];
  lines.push("");
  if (demoMode) {
    lines.push("[bridge] ─── Connection Info [DEMO MODE] ────────────────");
  } else {
    lines.push("[bridge] ─── Connection Info ───────────────────────────");
  }

  // Group by label
  const grouped = new Map<string, string[]>();
  for (const addr of displayAddresses) {
    const list = grouped.get(addr.label) ?? [];
    list.push(addr.ip);
    grouped.set(addr.label, list);
  }

  for (const [label, ips] of grouped) {
    for (const ip of ips) {
      const padded = `${label}:`.padEnd(12);
      lines.push(`[bridge]   ${padded} ${formatWsUrl(ip, port)}`);
    }
  }

  if (publicWsUrl) {
    lines.push(`[bridge]   ${"Public:".padEnd(12)} ${publicWsUrl}`);
  }

  const lanAddr = displayAddresses.find((a) => a.label === "LAN");
  const ipv6Addr = displayAddresses.find((a) => a.label === "IPv6");
  const fallbackIp = lanAddr?.ip ?? ipv6Addr?.ip ?? displayAddresses[0]?.ip;

  const fallbackWsUrl = fallbackIp ? formatWsUrl(fallbackIp, port) : undefined;
  const connectWsUrl = publicWsUrl ?? fallbackWsUrl;
  if (!connectWsUrl) return;

  // Demo mode: omit API key from deep link
  const deepLink = buildConnectionUrl(connectWsUrl, demoMode ? undefined : apiKey);

  lines.push("");
  lines.push(`[bridge]   Deep Link: ${deepLink}`);
  lines.push("");
  lines.push("[bridge]   Scan QR code with ccpocket app:");

  // Print all non-QR lines
  console.log(lines.join("\n"));

  // Generate and print QR code
  try {
    const qrText = await QRCode.toString(deepLink, {
      type: "terminal",
      small: true,
    });
    // Indent QR code lines
    const indented = qrText
      .split("\n")
      .map((line) => `           ${line}`)
      .join("\n");
    console.log(indented);
  } catch {
    console.log("[bridge]   (QR code generation failed)");
  }

  console.log(
    "[bridge] ───────────────────────────────────────────────",
  );
}
