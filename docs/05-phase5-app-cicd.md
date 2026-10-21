# 05 — Phase 5: App đầu tiên + CI/CD (GHCR → Dokploy)

> Trạng thái 21/10/2026: **pipeline build đã xanh**, app scaffold xong, chờ 3 credential để nối deploy.
> Repo: `bechovang/homeserver-bechovang` (private) · image: `ghcr.io/bechovang/homeserver-bechovang/hello`

## 1. App `apps/hello`

Zero dependency, Node 24 http server — chọn thay vì Next.js để giữ RAM server thấp (image ~50MB, RSS ~40MB).

| Route | Nội dung |
|---|---|
| `GET /` | HTML hiển thị hostname, version, node, uptime, số request |
| `GET /health` | `{"status":"ok"}` — dùng cho Traefik/Dokploy healthcheck |
| `GET /api/info` | JSON metadata |
| khác | 404; method không phải GET/HEAD → 405 |

- `server.js` export `createServer()` để test in-process, chỉ listen khi chạy trực tiếp.
- Test: `node --test` (5 test: health, info, html, 404, 405).
- Dockerfile: `node:24-alpine`, `USER node`, `HEALTHCHECK` bằng wget, `CMD node server.js`.
- Version hiển thị lấy từ `APP_VERSION` (workflow truyền `sha-...`).

## 2. Workflow `.github/workflows/ci.yml`

```
push main / PR
  ├─ test   : node --test (apps/hello)
  ├─ build  : docker build → ghcr.io/<repo>/hello:{latest,sha-<sha>}   (chỉ push)
  └─ deploy : tailscale join (tag:ci) → POST $DOKPLOY_URL/api/application.deploy
              chỉ chạy khi ref=main và vars.DEPLOY_ENABLED == 'true'
```

- Không build trên server: server chỉ `docker pull`.
- `cache-from/to: type=gha` để build lần sau nhanh.
- CI đỏ (test fail) → không có bước build/deploy.

## 3. Credential cần (phía user)

| Nơi | Tên | Giá trị |
|---|---|---|
| Dokploy → Settings → API Keys | `DOKPLOY_API_KEY` | key tạo app/deploy |
| Dokploy → app `hello` → Registry | GHCR creds **hoặc** để package public | xem mục 4 |
| Tailscale admin → Settings → OAuth clients | `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET` | tag `tag:ci` |
| GitHub repo → Settings → Secrets | `DOKPLOY_URL` = `http://100.83.245.0:3000` | |
| GitHub repo → Settings → Secrets | `DOKPLOY_APP_ID` | lấy sau khi tạo app |
| GitHub repo → Settings → Variables | `DEPLOY_ENABLED` = `true` | bật job deploy |

GitHub secrets có thể set bằng `gh secret set` (mình làm khi có giá trị).

## 4. GHCR private → Dokploy pull

Package kế thừa visibility của repo (private) → server pull bị `unauthorized`. Hai cách:

1. **Public package** (khuyến nghị): GitHub → profile → Packages → `hello` → Package settings → Change visibility → Public. Repo vẫn private; image chỉ chứa app hello.
2. **Registry credential**: tạo PAT classic scope `read:packages` → Dokploy → Settings → Registry (hoặc app → Advanced → Registry) → username `bechovang`, password PAT.

## 5. Tailscale OAuth client + ACL

1. `login.tailscale.com/admin/settings/oauth` → **Generate OAuth client** → tag **`tag:ci`** (tạo tag trong Access controls trước nếu chưa có).
2. ACL (`Access controls`) thêm tag vào `tagOwners` và cho phép tới Dokploy:

```json
{
  "tagOwners": { "tag:ci": ["autogroup:admin"] },
  "grants": [
    { "src": ["tag:ci"], "dst": ["homelab-01"], "ip": ["tcp:3000"] }
  ]
}
```

## 6. Dokploy application

| Trường | Giá trị |
|---|---|
| Project | `personal` |
| Application | `hello` |
| Provider | **Docker** (không phải GitHub/Build) |
| Image | `ghcr.io/bechovang/homeserver-bechovang/hello:latest` |
| Port | `3000` |
| Domain | `hello.phucnn.io.vn` · **HTTPS OFF · Certificate None** |
| Healthcheck | HTTP `/health` |
| Replicas | 1 |

Lý do HTTPS OFF: tunnel đã terminate TLS ở Cloudflare; bật HTTPS trong Dokploy sinh middleware redirect → vòng lặp.

## 7. Nghiệm thu

```bash
curl -sS https://hello.phucnn.io.vn/health            # {"status":"ok"}
curl -sS https://hello.phucnn.io.vn/api/info | jq .version   # sha-<commit>
docker ps --filter name=hello                          # 1 replica healthy
```
- [ ] CI xanh, image `:sha-<sha>` khớp commit
- [ ] CI đỏ → không deploy
- [ ] Push commit mới → `:latest` đổi → Dokploy tự deploy
- [ ] Rollback: đổi image tag về `sha-...` cũ trong Dokploy → Deploy

## 8. Debug

| Triệu chứng | Nguyên nhân | Fix |
|---|---|---|
| `unauthorized` khi pull | package private, chưa có registry creds | mục 4 |
| `404 page not found` qua domain | Dokploy domain chưa tạo / sai host | kiểm tra domain app, phải khớp `hello.phucnn.io.vn` |
| `502` qua tunnel | app không listen `0.0.0.0:3000` | Dockerfile đã set `HOST=0.0.0.0` mặc định |
| redirect loop | bật HTTPS trong Dokploy | tắt HTTPS, cert None |
| deploy job skipped | `DEPLOY_ENABLED` chưa set | thêm variable `true` |
| deploy 403 | API key sai/thiếu scope | tạo lại key, kiểm tra `x-api-key` |
