import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { createServer } from "./server.js";

let server;
let base;

before(async () => {
  server = createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => new Promise((resolve) => server.close(resolve)));

test("GET /health returns ok", async () => {
  const res = await fetch(`${base}/health`);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { status: "ok" });
});

test("GET /api/info exposes runtime metadata", async () => {
  const res = await fetch(`${base}/api/info`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, "ok");
  assert.equal(body.version, "dev");
  assert.match(body.node, /^v\d+\./);
});

test("GET / renders html", async () => {
  const res = await fetch(`${base}/`);
  assert.equal(res.status, 200);
  assert.match(res.headers.get("content-type"), /text\/html/);
  assert.match(await res.text(), /homelab \/ hello/);
});

test("unknown path is 404", async () => {
  const res = await fetch(`${base}/nope`);
  assert.equal(res.status, 404);
});

test("non-GET is 405", async () => {
  const res = await fetch(`${base}/`, { method: "POST" });
  assert.equal(res.status, 405);
});
