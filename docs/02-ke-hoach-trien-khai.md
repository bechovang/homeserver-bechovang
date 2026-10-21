# 02 — Kế hoạch triển khai Home Server CI/CD

> Phát hành: 21/10/2026 · Đã chốt với user: **WiFi-only (static IP)** · **Dokploy** · **sẽ mua domain** · **cài trực tiếp qua SSH**

## 1. Quyết định kiến trúc (đã chốt)

### Vì sao Dokploy?
- Web UI quản lý project/domain/DB/logs/rollback như "Vercel mini"
- Tích hợp Traefik reverse proxy + PostgreSQL + webhook auto-deploy
- API (`/api/application.deploy`) để GitHub Actions trigger deploy
- Ăn ~1–1.5GB RAM — chấp nhận được với 6GB usable (còn ~4.5GB cho apps + DB)
- Alternative đã cân nhắc: Docker Compose thuần (nhẹ hơn nhưng làm mọi thứ tay), Coolify (nặng hơn)

### Vì sao Cloudflare Tunnel?
- Mạng nhà VN thường **CGNAT/dynamic IP** → không port-forward được
- Tunnel là **outbound connection** — không mở bất kỳ inbound port nào trên router
- Free, có HTTPS, cache, DNS quản lý tập trung
- Yêu cầu duy nhất: 1 domain trỏ DNS về Cloudflare (user sẽ mua)

### Vì sao build trên GitHub Actions, không build trên server?
- i5-3470/6GB sẽ rất đau nếu vừa build vừa chạy services
- GitHub-hosted runner free cho repo cá nhân (2000 phút/tháng private, unlimited public)
- Server chỉ việc `docker pull` + run — đúng vai trò máy yếu

## 2. Kiến trúc đích

```
┌─────────────┐   git push    ┌──────────────────────────────┐
│ Laptop code │ ────────────> │ GitHub                       │
└─────────────┘               │  Actions: lint → test →      │
                              │  build image → push GHCR     │
                              └──────────────┬───────────────┘
                                             │ webhook (tailscale/github-action,
                                             │ ephemeral join tailnet)
                                             v
┌──────────────────────────────────────────────────────────────┐
│ HOME SERVER — homelab-01 (192.168.1.140 / ts 100.83.245.0)   │
│                                                              │
│  Ubuntu 26.04 ─ Docker Engine ─ Dokploy v0.30 ─ Traefik      │
│   ├── App 1 (Next.js)          ├── PostgreSQL 16 (Dokploy)   │
│   ├── App 2 (API)              ├── Uptime Kuma (:3001 LAN)   │
│   └── n8n (sau này)            └── backup → /data (HDD)      │
│                                                              │
│  cloudflared container ──outbound──> Cloudflare Edge         │
│         ^                                        │          │
│  Tailscale (SSH/admin only)           Internet HTTPS users    │
└──────────────────────────────────────────────────────────────┘
```

## 3. Phân vùng lưu trữ (đã áp dụng)

```
SSD 119GB (/)                    HDD 465GB (/data — ổ 2009, backup only!)
├── OS ~10GB                     ├── backups/
├── Docker images/volumes        │   ├── postgres/     # pg_dump định kỳ
├── PostgreSQL data (app)        │   ├── apps/         # volumes app
└── free ~80GB                   │   └── configs/      # dokploy, netplan, ...
                                 ├── uploads/
                                 └── archive/
```

Quy tắc: **DB chạy trên SSD** (nhanh, trẻ), **backup + file tĩnh trên HDD** (chậm, già). Backup quan trọng phải còn 1 bản **ngoài máy này** (GitHub repo / cloud).

## 4. RAM budget (6GB usable)

| Thành phần | Ước tính |
|---|---|
| Ubuntu + Docker + tailscaled + fail2ban | ~0.9 GB |
| Dokploy + dokploy-postgres + Traefik | ~1.0–1.5 GB |
| PostgreSQL (apps) | 0.3–0.7 GB |
| 1–2 app Node/Next | 0.5–1.5 GB |
| Uptime Kuma + Homepage + n8n (Phase 6+) | 0.5–1.0 GB |
| Thả nổi (cache/spike) | ~1.5 GB |

Giới hạn: mỗi service **1 replica**; không build trên server; tạm dừng app ít dùng; không GitLab/Prometheus-full/K8s. Nâng cấp ưu tiên số 1 nếu chật: **RAM → 16GB DDR3** (rẻ).

## 5. Lộ trình 7 phase

### ✅ Phase 0 — Base config (XONG 21/10)
- Timezone `Asia/Ho_Chi_Minh`, `apt full-upgrade`
- Netplan: static `192.168.1.140/24` trên WiFi, gw `192.168.1.1`, DNS 1.1.1.1/8.8.8.8; `eno1: optional: true` (fix wait-online)
- ufw: default deny in; allow 22, allow `192.168.1.0/24`, allow `tailscale0`
- fail2ban (jail sshd), smartd (short 02:00 daily, long 03:00 Chủ nhật)
- `/data/backups/{postgres,apps,configs}`, `/data/uploads`, `/data/archive`
- **TODO user:** reservation MAC WiFi ở router; rút USB rác

### ✅ Phase 1 — Docker (XONG 21/10)
- Docker Engine 29.9.2 từ repo chính thức (docker-ce, compose plugin, buildx)
- `daemon.json`: log rotation `json-file` max 10m × 3 (bảo vệ SSD)
- User `phuc` vào group `docker`

### ✅ Phase 2 — Tailscale (XONG 21/10)
- tailscaled 1.104.2, `--accept-dns=false --ssh --hostname=homelab-01`
- Tailnet IP **100.83.245.0**, tailnet `bechovang@`
- Truy cập mọi nơi: `ssh phuc@homelab-01` (Tailscale SSH)

### 🔄 Phase 3 — Dokploy (90% — đang chờ user tạo admin)
- [x] Review install script → chạy installer chính thức
- [x] Dokploy v0.30.8 + dokploy-postgres 16 + Traefik (80/443) — healthy
- [ ] **User: mở http://192.168.1.140:3000 → tạo admin (password mạnh)**
- [ ] Bật 2FA trong Settings
- [ ] Không bao giờ expose :3000 ra Internet

### ✅ Phase 4 — Domain + Cloudflare Tunnel (XONG 21/10 17:57)
- Domain `phucnn.io.vn` **Active** trên Cloudflare (NS `bill`/`zainab`), DNSSEC off, SSL mode **Full**
- Tunnel `dokploy-tunnel` `396142d9-e5f8-4418-9005-0611b9b011ce`, container `cloudflared` 4 conn QUIC healthy
- Ingress `phucnn.io.vn` + `*.phucnn.io.vn` → `http://dokploy-traefik:80`; CNAME `@`/`*` → cfargotunnel
- Nghiệm thu: host bất kỳ → **404 Traefik**, `http://` → **301 https**, không 502/1033
- Chi tiết lệnh, biến thể fallback và bảng lỗi: [`04-phase4-domain-cloudflare-tunnel.md`](04-phase4-domain-cloudflare-tunnel.md)

### ✅ Phase 5 — App đầu tiên + CI/CD (XONG 22/10 01:52)
- App `apps/hello` — Node 24 zero-dependency, non-root, healthcheck, 5 test (`node --test`)
- CI: `test → build GHCR (:latest + :sha-<sha>) → deploy` qua Tailscale OAuth `tag:ci` → `POST /api/application.deploy`
- Dokploy: project `personal` / app `hello` (Docker provider), domain `hello.phucnn.io.vn` (HTTPS off, cert none)
- Nghiệm thu: push → tự deploy ✅ · CI đỏ → build/deploy **skip** ✅ · rollback `sha-<sha>` ✅ · `/health` qua tunnel 200 ✅
- Chưa tạo PostgreSQL service — app hello không cần DB; làm khi app đầu tiên cần
- Chi tiết + ID tài nguyên: [`05-phase5-app-cicd.md`](05-phase5-app-cicd.md)

### 🔄 Phase 6 — Monitoring + Backup + Dashboard + nghiệm thu (22/10)
- **Backup** ✅ `homelab-backup.timer` 02:30 (pg_dump -Fc + configs tar, retention 7/28/14 ngày), drill Chủ nhật 03:30 → restore thật 67 bảng
- **Monitoring** ✅ **Gatus** thay Uptime Kuma (config-as-code) — `https://status.phucnn.io.vn`, 4 endpoint × 60s; alert **Slack #homeserver-noti** (đã test DOWN)
- **Homepage** ✅ `https://home.phucnn.io.vn` + Traefik **basicAuth** (bcrypt cost 12), config trong `infra/homepage/`
- **Reboot test** ✅ static IP, Docker, Dokploy, cloudflared, hello, gatus, homepage, timers tự lên sau ~40s
- Off-site backup: **user chọn không làm** (rủi ro đã ghi nhận). Còn: Slack URL + 48h RAM/disk
- Chi tiết: [`06-phase6-monitoring-backup.md`](06-phase6-monitoring-backup.md)

## 6. Checklist nghiệm thu (Definition of Done)

- [ ] Reboot máy: tự lên mạng WiFi, toàn bộ service tự start
- [ ] SSH qua Tailscale từ mạng ngoài (4G) OK
- [x] Push code lên main → CI xanh → app tự deploy bản mới
- [x] CI đỏ → KHÔNG deploy
- [x] App public qua domain HTTPS (Cloudflare Tunnel)
- [ ] PostgreSQL không reachable từ Internet/LAN ngoài Dokploy network
- [ ] Restart container → data không mất
- [ ] Restore 1 bản pg_dump thành công
- [x] Rollback về image cũ OK
- [ ] Uptime Kuma cảnh báo khi stop app
- [ ] RAM/disk trong ngưỡng sau 48h chạy

## 7. Rủi ro & đối sách

| Rủi ro | Đối sách |
|---|---|
| WiFi rớt sau reboot/sóng yếu | Netplan giữ cấu hình, wpa_supplicant tự retry; nếu cần → mua dây LAN cắm (máy có port) |
| IP .140 bị router cấp cho thiết bị khác | Reservation MAC ở router; theo dõi xung đột |
| HDD 2009 chết mất backup | smartd theo dõi + bắt buộc 1 bản off-server (GitHub/cloud/ổ cắm ngoài) |
| Mất điện | Sau này mua UPS; hiện tại: fsync bình thường, docker restart=always, DB dùng journal |
| Public IP động/CGNAT | Cloudflare Tunnel giải quyết (outbound) |
| Dokploy admin bị lộ | Chỉ LAN/Tailscale (ufw), password mạnh + 2FA, không tạo tunnel cho :3000 |
| PR lạ chạy code (nếu dùng self-hosted runner) | Không dùng self-hosted runner giai đoạn này |
