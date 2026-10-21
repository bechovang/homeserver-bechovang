import http from "node:http";
import os from "node:os";
import process from "node:process";
import { pathToFileURL } from "node:url";

const PORT = Number(process.env.PORT ?? 3000);
const HOST = process.env.HOST ?? "0.0.0.0";
const VERSION = process.env.APP_VERSION ?? "dev";
const startedAt = Date.now();
let requests = 0;

const escapeHtml = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

function page() {
  const rows = [
    ["hostname", os.hostname()],
    ["version", VERSION],
    ["node", process.version],
    ["uptime", `${Math.floor((Date.now() - startedAt) / 1000)}s`],
    ["requests", requests],
    ["time", new Date().toISOString()],
  ];
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>homelab hello</title>
<style>
  body{font:15px/1.6 ui-monospace,SFMono-Regular,Menlo,monospace;max-width:40rem;margin:4rem auto;padding:0 1rem;color:#111}
  h1{font-size:1.1rem;letter-spacing:.04em;text-transform:uppercase}
  table{border-collapse:collapse;width:100%}
  td{padding:.35rem .5rem;border-bottom:1px solid #e5e5e5}
  td:first-child{color:#666;width:9rem}
  code{background:#f3f3f3;padding:.1rem .3rem;border-radius:3px}
</style>
</head>
<body>
<h1>homelab / hello</h1>
<p>Deployed via GitHub Actions → GHCR → Dokploy → Cloudflare Tunnel.</p>
<table>${rows.map(([k, v]) => `<tr><td>${k}</td><td><code>${escapeHtml(v)}</code></td></tr>`).join("")}</table>
</body>
</html>`;
}

function info() {
  return {
    status: "ok",
    hostname: os.hostname(),
    version: VERSION,
    node: process.version,
    uptimeSeconds: Math.floor((Date.now() - startedAt) / 1000),
    requests,
    time: new Date().toISOString(),
  };
}

function send(res, status, type, body) {
  res.writeHead(status, { "content-type": type, "cache-control": "no-store" });
  res.end(body);
}

export function createServer() {
  return http.createServer((req, res) => {
    requests += 1;
    const url = new URL(req.url ?? "/", "http://localhost");

    if (req.method !== "GET" && req.method !== "HEAD") {
      return send(res, 405, "text/plain; charset=utf-8", "method not allowed\n");
    }
    switch (url.pathname) {
      case "/":
        return send(res, 200, "text/html; charset=utf-8", page());
      case "/health":
        return send(res, 200, "application/json", JSON.stringify({ status: "ok" }));
      case "/api/info":
        return send(res, 200, "application/json", JSON.stringify(info()));
      default:
        return send(res, 404, "text/plain; charset=utf-8", "not found\n");
    }
  });
}

if (pathToFileURL(process.argv[1]).href === import.meta.url) {
  const server = createServer();
  server.listen(PORT, HOST, () => {
    console.log(`hello listening on http://${HOST}:${PORT} version=${VERSION}`);
  });
  for (const signal of ["SIGTERM", "SIGINT"]) {
    process.on(signal, () => {
      console.log(`${signal} received, closing`);
      server.close(() => process.exit(0));
      setTimeout(() => process.exit(1), 5000).unref();
    });
  }
}
