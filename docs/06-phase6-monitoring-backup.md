# 06 — Phase 6: Monitoring + Backup + nghiệm thu

> Trạng thái 22/10/2026 02:10 +07: backup + restore drill ✅, status page ✅, reboot test ✅. Còn 48h theo dõi tài nguyên và alert webhook.

## 1. Backup (`scripts/homelab-backup.sh`)

Cài tại `/usr/local/sbin/homelab-backup.sh`, chạy root qua systemd.

| Thành phần | Đường dẫn | Ghi chú |
|---|---|---|
| Postgres dump | `/data/backups/postgres/<container>__<db>.dump` | `pg_dump -Fc`, giữ 7 ngày |
| Weekly tier | `/data/backups/postgres/weekly/` | bản Chủ nhật, giữ 28 ngày |
| Config host | `/data/backups/configs/homelab-configs_YYYY-MM-DD.tar.gz` | `/etc/dokploy`, netplan, docker, sshd, fail2ban, smartd — giữ 14 ngày |
| Quyền | `umask 077`, file 600 | chứa secret (Dokploy env/cert) |

- Tự phát hiện container `postgres:*` đang chạy, đọc `POSTGRES_USER` rồi fallback `dokploy`/`postgres`.
- Timer: `homelab-backup.timer` **02:30 daily** (`Persistent=true`, `RandomizedDelaySec=300`).
- Drill: `homelab-backup-verify.timer` **Chủ nhật 03:30** → restore dump mới nhất vào DB tạm `restore_check_<pid>`, đếm bảng, drop.

Kết quả lần chạy thật:
```
postgres dump ok: ...__dokploy.dump (196K)
configs archived: homelab-configs_2026-10-22.tar.gz (100K)
VERIFY OK ...__dokploy.dump -> 67 tables in restore_check_107171 (dropped)
```

Lệnh thủ công:
```bash
sudo systemctl start homelab-backup.service          # backup ngay
sudo systemctl start homelab-backup-verify.service   # drill ngay
journalctl -u homelab-backup.service -n 30
```

Chưa có off-site (rclone) — cần credential cloud; HDD 2009 vẫn là bản duy nhất nên đây là việc còn hở.

## 2. Monitoring — Gatus (thay Uptime Kuma)

**Lý do đổi:** Uptime Kuma không có API/CLI để tạo monitor và admin, phải làm tay qua UI ~10 phút; Gatus cấu hình bằng YAML, version trong repo, tự động hoá hoàn toàn. Cùng mục tiêu: check định kỳ + cảnh báo.

- Container `gatus` (`ghcr.io/twin/gatus:stable`), `--restart=always`, `--network dokploy-network`, mount `/data/gatus/config:/config`.
- Config: [`infra/gatus/config.yaml`](../infra/gatus/config.yaml) → `/data/gatus/config/config.yaml` trên server.
- Public status page: **https://status.phucnn.io.vn** (ingress riêng trong tunnel → `http://gatus:8080`, không qua Traefik).

| Endpoint | Kiểm tra |
|---|---|
| `hello` | `https://hello.phucnn.io.vn/health` → 200 + body `"status":"ok"` |
| `cloudflare-edge` | `https://phucnn.io.vn/` → 404 (Tunnel + Traefik sống) |
| `dokploy-postgres` | TCP `dokploy-postgres:5432` |
| `dokploy-api` | `http://dokploy:3000/api/health` → 200 |

Lặp 60s. Alerting đang **tắt** — bật bằng cách điền `alerting.telegram.token/id` (hoặc Discord/Slack) vào config rồi restart container:

```bash
docker restart gatus
```

## 3. Reboot test (22/10 02:07)

Lệnh: `systemctl reboot` (qua container privileged vì user không có sudo passwordless).

| Kiểm tra sau reboot | Kết quả |
|---|---|
| WiFi static IP | `192.168.1.140/24` ✅ |
| SSH key-only | login lại sau ~40s ✅ |
| Docker + Dokploy + Traefik + Postgres | healthy ✅ |
| `cloudflared` | Up, tunnel 4 conn ✅ |
| `hello` app | healthy, `/health` 200 ✅ |
| `gatus` + status page | 200 ✅ |
| Timer backup | next 02:32, verify 25/10 ✅ |
| tailscaled / ufw / fail2ban / smartd | active ✅ |
| RAM | 1541/6011 MB |

## 4. Việc còn lại

1. **Alert webhook** (Telegram/Discord) → bật alerting trong Gatus.
2. **Off-site backup** (rclone) — bắt buộc theo nguyên tắc "bản backup quan trọng phải ra khỏi máy".
3. **48h theo dõi** RAM/disk sau khi chạy đủ tải.
4. Homepage dashboard: **hoãn** — chưa có lớp auth; public hoá sẽ lộ toàn bộ link nội bộ. Làm sau khi có Cloudflare Access (service token/OTP) hoặc chỉ chạy LAN.
5. `:3000` vẫn publish ra LAN (Docker bypass ufw) — siết bằng chain `DOCKER-USER` nếu cần.

## 5. Access policy hiện tại

| Dịch vụ | LAN | Tailscale | Internet |
|---|---|---|---|
| `hello.phucnn.io.vn` | ✅ | ✅ | ✅ công khai |
| `status.phucnn.io.vn` | ✅ | ✅ | ✅ công khai (read-only) |
| Dokploy `:3000` | ✅ | ✅ | ❌ |
| Postgres | internal | ❌ | ❌ |
| Gatus container | internal | ❌ | qua status hostname |
