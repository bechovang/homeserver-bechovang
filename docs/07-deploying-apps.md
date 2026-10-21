# 07 — Deploy app lên homelab (playbook)

> Áp dụng cho mọi app mới. Hai mẫu đang chạy: `hello` (Node service) và `site` (static nginx).
> Bổ sung ngày 22/10/2026 sau khi deploy `bechovang.github.io` tại `https://phucnn.io.vn`.

## 1. Kiến trúc một app

```
git push -> GitHub Actions (build image, push GHCR)
        -> job deploy: join tailnet tag:ci -> POST Dokploy API
        -> server: docker pull image -> Traefik router (domain) -> cloudflared -> Cloudflare
```

Server **không build**. Mọi app đều là image chạy 1 replica, `restart=always`, nằm trong `dokploy-network`.

## 2. Checklist thêm app mới

1. **Repo** có `Dockerfile` (non-root nếu được, `HEALTHCHECK`, `EXPOSE`).
2. **Workflow** copy từ `bechovang/bechovang.github.io/.github/workflows/deploy.yml` hoặc `homeserver-bechovang/.github/workflows/ci.yml`.
3. **GitHub repo** → secrets `DOKPLOY_URL`, `DOKPLOY_API_KEY`, `DOKPLOY_APP_ID`, `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET`; variable `DEPLOY_ENABLED=true`.
4. **Dokploy**: tạo app (Docker provider) → domain → deploy.
5. **DNS**: chỉ cần wildcard `*.phucnn.io.vn` (đã có); apex `phucnn.io.vn` cũng đã có CNAME.
6. **Monitoring**: thêm endpoint vào `infra/gatus/config.yaml` + alert Slack.
7. **Homepage**: thêm link vào `infra/homepage/services.yaml`.
8. Ghi lại ID app/domain vào mục 5 bên dưới.

## 3. Mẫu A — static site (nginx)

`bechovang.github.io` (24MB HTML/CSS/JS + ảnh, không build step):

```dockerfile
FROM nginx:1.29-alpine
COPY nginx.conf /etc/nginx/conf.d/site.conf
COPY --chown=nginx:nginx . /usr/share/nginx/html
HEALTHCHECK CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
```

- `.dockerignore`: `.git`, `.github`, `Dockerfile`, `.dockerignore`, `README.md`.
- `nginx.conf`: gzip css/js/svg, cache 7 ngày cho asset, `try_files $uri $uri/ $uri.html =404`.
- Port **80** (nginx), domain trỏ port 80 trong Dokploy.

## 4. Mẫu B — service Node

`apps/hello`:

- `node:24-alpine`, `USER node`, `HEALTHCHECK /health`, port **3000**.
- Export `createServer()` để test in-process, `node --test` trong CI trước khi build.
- Env runtime: `APP_VERSION` set trong Dokploy (`saveEnvironment`).

## 5. Tài nguyên đang chạy

| App | Repo | Image | Dokploy app | Domain | Port |
|---|---|---|---|---|---|
| `hello` | `bechovang/homeserver-bechovang` | `ghcr.io/bechovang/homeserver-bechovang/hello:latest` | `qJIbE8SOBTDgbFDSAr7dM` | `hello.phucnn.io.vn` | 3000 |
| `site` | `bechovang/bechovang.github.io` | `ghcr.io/bechovang/bechovang.github.io/site:latest` | `IeeRmR6pwlUiknGUr09vO` (`site-otvqqb`) | `phucnn.io.vn` + `www.phucnn.io.vn` | 80 |
| `gatus` | config trong repo này | `ghcr.io/twin/gatus:stable` | không (standalone) | `status.phucnn.io.vn` | 8080 |
| `homepage` | config trong repo này | `ghcr.io/gethomepage/homepage:latest` | không (standalone) | `home.phucnn.io.vn` + basicAuth | 3000 |
| `cloudflared` | – | `cloudflare/cloudflared:latest` | không (standalone) | – | – |

Project Dokploy: `personal` = `X816lHAiV3ff5RdD8iZ3O`, env `production` = `rzWPRXdKFPR83yuJ0QEfE`.

## 6. Tạo app bằng API (không cần UI)

```bash
# 1. app
curl -s -X POST http://100.83.245.0:3000/api/application.create   -H "x-api-key: $KEY" -H 'content-type: application/json'   -d '{"name":"site","appName":"site","environmentId":"rzWPRXdKFPR83yuJ0QEfE","sourceType":"docker"}'

# 2. image + registry (null/null khi package public)
curl -s -X POST .../api/application.saveDockerProvider   -d '{"applicationId":"<id>","dockerImage":"ghcr.io/<user>/<repo>/site:latest","username":null,"password":null,"registryUrl":null}'

# 3. domain (HTTPS OFF, cert none - TLS do Cloudflare)
curl -s -X POST .../api/domain.create   -d '{"host":"phucnn.io.vn","port":80,"https":false,"certificateType":"none","applicationId":"<id>","domainType":"application"}'

# 4. deploy
curl -s -X POST .../api/application.deploy -d '{"applicationId":"<id>"}'
```

OpenAPI đầy đủ: `GET /api/settings.getOpenApiDocument` với header `x-api-key`.

Lưu ý domain: **HTTPS OFF, Certificate None** — tunnel đã terminate TLS; bật HTTPS trong Dokploy sẽ sinh redirect loop.

## 7. Pipeline template

```yaml
env:
  IMAGE: ghcr.io/${{ github.repository }}/site
# build: docker/build-push-action -> $IMAGE:{latest,sha-<sha>}, cache gha
# deploy (push main + vars.DEPLOY_ENABLED):
#   tailscale/github-action@v4 (oauth, tags: tag:ci)
#   curl -X POST $DOKPLOY_URL/api/application.deploy -H "x-api-key: ..."
```

- `GITHUB_TOKEN` đủ để push GHCR (permissions `packages: write`).
- Image phải **public** hoặc Dokploy có registry credential; repo public → package public (đã kiểm chứng với `site`, pull anonymous thành công).
- CI đỏ → `needs` chặn build/deploy.

## 8. Kiểm tra sau deploy

```bash
docker ps --filter name=<app> --format '{{.Status}} | {{.Image}}'
curl -sS -o /dev/null -w '%{http_code}\n' https://<domain>/
curl -sS https://<domain>/health
```

Kỳ vọng: container `healthy`, HTTP 200/401 tuỳ app, gatus endpoint xanh sau ≤ 60s, Slack không báo.

## 9. Sự cố thường gặp

| Triệu chứng | Nguyên nhân | Fix |
|---|---|---|
| `unauthorized` khi pull | package private | đổi public hoặc thêm registry creds |
| 404 Traefik | domain chưa tạo / sai host | `domain.create`, so khớp host |
| 502 | app không listen đúng port/interface | kiểm tra `EXPOSE`, `0.0.0.0`, port domain |
| redirect loop | Dokploy bật HTTPS | HTTPS OFF, cert none |
| deploy job skip | thiếu `DEPLOY_ENABLED` | set variable `true` |
| join tailnet 400 | `tag:ci` chưa có trong `tagOwners` | sửa ACL |
| asset 404 | `try_files`/đường dẫn tuyệt đối | kiểm tra nginx.conf và base path |
