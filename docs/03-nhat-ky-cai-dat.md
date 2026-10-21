# 03 — Nhật ký cài đặt

> Ghi chú mọi thay đổi đã áp dụng lên server để tái hiện được khi cần. **Không chứa secret** (password/mã token đều ghi placeholder).

## 2026-10-21 — Ngày 1: Phase 0 → 3

### Phase 0 — Base config

**1. Timezone + update**
```bash
sudo timedatectl set-timezone Asia/Ho_Chi_Minh
sudo apt update && sudo apt full-upgrade -y   # không cần reboot
```

**2. Netplan — static IP qua WiFi** (backup bản cũ tại `/etc/netplan/00-installer-config.yaml.bak`)
- File đầy đủ (đã sanitize password): [`configs/netplan-00-installer-config.example.yaml`](../configs/netplan-00-installer-config.example.yaml)
- Điểm chính: `wlp2s0` tắt DHCP, set `192.168.1.140/24`, default route qua `192.168.1.1`, DNS `1.1.1.1, 8.8.8.8, 192.168.1.1`; `eno1` thêm `optional: true` → **fix lỗi `systemd-networkd-wait-online` timeout 2 phút mỗi lần boot**
- Apply bằng `sudo netplan generate && sudo netplan apply` — kết nối SSH không đứt (giữ nguyên IP)

**3. UFW**
```
Status: active · Default: deny (incoming), allow (outgoing)
- 22/tcp OpenSSH        ALLOW Anywhere      # SSH
- Anywhere              ALLOW 192.168.1.0/24   # LAN full access (Dokploy UI, DB nội bộ...)
- Anywhere on tailscale0 ALLOW Anywhere     # toàn bộ traffic qua Tailscale
```
⚠️ Lưu ý kiến thức: Docker publish port **đi qua iptables riêng, không qua UFW** — đừng tưởng UFW chặn được port container đã publish. Kiểm soát bằng cách không publish port không cần thiết.

**4. fail2ban** — cài qua apt, jail `sshd` mặc định, `systemctl enable --now fail2ban`

**5. smartd** — `/etc/smartd.conf`:
```
DEVICESCAN -a -s (S/../.././02|L/../../06/03)
```
= Short test 02:00 hằng ngày, Long test 03:00 Chủ nhật. `systemctl enable --now smartmontools`.

**6. Cây thư mục HDD**
```
/data/backups/postgres  /data/backups/apps  /data/backups/configs
/data/uploads  /data/archive    (owner phuc:phuc)
```

### Phase 1 — Docker Engine
- Repo chính thức `download.docker.com/linux/ubuntu resolute stable` (key `/etc/apt/keyrings/docker.asc`)
- `docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` → **Docker 29.9.2**
- `sudo usermod -aG docker phuc`
- `/etc/docker/daemon.json` — log rotation chống phình SSD:
```json
{
  "log-driver": "json-file",
  "log-opts": {"max-size": "10m", "max-file": "3"}
}
```
- Verify: `docker run --rm hello-world` ✅

### Phase 2 — Tailscale
- Cài qua `https://tailscale.com/install.sh` → **1.104.2**
- `sudo tailscale up --accept-dns=false --ssh --hostname=homelab-01`
- Kết quả: **tailnet IP `100.83.245.0`**, tailnet `bechovang@`, Tailscale SSH bật
- Từ đó: `ssh phuc@homelab-01` mọi nơi có Tailscale

### Phase 3 — Dokploy (đang dở — chờ user)
- Download + review `https://dokploy.com/install.sh` (408 dòng, dùng Docker sẵn có, không downgrade, check port 3000)
- Chạy installer → khởi tạo **Docker Swarm single-node**
- Services:
  - `dokploy` v0.30.8 — port 3000, healthy
  - `dokploy-postgres` (postgres:16) — internal
  - `dokploy-traefik` (traefik v3.6.25) — 80/443
- RAM sau cài: 1.6GB dùng / 4.3GB available ✅
- **Còn chờ user:** mở http://192.168.1.140:3000 tạo admin + bật 2FA

### Checkpoint cấu hình quan trọng trên server
| File | Vai trò |
|---|---|
| `/etc/netplan/00-installer-config.yaml` | Static IP WiFi (.bak là bản gốc DHCP) |
| `/etc/docker/daemon.json` | Log rotation |
| `/etc/smartd.conf` | Lịch test ổ đĩa |
| `/etc/fstab` | mount `/data` theo UUID (có sẵn từ installer) |
| `/swap.img` | Swap 4GB |

## Việc tiếp theo
1. User tạo Dokploy admin + 2FA → xong Phase 3
2. Domain: `bechovang.site` hết hạn → mua `phucnn.io.vn` (Tenten), chờ đổi NS → Phase 4 (Cloudflare Tunnel)
3. Chuẩn bị GitHub repo app mẫu → Phase 5 (CI/CD)
4. Uptime Kuma + backup cron → Phase 6

## 2026-10-21 (đợt 2) — Re-audit trước Phase 4

Đo trực tiếp qua SSH, đúng trạng thái lúc 11:56 +07:

| Kiểm tra | Kết quả |
|---|---|
| `dokploy` | v0.30.8 healthy, `0.0.0.0:3000` |
| **Số user trong DB Dokploy** | **0** → admin chưa tạo |
| `dokploy-traefik` | v3.6.25, container (không phải swarm service), publish 80/443 tcp+udp, nằm trong `dokploy-network` với alias `dokploy-traefik` (10.0.1.7) |
| `dokploy-postgres` | v16, chỉ `5432/tcp` nội bộ, không publish |
| Traefik entrypoints | `web:80`, `websecure:443` + `certResolver: letsencrypt`, email `test@localhost.com` |
| Middleware | `redirect-to-https` có sẵn, chỉ áp dụng khi domain bật HTTPS |
| RAM | 1587/6011 MB used, 4423 MB available |
| Disk | `/` 14G/116G · `/data` 2.1M/458G |
| ufw | active, deny incoming (Docker publish vẫn bypass) |
| Tailscale | 1.104.2, `100.83.245.0`, SSH bật |
| Egress Cloudflare | 200 trong 0.18s |
| Clock | NTP sync OK |
| Công cụ | curl, dig, jq, rsync, nc đủ |

Việc phát hiện:
1. `authorized_keys` rỗng + `PasswordAuthentication yes` → cần thêm SSH key rồi tắt password (Tailscale SSH làm đường lui).
2. `:3000` publish ra toàn LAN, ufw không chặn được (Docker iptables) → muốn giới hạn phải dùng chain `DOCKER-USER`.
3. ACME email là placeholder, không dùng được cho Let's Encrypt thật (không cần khi đi Cloudflare Tunnel).

## 2026-10-21 (đợt 3) — SSH hardening + đổi domain

### SSH: chuyển sang key-only
```bash
# trên máy Windows
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_homelab -N '' -C "admin@windows -> homelab-01"
ssh-copy-id tương đương: append ~/.ssh/id_ed25519_homelab.pub vào /home/phuc/.ssh/authorized_keys
```
Trên server:
```bash
sudo cp -n /etc/ssh/sshd_config.d/50-cloud-init.conf{,.bak}
sudo sh -c 'printf "PasswordAuthentication no\n" > /etc/ssh/sshd_config.d/50-cloud-init.conf'
sudo sshd -t && sudo systemctl reload ssh
```
- Lưu ý: `50-cloud-init.conf` khai báo `PasswordAuthentication yes` và sshd lấy **giá trị đầu tiên** gặp được → file `99-*.conf` **không** override được. Phải sửa chính file 50.
- Verify: `sshd -T | grep passwordauthentication` → `no`; login bằng key OK; login password bị từ chối.
- Alias Windows (`~/.ssh/config`): `homelab` → 192.168.1.140, `homelab-ts` → homelab-01.
- Đường lui: Tailscale SSH (`--ssh` đã bật từ Phase 2).

### Domain
- `bechovang.site`: **hết hạn**, bỏ. Tunnel CLI `bechovang` (`0d4b63f9-…`, 0 connection) là rác.
- `phucnn.io.vn`: registrar **Tenten**, NS hiện tại `ns-b1/b2/b3.tenten.vn`, đã delegation.
- Cloudflare nhận `.io.vn` — kiểm chứng bằng `dig NS` trên các zone `.io.vn` đang dùng `*.ns.cloudflare.com`.

## 2026-10-21 (đợt 4) — Phase 4 hoàn tất: domain + Cloudflare Tunnel

### DNS / delegation
- Tenten → NS `bill.ns.cloudflare.com` + `zainab.ns.cloudflare.com`
- 4 server VNNIC (`a–d.dns-servers.vn`) trả NS Cloudflare; zone **Active**, account `d89f4239433ffc169f910b495022c51f`, zone `9762390c91e2650af41e23eb9b0eb1e7`
- DNSSEC **off** (query DS không có bản ghi) → không cần xử lý
- Settings: `ssl=full`, `always_use_https=on`, `min_tls_version=1.2`

### Tunnel
- Tunnel `dokploy-tunnel` = `396142d9-e5f8-4418-9005-0611b9b011ce` (remote-managed)
- `cloudflared` chạy **ngoài** Dokploy (admin vẫn 0 user), vào đúng `dokploy-network`:
```bash
docker run -d --name cloudflared --restart=always --network dokploy-network \
  -e TUNNEL_TOKEN=<secret> cloudflare/cloudflared:latest tunnel --no-autoupdate run
```
- 4 connection QUIC (sin17/sin07/sin13/sin20), RAM ~17MB, precheck all PASS
- Ingress (API `PUT /accounts/{acct}/cfd_tunnel/{id}/configurations`): `phucnn.io.vn` + `*.phucnn.io.vn` → `http://dokploy-traefik:80`, catch-all `http_status:404`
- DNS: CNAME `@` và `*` → `396142d9-e5f8-4418-9005-0611b9b011ce.cfargotunnel.com` Proxied

### Nghiệm thu (đo từ ngoài, 17:56 +07)
| Test | Kết quả |
|---|---|
| `https://phucnn.io.vn`, `test/app/kuma.phucnn.io.vn` | **404** Traefik (đúng, chưa có route app) |
| `http://test.phucnn.io.vn` | **301** → `https://test.phucnn.io.vn/` |
| `dokploy-traefik` resolve trong `dokploy-network` | 10.0.1.7 ✅ |
| `http://dokploy-traefik:80` gọi từ network | 404 ✅ (không phải 502) |
| RAM sau thêm cloudflared | 1669 / 6011 MB |

### Công cụ / ghi chú
- Thao tác DNS + tunnel làm qua **Cloudflare REST API** với token scope: Zone DNS Edit, Zone Settings Edit, Zone Read, Account Tunnel Edit, Account Settings Read (token **không** lưu trong repo)
- MCP `cloudflare-api` khai báo tại `~/.omp/agent/mcp.json` (`https://mcp.cloudflare.com/mcp`, Bearer `${CLOUDFLARE_API_TOKEN}`); token hiện chưa có `user:read` → handshake trả 403 `insufficient_scope`; thêm quyền **User → User Details → Read** nếu muốn dùng MCP

Còn treo: Dokploy admin **0 user** → chặn Phase 5; nên chuyển `cloudflared` sang Dokploy quản lý sau khi có admin.

## 2026-10-22 (đợt 5) — Phase 5: app + CI/CD

- Dokploy admin đã tạo (`phuchcm2006@gmail.com`, 2FA bật — DB `user.two_factor_enabled = t`)
- Repo `bechovang/homeserver-bechovang` (public), app `apps/hello` zero-dependency
- CI: `node --test` → `docker/build-push-action` push `ghcr.io/bechovang/homeserver-bechovang/hello:{latest,sha-<sha>}` → job deploy join Tailscale (`tag:ci`) → `POST http://100.83.245.0:3000/api/application.deploy`
- Dokploy: project `personal` (`X816lHAiV3ff5RdD8iZ3O`), app `hello` (`qJIbE8SOBTDgbFDSAr7dM`), domain `hello.phucnn.io.vn` port 3000, HTTPS off
- GHCR package phải để **Public** thì server mới pull được (private → `unauthorized`)
- Tailscale ACL cần `"tagOwners": {"tag:ci": ["autogroup:admin"]}` trước khi OAuth client join được
- Nghiệm thu: `/health` 200, `version=latest`; test fail trên PR → build+deploy skip; rollback `:sha-0df7617…` chạy đúng rồi trả `:latest`
- GitHub secrets: `DOKPLOY_URL`, `DOKPLOY_API_KEY`, `DOKPLOY_APP_ID`, `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET`; variable `DEPLOY_ENABLED=true`
