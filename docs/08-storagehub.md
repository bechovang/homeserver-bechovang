# 08 — StorageHub: triển khai đa container (Dokploy Compose)

> Deploy 22/10/2026. Repo `bechovang/StorageHub` (branch `master`, PR #50 thêm hạ tầng).
> URL: **https://storagehub.phucnn.io.vn** — Spring Boot + React + MySQL 8.4.

## 1. Kiến trúc

```
Cloudflare (storagehub.phucnn.io.vn) → Tunnel → Traefik
        └─ compose "storagehub" (appName storagehub-myzyte)
             ├─ frontend  nginx 1.29  — SPA build sẵn, proxy /api + /actuator/health → backend:8080
             ├─ backend   Spring Boot 4.1.1 / Java 21 (JRE alpine, non-root)
             └─ db        mysql:8.4   — volume storagehub-myzyte_mysql_data (SSD)
```

- Không build trên server: CI push image lên GHCR, compose chỉ `image:` + pull.
- FE/BE cùng origin → không cần CORS (JWT gửi qua header `Authorization`).
- MySQL data nằm ở Docker volume trên SSD; backup ra `/data/backups/mysql` (HDD).

## 2. Tài nguyên

| Hạng mục | Giá trị |
|---|---|
| Dokploy compose | `8heFNSbnt-TR7XiX23Cfi` (`storagehub`, appName `storagehub-myzyte`) |
| Project/env | `personal` / `production` (`rzWPRXdKFPR83yuJ0QEfE`) |
| Domain | `storagehub.phucnn.io.vn` = `OoCAz5AWqf--1GkxXcAEv`, service `frontend`, port 80, HTTPS off |
| Image backend | `ghcr.io/bechovang/storagehub/backend:{latest,sha-<sha>}` |
| Image frontend | `ghcr.io/bechovang/storagehub/frontend:{latest,sha-<sha>}` |
| GitHub PR | #50 (`be/phuc-ci` → `master`) |

## 3. File hạ tầng trong repo (PR #50)

| File | Vai trò |
|---|---|
| `backend/Dockerfile` | multi-stage `maven:3.9-eclipse-temurin-21` → `eclipse-temurin:21-jre-alpine`, `USER app`, `MaxRAMPercentage=70`, healthcheck actuator |
| `frontend/Dockerfile` | `node:22-alpine` build → `nginx:1.29-alpine`, healthcheck |
| `frontend/nginx.conf` | SPA fallback, proxy `/api/` → `backend:8080`, cache asset 7d, `client_max_body_size 10m` |
| `docker-compose.prod.yml` | 3 service + volume; **không có `build:`** |
| `.github/workflows/deploy.yml` | PR: `mvn test` + `npm ci && build`; push master: build/push 2 image → Tailscale → `compose.deploy` |

Nhánh `be/phuc` đang có commit riêng (payment/role) nên hạ tầng tách sang `be/phuc-ci` để tránh force-push/đụng việc của team.

## 4. Biến môi trường (Dokploy Compose → Environment)

| Biến | Ghi chú |
|---|---|
| `DB_NAME` / `DB_USER` / `DB_PASS` | DB `storagehub`, user riêng, mật khẩu random 24 byte |
| `MYSQL_ROOT_PASSWORD` | random, chỉ dùng nội bộ |
| `JWT_SECRET` | Base64 48 byte (`openssl rand -base64 48`) |
| `SPRING_PROFILES_ACTIVE` | **`dev`** → Flyway chạy seed demo V2–V5 |
| `PAYOS_ENABLED` | `true` |
| `PAYOS_CLIENT_ID` / `PAYOS_API_KEY` / `PAYOS_CHECKSUM_KEY` | từ my.payos.vn (kênh DEMO-MARKETPLACE) |
| `PAYOS_RETURN_URL` / `PAYOS_CANCEL_URL` | `https://storagehub.phucnn.io.vn/payment` |
| `PAYOS_WEBHOOK_URL` | `https://storagehub.phucnn.io.vn/api/v1/payments/webhooks/payos` |

Secret không nằm trong repo; nằm trong Dokploy DB (và trong bản backup configs `/data/backups/configs`).

## 5. Tài khoản demo (profile dev — CÔNG KHAI)

| Role | Email | Password |
|---|---|---|
| SYSTEM_ADMIN | `nam@demo.storagehub.vn` | `password` |
| BUSINESS_OPS | `hang@demo.storagehub.vn` | `password` |
| FACILITY_MANAGER | `minh@demo.storagehub.vn` | `password` |
| STAFF | `tuan@demo.storagehub.vn` | `password` |
| CUSTOMER | `lan@demo.storagehub.vn`, `trang@demo.storagehub.vn` | `password` |

⚠️ Đây là **quyết định có chủ đích** (phương án C): site public để demo đồ án, chấp nhận ai cũng đăng nhập được admin. Không dùng dữ liệu thật. Muốn siết: Cloudflare Access / basic auth ở nginx / đổi mật khẩu toàn bộ user sau seed.

## 6. CI/CD

- PR → chỉ test (`mvn -B test`, `npm ci && npm run build`), không push image.
- Push `master` + `DEPLOY_ENABLED=true` → build 2 image GHCR (`:latest` + `:sha-<commit>`) → join tailnet `tag:ci` → **pin compose sang `:sha-<commit>`** (`compose.update`) → `compose.deploy`.
- Vì sao phải pin: `docker compose up -d` với `:latest` không recreate container khi tag không đổi. Pin sha đảm bảo mỗi commit tạo container mới và rollback chỉ là chạy lại workflow cũ/đổi tag.
- Rollback: trong Dokploy đổi tag compose sang `:sha-<commit>` cũ rồi deploy, hoặc `compose.update` rồi `compose.deploy`.
- Secrets repo: `DOKPLOY_URL`, `DOKPLOY_API_KEY`, `DOKPLOY_COMPOSE_ID`, `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET`, `SLACK_WEBHOOK_URL`.
- Job `notify` (`always()`, bỏ qua PR) gửi Slack sau mỗi run: icon OK/FAILED, repo@sha, branch, actor, kết quả từng job, link run.

## 7. Backup & restore

`scripts/homelab-backup.sh` đã mở rộng: mỗi container `mysql:*` → `mysqldump --single-transaction --routines --triggers` từng DB (trừ schema hệ thống) → `/data/backups/mysql/<container>__<db>.sql.gz`, giữ 7 ngày + weekly 28 ngày. Drill `--verify` restore dump MySQL mới nhất vào DB tạm rồi drop.

```bash
sudo systemctl start homelab-backup.service
sudo systemctl start homelab-backup-verify.service
```

## 8. Nghiệm thu (22/10)

| Test | Kết quả |
|---|---|
| `GET /` | 200, title `StorageHub · Self-Storage Facility Management` |
| `GET /actuator/health` | 200 `{"groups":["liveness","readiness"],"status":"UP"}` |
| `POST /api/v1/auth/login` (admin seed) | 200 + JWT, `landingRoute:/users` |
| `GET /api/v1/users` (admin token) | 200, 7 user seed |
| `GET /api/v1/units` (customer token) | 200, có unit LOCK-2… |
| `POST /api/v1/payments/webhooks/payos` rỗng | 400 (đúng — thiếu chữ ký) |
| containers | db healthy, backend healthy, frontend healthy |

## 9. Vấn đề đã biết

1. **PayOS `confirm-webhook` (đã sửa).** PayOS xác thực URL bằng cách POST một payload mẫu **có chữ ký hợp lệ** với `orderCode = 123`. Backend cũ coi orderCode ngoài dải `100000+paymentId` là lỗi → trả 400 → dashboard báo "Webhook url invalid". Đã sửa: orderCode lạ + chữ ký hợp lệ ⇒ coi là probe, bỏ qua, trả `{"code":"00","desc":"success"}` (200); chữ ký sai vẫn 400. Đổi hành vi ở `PayOsPaymentGateway.verifyWebhook` + `PaymentServiceImpl.handlePayOsWebhook`, test `ignoresForeignOrderCodeAsProbe`.
2. **Attachment upload chưa tồn tại** (Sprint 2): seed có `*PhotoUrl` `/storage/contracts/...` nhưng không có endpoint/static mapping → ảnh hợp đồng 404.
3. `springdoc` vẫn bật (`/swagger-ui.html`) — có thể tắt bằng `SPRINGDOC_API_DOCS_ENABLED=false` nếu muốn.
4. JVM heap mặc định 70% RAM container; container chưa giới hạn RAM nên JVM thấy host 6GB → có thể thêm `mem_limit` nếu cần.
5. Dev seed chạy migration mỗi lần DB trống — tạo lại volume sẽ reset toàn bộ dữ liệu demo.
