# 04 — Phase 4: Domain `phucnn.io.vn` + Cloudflare Tunnel (runbook)

> Baseline đo trực tiếp trên server lúc **21/10/2026 11:56 +07** qua SSH.
> `TUNNEL_ID` / `TUNNEL_TOKEN` điền sau khi tạo tunnel; token là secret, không commit.
>
> ⚠️ `bechovang.site` **đã hết hạn** — mọi cấu hình cũ liên quan domain đó bỏ đi. Tunnel CLI `bechovang` (0 connection) là rác, xoá sau khi Phase 4 xong.

## 0. Trạng thái domain (kiểm tra thật, 21/10 12:05 +07)

| Hạng mục | Kết quả |
|---|---|
| Tên miền | **`phucnn.io.vn`** (mua mới) |
| Registrar / DNS hiện tại | **Tenten** — `ns-b1.tenten.vn`, `ns-b2.tenten.vn`, `ns-b3.tenten.vn` |
| Trạng thái DNS | Đã delegation, SOA trả lời bình thường → chỉ cần đổi NS |
| Cloudflare có nhận `.io.vn`? | **Có** — kiểm chứng: `cloudflare.io.vn`, `test.io.vn`, `google.io.vn` đều đang dùng `*.ns.cloudflare.com` |
| Cấu trúc zone | `phucnn.io.vn` là domain đăng ký hợp lệ (`io.vn` là public suffix trong PSL) → CF coi là 1 zone, Universal SSL phủ `phucnn.io.vn` + `*.phucnn.io.vn` |

Hostname dự kiến: `hello.phucnn.io.vn` (test Phase 4) · `app.phucnn.io.vn` (Phase 5) · `kuma.phucnn.io.vn` (Phase 6).

## 1. Baseline server (không phải giả định)

| Hạng mục | Giá trị thực |
|---|---|
| Dokploy | `dokploy/dokploy:v0.30.8`, healthy, `0.0.0.0:3000` |
| **User trong DB Dokploy** | **0** → **admin chưa tạo** (chặn Phase 3 + Phương án A) |
| Traefik | `v3.6.25`, container standalone, publish 80/443 tcp+udp |
| Network Traefik | `dokploy-network`, IP `10.0.1.7`, alias **`dokploy-traefik`** ✅ |
| Postgres | `v16`, chỉ `5432/tcp` nội bộ ✅ |
| Entrypoints | `web:80`, `websecure:443` + `certResolver: letsencrypt`, email `test@localhost.com` |
| Middleware | `redirect-to-https` có sẵn, chỉ áp khi domain bật HTTPS |
| RAM | 1587/6011 MB used · 4423 MB available |
| Disk | `/` 14G/116G · `/data` 2.1M/458G |
| ufw | active deny-in, Docker publish **bypass ufw** |
| Tailscale | 1.104.2, `100.83.245.0`, SSH bật |
| SSH | **pubkey-only** (đã tắt password 21/10 12:00) |
| Egress CF | 200 trong 0.18s · NTP sync OK |

## 2. Kiến trúc chốt

```
Internet ──HTTPS──> Cloudflare Edge ──tunnel(QUIC)──> cloudflared ──HTTP──> dokploy-traefik:80 ──> app
```

| Hạng mục | Chọn |
|---|---|
| Tunnel | 1 tunnel `dokploy-tunnel` (remote-managed, token) |
| Public hostname | `*.phucnn.io.vn` → `http://dokploy-traefik:80` |
| TLS | Cloudflare Edge, mode **Full** + Always Use HTTPS |
| Dokploy domain | **HTTPS OFF · Certificate None** |
| Admin `:3000` | không public (LAN + Tailscale) |

## 3. Cloudflare — DNS (browser, làm trước)

1. `dash.cloudflare.com` → **Add a site** → `phucnn.io.vn` → plan **Free**.
2. Cloudflare trả 2 NS dạng `xxx.ns.cloudflare.com` / `yyy.ns.cloudflare.com`.
3. **Tenten** → quản lý tên miền `phucnn.io.vn` → **Nameservers / DNS** → chọn *dùng nameserver khác* → nhập đúng 2 NS Cloudflare → lưu.
4. Chờ **Active** (5 phút – 24h, thường < 1h). Kiểm tra từ server:
   ```bash
   dig +short NS phucnn.io.vn      # phải ra *.ns.cloudflare.com
   ```
5. **SSL/TLS → Overview → `Full`** (Flexible → loop, Full Strict → 526).
6. **SSL/TLS → Edge Certificates**: `Always Use HTTPS` ON, `Minimum TLS 1.2`.

## 4. Cloudflare — tunnel + route

1. **Zero Trust → Networks → Tunnels → Create a tunnel** → **Cloudflared** → name `dokploy-tunnel` → Save.
2. Copy **`TUNNEL_TOKEN`** (`eyJhIjoi...`) và **`TUNNEL_ID`**.
3. **DNS → Records → Add record** (wildcard bắt buộc tạo tay):

   | Type | Name | Content | Proxy |
   |---|---|---|---|
   | CNAME | `*` | `TUNNEL_ID.cfargotunnel.com` | Proxied |
   | CNAME | `@` | `TUNNEL_ID.cfargotunnel.com` | Proxied (chỉ khi cần apex) |

4. **Tunnels → `dokploy-tunnel` → Public Hostname → Add**: Subdomain `*`, Domain `phucnn.io.vn`, Path trống, Type `HTTP`, URL **`dokploy-traefik:80`**.

## 5. Server — Dokploy Application (Phương án A, đã chốt)

Điều kiện: **phải có admin Dokploy** (hiện 0 user).

1. Project `infra` → **Application** `cloudflared`.
2. **General → Provider = Docker**, Docker Image = `cloudflare/cloudflared:latest`.
3. **Environment**: `TUNNEL_TOKEN=<token>`.
4. **Advanced → Arguments** — đúng thứ tự, mỗi dòng 1 entry: `tunnel`, `run`.
5. Deploy → **Logs** phải có `Registered tunnel connection connIndex=0..3`.

Kiểm tra từ SSH:

```bash
sudo docker service ls | grep cloudflared
sudo docker service logs --tail 30 $(sudo docker service ls -q -f name=cloudflared)
```

### Fallback B (chỉ khi A không tới được Traefik)

```bash
docker run -d --name cloudflared --restart=always --network host \
  cloudflare/cloudflared:latest tunnel --no-autoupdate run --token 'TUNNEL_TOKEN'
```
Public hostname đổi URL thành `http://127.0.0.1:80`. Không chạy đồng thời A và B.

## 6. Nghiệm thu

Từ **máy ngoài LAN** (4G):

```bash
dig +short test.phucnn.io.vn                 # IP Cloudflare
curl -sS -o /dev/null -w '%{http_code}\n' https://test.phucnn.io.vn   # 404 Traefik
curl -sSI http://test.phucnn.io.vn | grep -i '^location'              # 301 -> https
```

- [ ] `dig` trả IP Cloudflare, không lộ IP nhà
- [ ] `https://test.phucnn.io.vn` → **404** (không 502/1033/530)
- [ ] `http://` → 301 https
- [ ] Tunnel dashboard **Healthy**, đủ 4 `connIndex`
- [ ] Từ Internet: `:3000`, `:80`, `:443` của `192.168.1.140` timeout
- [ ] RAM tăng < 100MB

| Triệu chứng | Nguyên nhân | Fix |
|---|---|---|
| 502 | không tới được `dokploy-traefik:80` | chuyển B |
| 1033 | connector chưa chạy / token sai | xem log `Unauthorized` |
| redirect loop | domain Dokploy bật HTTPS | HTTPS OFF, Cert None |
| 522/526 | SSL mode sai | đặt **Full** |
| 404 mọi host | Host trong Dokploy khác host gọi | khớp tuyệt đối |
| 1016 / NS chưa active | chưa đổi NS ở Tenten | chờ propagate, `dig NS` |

## 7. Rollback

Xoá app `cloudflared` trong Dokploy (hoặc `docker rm -f cloudflared`); xoá public hostname + CNAME `*`. LAN/Tailscale không đổi.

## 8. Giới hạn Free plan

- Upload ≤ 100MB/request.
- Universal SSL phủ `phucnn.io.vn` + `*.phucnn.io.vn` (1 cấp). `api.staging.phucnn.io.vn` **không** có cert → dùng `staging-api.phucnn.io.vn`.
- Tunnel chỉ HTTP/HTTPS; SSH/DB đi Tailscale. WebSocket chạy sẵn.
- IP client thật: header `CF-Connecting-IP`.

## 9. Đã làm trong đợt này: SSH hardening (21/10 12:00)

| Bước | Kết quả |
|---|---|
| Tạo key `~/.ssh/id_ed25519_homelab` (ed25519, không passphrase) | ✅ |
| Cài public key vào `phuc:~/.ssh/authorized_keys` (700/600) | ✅ |
| Test `ssh -i ... -o BatchMode=yes` | ✅ `KEY_LOGIN_OK` |
| Sửa `/etc/ssh/sshd_config.d/50-cloud-init.conf` → `PasswordAuthentication no` (file này thắng mọi `99-*` vì được đọc trước) | ✅ `sshd -t` OK + reload |
| Test lại: password bị từ chối — `No supported authentication methods (server sent: publickey)` | ✅ |
| Backup | `/etc/ssh/sshd_config.d/50-cloud-init.conf.bak` |
| Alias trên Windows | `ssh homelab` (LAN) · `ssh homelab-ts` (Tailscale) |

Đường lui nếu mất key: **Tailscale SSH** (`ssh phuc@homelab-01`), đang bật.

## 10. Việc còn treo (không thuộc Phase 4)

1. **Dokploy admin = 0** → tạo tại `http://192.168.1.140:3000` + bật 2FA.
2. `:3000` publish ra toàn LAN, ufw không chặn (Docker iptables) → giới hạn bằng chain `DOCKER-USER` nếu cần.
3. DHCP reservation MAC `ae:ed:5c:bc:d3:33` chưa xác nhận ở router.
4. ACME email vẫn là `test@localhost.com` (không ảnh hưởng tunnel).
5. Xoá tunnel rác `bechovang` (ID `0d4b63f9-…`) và `~/.cloudflared/config.yml` cũ trên Windows.

## 11. Kết quả thực thi — 21/10/2026 17:57 +07

| Hạng mục | Kết quả |
|---|---|
| NS | `bill.ns.cloudflare.com` + `zainab.ns.cloudflare.com`, zone **Active** |
| DNSSEC | off (không có DS) |
| SSL | mode `full`, always_use_https `on`, min TLS `1.2` |
| Tunnel | `dokploy-tunnel` `396142d9-e5f8-4418-9005-0611b9b011ce`, 4 conn QUIC |
| Container | `cloudflared` `--network dokploy-network`, `--restart=always`, RAM ~17MB |
| Ingress | apex + `*` → `http://dokploy-traefik:80`, fallback 404 |
| DNS record | CNAME `@`, `*` → `<TUNNEL_ID>.cfargotunnel.com` Proxied |
| `https://test.phucnn.io.vn` | **404** Traefik ✅ |
| `http://test.phucnn.io.vn` | **301** → https ✅ |

Lệnh đã dùng (token là secret, thay `<TOKEN>`):
```bash
docker run -d --name cloudflared --restart=always --network dokploy-network \
  -e TUNNEL_TOKEN='<TOKEN>' cloudflare/cloudflared:latest tunnel --no-autoupdate run
```
Fallback B trong mục 5 **không cần** — đường `dokploy-traefik:80` chạy tốt.

Việc còn lại của Phase 4: khi có admin Dokploy thì tạo Application `cloudflared` (Provider Docker) và xoá container standalone, hoặc giữ nguyên.
