import { randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { getReachableAddresses } from "./startup-info.js";

export function loadNetworkIdentity(path: string): string {
  mkdirSync(dirname(path), { recursive: true });
  try {
    writeFileSync(path, randomUUID(), { flag: "wx", mode: 0o600 });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
  }
  const id = readFileSync(path, "utf8").trim();
  if (!/^[a-f0-9-]{36}$/.test(id)) throw new Error("Invalid Bridge network identity");
  return id;
}

export function networkRoutes(
  port: number,
  host: string,
  addresses: { ip: string; label: string }[],
) {
  const wildcard = host === "::" || host === "0.0.0.0";
  return [...new Set(addresses
    .filter(({ ip, label }) => (label === "LAN" || label === "IPv6") &&
      (wildcard || host === ip) && !(host === "0.0.0.0" && ip.includes(":")))
    .map(({ ip }) => `ws://${ip.includes(":") ? `[${ip}]` : ip}:${port}`))].slice(0, 12);
}

export function createNetworkDiscovery(id: string, port: number, host: string) {
  let expires = 0;
  let endpoints: string[] = [];
  return () => {
    if (Date.now() >= expires) {
      endpoints = networkRoutes(port, host, getReachableAddresses());
      expires = Date.now() + 30_000;
    }
    return { bridgeId: id, endpoints };
  };
}
