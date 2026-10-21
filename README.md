# 🏠 Home Server — bechovang

Biến PC cũ (i5-3470) thành **home server CI/CD**: deploy dự án cá nhân, self-hosted services, học DevOps.

> Cập nhật: 2026-10-21 · Phase 4 ✅ (`phucnn.io.vn` Active, tunnel 4 conn) · Phase 3 chờ tạo admin (DB **0 user**) · SSH key-only

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

## 🗂 Cấu trúc repo

```
docs/
  01-hien-trang-server.md      # Audit phần cứng + OS + mạng (SSH 21/10/2026)
  02-ke-hoach-trien-khai.md    # Kế hoạch 7 phase + kiến trúc + checklist nghiệm thu
  03-nhat-ky-cai-dat.md        # Nhật ký: đã cài gì, config nào đã áp dụng
  04-phase4-domain-cloudflare-tunnel.md  # Runbook domain + Cloudflare Tunnel (baseline đã audit)
configs/
  netplan-00-installer-config.example.yaml   # Đã sanitize password
deploy-CICD/
  Xây dựng Homelab CI CD.txt   # Tài liệu gốc (thảo luận ChatGPT làm nền)
```

## 📊 Tiến độ

| Phase | Nội dung | Trạng thái |
|---|---|---|
| 0 | Base config: static IP, ufw, fail2ban, smartd, timezone, `/data` | ✅ Xong |
| 1 | Docker Engine 29.9.2 + log rotation | ✅ Xong |
| 2 | Tailscale (`homelab-01` = 100.83.245.0) | ✅ Xong |
| 3 | Dokploy v0.30.8 — healthy, nhưng DB **0 user** (chưa tạo admin + 2FA) | 🔄 |
| 4 | Domain `phucnn.io.vn` + Cloudflare Tunnel — **Active**, `cloudflared` 4 conn, `*` → `dokploy-traefik:80` | ✅ Xong |
| 5 | App đầu tiên + CI/CD (GHCR → Dokploy) | ⏳ |
| 6 | Uptime Kuma + backup tự động + nghiệm thu | ⏳ |

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
