# 🏠 Home Server — bechovang

Biến PC cũ (i5-3470) thành **home server CI/CD**: deploy dự án cá nhân, self-hosted services, học DevOps.

> Cập nhật: 2026-10-22 · Phase 5 ✅ (CI/CD + rollback) · Phase 6 🔄 — backup+restore drill ✅, status page ✅, reboot test ✅; còn alert webhook, off-site, 48h

## 📌 Thông tin nhanh

| | |
|---|---|
| **Hostname** | `bechovang-homeserver` / Tailscale: `homelab-01` |
| **IP LAN (static)** | `192.168.1.140` (WiFi Intel AC-8265) |
| **IP Tailscale** | `100.83.245.0` — tailnet `bechovang@` |
| **SSH** | `ssh homelab` (LAN) · `ssh homelab-ts` (Tailscale) — **key-only**, password đã tắt 21/10 |
| **Dokploy UI** | `http://192.168.1.140:3000` — **chỉ qua LAN/Tailscale, không public** |
| **OS** | Ubuntu 26.04.1 LTS (kernel 7.0, UEFI) |
| **Phần cứng** | i5-3470 · 8GB DDR3 (~6GB usable) · SSD 119GB · HDD 500GB |
| **Domain** | `phucnn.io.vn` — NS Cloudflare (`bill`/`zainab`), Cloudflare Tunnel live, SSL **Full** |
| **App demo** | `https://hello.phucnn.io.vn` — CI/CD từ repo `bechovang/homeserver-bechovang` |
| **Status page** | `https://status.phucnn.io.vn` — Gatus, 4 endpoint × 60s |
| **Backup** | `/data/backups` — timer 02:30 daily, restore drill CN 03:30 |

## 🗂 Cấu trúc repo

```
docs/
  01-hien-trang-server.md      # Audit phần cứng + OS + mạng (SSH 21/10/2026)
  02-ke-hoach-trien-khai.md    # Kế hoạch 7 phase + kiến trúc + checklist nghiệm thu
  03-nhat-ky-cai-dat.md        # Nhật ký: đã cài gì, config nào đã áp dụng
  04-phase4-domain-cloudflare-tunnel.md  # Runbook domain + Cloudflare Tunnel (baseline đã audit)
  05-phase5-app-cicd.md        # Runbook app mẫu + GitHub Actions → GHCR → Dokploy
  06-phase6-monitoring-backup.md  # Backup + restore drill + Gatus + reboot test
configs/
  netplan-00-installer-config.example.yaml   # Đã sanitize password
apps/
  hello/                        # App mẫu zero-dependency (Node 24, Dockerfile non-root có healthcheck)
.github/workflows/ci.yml        # test → build GHCR → deploy qua Tailscale
scripts/
  homelab-backup.sh             # pg_dump + configs tar + restore drill (systemd timer)
  systemd/                      # homelab-backup{,-verify}.{service,timer}
infra/
  gatus/config.yaml             # status page config-as-code
deploy-CICD/
  Xây dựng Homelab CI CD.txt   # Tài liệu gốc (thảo luận ChatGPT làm nền)
```

## 📊 Tiến độ

| Phase | Nội dung | Trạng thái |
|---|---|---|
| 0 | Base config: static IP, ufw, fail2ban, smartd, timezone, `/data` | ✅ Xong |
| 1 | Docker Engine 29.9.2 + log rotation | ✅ Xong |
| 2 | Tailscale (`homelab-01` = 100.83.245.0) | ✅ Xong |
| 3 | Dokploy v0.30.8 — admin `phuchcm2006@gmail.com` + 2FA | ✅ Xong |
| 4 | Domain `phucnn.io.vn` + Cloudflare Tunnel — **Active**, `cloudflared` 4 conn, `*` → `dokploy-traefik:80` | ✅ Xong |
| 5 | App `hello` + CI/CD — push → test → GHCR → Dokploy tự deploy; CI đỏ chặn deploy; rollback `sha-…` OK | ✅ Xong |
| 6 | Backup 02:30 + restore drill ✅ · Gatus `status.phucnn.io.vn` ✅ · reboot test ✅ · còn alert webhook + off-site + 48h | 🔄 |

## 🎯 Kiến trúc đích

```
[Laptop code] → git push → [GitHub Actions: test + build] → [GHCR image]
                                                          ↓ webhook qua Tailscale
[Home Server: Ubuntu 26.04 + Docker + Dokploy + Traefik]
   ├─ PostgreSQL (data trên SSD, backup ra HDD /data)
   ├─ Cloudflare Tunnel ← Internet HTTPS (không mở port router)
   ├─ Uptime Kuma + Homepage + n8n (giai đoạn sau)
   └─ Tailscale (SSH + quản trị riêng tư)
```

**Nguyên tắc với 6GB RAM usable:** build trên GitHub runner (free), máy nhà chỉ pull image + chạy app. Không Redis. Không K8s giai đoạn này.

## 🔐 Chính sách truy cập

| Dịch vụ | LAN | Tailscale | Internet |
|---|---|---|---|
| SSH | ✅ | ✅ | ❌ |
| Dokploy admin (:3000) | ✅ | ✅ | ❌ |
| PostgreSQL | internal only | ❌ | ❌ |
| Website/API production | ✅ | ✅ | ✅ (qua Cloudflare Tunnel, HTTPS) |
