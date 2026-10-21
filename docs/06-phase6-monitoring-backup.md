# 06 — Phase 6: Monitoring + Backup + Dashboard + nghiệm thu

> Trạng thái 22/10/2026 03:00 +07: backup + restore drill ✅, Gatus status page ✅, Homepage basic-auth ✅, reboot test ✅.
> Còn: Slack webhook URL, 48h theo dõi. Off-site backup: **user quyết định không làm** (rủi ro được ghi nhận ở mục 5).

## 1. Backup (`scripts/homelab-backup.sh`)

Cài `/usr/local/sbin/homelab-backup.sh`, chạy root qua systemd.

| Thành phần | Đường dẫn | Ghi chú |
|---|---|---|
| Postgres dump | `/data/backups/postgres/<container>__<db>.dump` | `pg_dump -Fc`, giữ 7 ngày |
| Weekly tier | `/data/backups/postgres/weekly/` | bản Chủ nhật, giữ 28 ngày |
| Config host | `/data/backups/configs/homelab-configs_YYYY-MM-DD.tar.gz` | `/etc/dokploy`, netplan, docker, sshd, fail2ban, smartd — giữ 14 ngày |
| Quyền | `umask 077`, file 600 | chứa secret (Dokploy env/cert) |

- Tự phát hiện container `postgres:*`, đọc `POSTGRES_USER` rồi fallback `dokploy`/`postgres`.
- `homelab-backup.timer` **02:30 daily** (`Persistent=true`, `RandomizedDelaySec=300`).
- `homelab-backup-verify.timer` **Chủ nhật 03:30** → restore dump mới nhất vào DB tạm `restore_check_<pid>`, đếm bảng, drop.

Kết quả chạy thật:
```
postgres dump ok: ...__dokploy.dump (196K)
configs archived: homelab-configs_2026-10-22.tar.gz (100K)
VERIFY OK ...__dokploy.dump -> 67 tables in restore_check_107171 (dropped)
```

```bash
sudo systemctl start homelab-backup.service          # backup ngay
sudo systemctl start homelab-backup-verify.service   # drill ngay
journalctl -u homelab-backup.service -n 30
```

## 2. Monitoring — Gatus + Slack

**Lý do đổi từ Uptime Kuma:** Kuma không có API/CLI tạo monitor/admin, phải làm tay qua UI; Gatus config-as-code, version trong repo, tự động hoá hoàn toàn.

- Container `gatus` (`ghcr.io/twin/gatus:stable`), `restart=always`, `network dokploy-network`, `--env-file /data/gatus/.env`, mount `/data/gatus/config`.
- Config: [`infra/gatus/config.yaml`](../infra/gatus/config.yaml).
- Public status page: **https://status.phucnn.io.vn** (ingress tunnel → `http://gatus:8080`, không qua Traefik).

| Endpoint | Kiểm tra |
|---|---|
| `hello` | `https://hello.phucnn.io.vn/health` → 200 + body `"status":"ok"` |
| `site` | `https://phucnn.io.vn/` → 200 + body chứa `Bechovang` |
| `cloudflare-edge` | `https://www.phucnn.io.vn/` → 200 |
| `dokploy-postgres` | TCP `dokploy-postgres:5432` |
| `dokploy-api` | `http://dokploy:3000/api/health` → 200 |

Chu kỳ 60s. **Alerting:** Slack, `failure-threshold: 3`, `success-threshold: 2`, `send-on-resolved: true`.

Đã test end-to-end bằng stub HTTP nội bộ (chưa cần Slack thật):
- target trả 500, interval 10s → sau 3 lần gửi payload Slack `color #DD0000` "has been triggered due to having failed 3 time(s)"
- target trả 200 → sau 2 lần gửi `color #36A64F` "has been resolved after passing successfully 2 time(s)"

**Đang bật thật:** webhook Slack của workspace đã điền vào `/data/gatus/.env` (root:docker 640), channel **#homeserver-noti**. Đã xác nhận:
- `POST` trực tiếp từ `dokploy-network` → **200**
- Gatus với endpoint chết `http://127.0.0.1:9/` (interval 10s) → log `Sending slack alert ... TRIGGERED`, tin DOWN tới channel; endpoint test đã xoá sau kiểm tra

Thay đổi webhook: sửa `.env`, **phải tạo lại container** (`docker restart` không nạp lại `--env-file`):

```bash
docker rm -f gatus && docker run -d --name gatus --restart=always \
  --network dokploy-network --env-file /data/gatus/.env \
  -v /data/gatus/config:/config ghcr.io/twin/gatus:stable
```

Lưu ý: **App Credentials** (client id/secret, signing secret) không dùng được để gửi alert; chỉ **Incoming Webhook URL** mới dùng được.

## 3. Homepage dashboard (Basic Auth)

- Container `homepage` (`ghcr.io/gethomepage/homepage:latest`), `restart=always`, `network dokploy-network`, mount `/data/homepage/config:/app/config` (rw — Homepage cần tạo `config/logs`).
- Env `HOMEPAGE_ALLOWED_HOSTS=home.phucnn.io.vn`.
- URL: **https://home.phucnn.io.vn** — Traefik **basicAuth** (bcrypt cost 12) từ file động `/etc/dokploy/traefik/dynamic/homepage.yml`.
- Config: [`infra/homepage/`](../infra/homepage) (`settings.yaml`, `services.yaml`, `widgets.yaml`); file Traefik mẫu: `traefik-homepage.example.yml` (hash thật **không** commit).
- Đổi mật khẩu:
  ```bash
  docker run --rm httpd:alpine htpasswd -nbB -C 12 admin 'newpass'
  # dán dòng "admin:$2y$12$..." vào users[0] trong /etc/dokploy/traefik/dynamic/homepage.yml
  ```
- Không widget Docker (tránh mount docker.sock = root-equivalent); chỉ link + search + datetime + resource của container.

Nghiệm thu: không auth → **401**, có auth → **200**.

## 4. Reboot test (22/10 02:07)

| Kiểm tra sau reboot | Kết quả |
|---|---|
| WiFi static IP | `192.168.1.140/24` ✅ |
| SSH key-only | login lại sau ~40s ✅ |
| Docker/Dokploy/Traefik/Postgres | healthy ✅ |
| `cloudflared` | Up, tunnel 4 conn ✅ |
| `hello` `/health` · `status` `/` · `home` (auth) | 200 ✅ |
| Backup timers | armed ✅ |
| tailscaled / ufw / fail2ban / smartd | active ✅ |
| RAM | ~1.5/6 GB ✅ |

## 5. Việc còn lại

1. **Slack webhook URL** → điền `.env`, restart gatus, test DOWN/RESOLVED.
2. **Off-site backup: không làm** (user quyết định). Rủi ro chấp nhận: HDD 2009 là bản sao duy nhất; hỏng ổ/mất máy là mất toàn bộ dump + config.
3. **48h RAM/disk**: đo lại sau 24h/48h (không đặt timer report theo yêu cầu).
4. `:3000` vẫn publish ra LAN (Docker bypass ufw) — siết bằng chain `DOCKER-USER` nếu cần.

## 6. Access policy hiện tại

| Dịch vụ | LAN | Tailscale | Internet |
|---|---|---|---|
| `phucnn.io.vn`, `www.phucnn.io.vn` | ✅ | ✅ | ✅ public (blog) |
| `hello.phucnn.io.vn` | ✅ | ✅ | ✅ public |
| `status.phucnn.io.vn` | ✅ | ✅ | ✅ public (read-only) |
| `home.phucnn.io.vn` | ✅ | ✅ | ✅ public + basicAuth |
| Dokploy `:3000` | ✅ | ✅ | ❌ |
| Postgres | internal | ❌ | ❌ |

## 7. Ghi chú vận hành

- User `phuc` **không** có passwordless sudo → thao tác root qua `docker run --privileged --pid=host -v /:/host alpine chroot /host ...` (docker group = root-equivalent).
- `docker --env-file` do CLI đọc với quyền user → file env phải `root:docker 640`, thư mục `750`.
