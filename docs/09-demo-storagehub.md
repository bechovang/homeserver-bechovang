# 09 — Kịch bản demo StorageHub (từ đầu đến cuối)

> Dùng cho buổi demo đồ án. Mọi bước dưới đây đã được kiểm chứng trên **https://storagehub.phucnn.io.vn** (24/10/2026).
> Tổng thời lượng gợi ý: **25–30 phút**. Có thể cắt bớt role tuỳ thời gian.

---

## 0. Chuẩn bị trước demo (15 phút)

### 0.1. Tab/thiết bị

| Chuẩn bị | Ghi chú |
|---|---|
| Chrome profile 1 | Customer (`lan@`) — dùng để đặt kho |
| Chrome profile 2 | Staff / FM / BOPS / Admin (đăng xuất–đăng nhập lần lượt) |
| Tab phụ | `https://status.phucnn.io.vn`, `https://github.com/bechovang/StorageHub/actions`, Slack `#homeserver-noti` |
| Kết nối | Internet ổn định; PayOS cần mạng ra ngoài |

### 0.2. Tài khoản seed (mật khẩu chung `password`)

| Role | Email | Dùng để demo |
|---|---|---|
| CUSTOMER | `lan@demo.storagehub.vn` | đặt kho, thanh toán, hợp đồng, check-in pass |
| CUSTOMER | `trang@demo.storagehub.vn` | (tuỳ chọn) test trùng kho → 409 |
| STAFF | `minh@demo.storagehub.vn` | task board, lịch trực |
| FACILITY_MANAGER | `tuan@demo.storagehub.vn` | facility overview, quản lý kho, ca trực, activity log |
| BUSINESS_OPS | `hang@demo.storagehub.vn` | KPI, báo cáo, chính sách |
| SYSTEM_ADMIN | `nam@demo.storagehub.vn` | quản trị user, phân quyền, audit |

### 0.3. Kiểm tra nhanh trước khi bắt đầu

```bash
curl -s https://storagehub.phucnn.io.vn/actuator/health      # {"status":"UP"}
curl -s -o /dev/null -w '%{http_code}\n' https://storagehub.phucnn.io.vn/
```

Mở sẵn trang status: **7/7 endpoint xanh**. Nếu có endpoint đỏ, xem mục 8.

---

## 1. Mở màn: kiến trúc 30 giây

Nói ngắn gọn khi mở trang:

> “Ứng dụng chạy trên PC cũ tại nhà: Cloudflare Tunnel → Traefik → 3 container (React+nginx, Spring Boot, MySQL). Không mở port router, không lộ IP. Code push lên GitHub là tự build image và deploy, không build trên server.”

Có thể mở sơ đồ trong `docs/08-storagehub.md` nếu cần.

---

## 2. Kịch bản A — Khách hàng (8–10 phút)

### A1. Đăng nhập & landing theo vai trò (1 phút)

1. Mở `https://storagehub.phucnn.io.vn` → tự chuyển `/login`.
2. Đăng nhập `lan@demo.storagehub.vn` / `password`.
3. Hệ thống điều hướng về **`/browse`** (landing của CUSTOMER).
4. Chỉ vào header: tên + role, chuông thông báo.

**Điểm nói:** backend trả `landingRoute` theo role; FE không tự đoán.

### A2. Tìm & xem kho (2 phút)

1. Ở `/browse`: dùng filter (zone, loại kho, khoảng giá) và search.
2. Bấm một unit còn trống (ví dụ **M-2** hoặc **L-1**).
3. Trang chi tiết: mô tả, tiện ích, ảnh, **bảng giá minh bạch**.
4. Đổi số tháng → giá và cọc cập nhật ngay (gọi `/units/{id}/quote`).

**Điểm nói:** mọi con số tiền do backend `PricingEngine` tính; FE chỉ hiển thị. Cùng một quote được snapshot khi đặt để hợp đồng/biên lai không lệch giá.

### A3. Đặt kho (2 phút)

1. Bấm **Đặt kho** → trang booking summary.
2. Chọn ngày bắt đầu (tương lai, ví dụ tháng sau) + số tháng.
3. Bấm **Xác nhận đặt** → tạo reservation `PENDING_PAYMENT`, chuyển sang bước thanh toán.

**Điểm nói:** server re-check availability trong transaction; nếu unit vừa bị người khác đặt → **409 BOOKING_UNIT_TAKEN** và gợi ý unit tương tự. (Có thể demo nhanh: profile 2 dùng `trang@` đặt cùng unit/ngày → thấy lỗi 409.)

### A4. Thanh toán (2–3 phút)

Trang Payment có 4 phương thức:

| Tab | Cách demo | Kết quả kỳ vọng |
|---|---|---|
| **CARD** | nhập số thẻ bất kỳ (demo) | PROCESSING → ~1s → **SUCCEEDED** |
| **MOMO** | nhập SĐT bất kỳ | tự SUCCEEDED (demo, không OTP) |
| **VNPAY** | bấm thanh toán | tự SUCCEEDED |
| **PAYOS** | bấm tạo QR | hiện **VietQR + nút mở cổng PayOS**; quét/chuyển khoản thật thì webhook xác nhận |

Khuyến nghị khi demo: dùng **MOMO** để chắc chắn thành công, sau đó giới thiệu **PAYOS** bằng cách mở QR (không cần chuyển tiền) và nói: “đây là cổng thật, webhook đã xác thực chữ ký; tiền vào tài khoản thì trạng thái mới đổi.”

**Sau khi thanh toán cọc:**
- Reservation → **RESERVED**, deposit `HELD`.
- Hợp đồng **DRAFT** được sinh tự động (`CT-...`).
- Có notification “Booking confirmed”.

### A5. My Rentals & hợp đồng (1–2 phút)

1. Vào `/rentals`: thấy đơn vừa đặt, nhóm theo trạng thái.
2. Mở đơn → tab/tóm tắt: giá, cọc, **chuỗi hợp đồng**, nút xem nội dung hợp đồng.
3. (Tuỳ chọn) nếu có phụ lục: mở chain → ký phụ lục.

**Điểm nói:** hợp đồng lưu `contentSnapshot` tại thời điểm tạo; sửa policy sau này không làm thay đổi hợp đồng cũ.

### A6. Check-in pass (1 phút)

1. Trong rental detail bấm **Check-in pass** (`/rentals/{id}/check-in-pass`).
2. Trang hiện mã/QR để đưa nhân viên quét khi đến kho.

### A7. Gia hạn & trả kho (tuỳ chọn, 2 phút)

- **Gia hạn:** trong rental detail chọn gia hạn → hệ thống báo phí (quote) → xác nhận tạo payment phí gia hạn.
- **Trả kho:** chọn “Yêu cầu trả kho” → tạo checkout request; staff/FM xử lý ở phía vận hành.

### A8. Thông báo & hỗ trợ

- Bấm chuông: danh sách notification, đánh dấu đã đọc.
- Trang **Hỗ trợ** (`/support`): dùng để minh hoạ luồng ticket (lưu cục bộ — xem mục 7).

---

## 3. Kịch bản B — Nhân viên (STAFF) (4 phút)

Đăng nhập `minh@demo.storagehub.vn` / `password` → landing `/tasks`.

1. **Task board Kanban**: các cột theo trạng thái; task sinh từ nghiệp vụ (check-in/checkout/dọn dẹp).
2. Mở một task → xem chi tiết, ritual hướng dẫn.
3. Kéo/đổi trạng thái task → cột cập nhật, ghi activity log.
4. **Lịch trực**: xem ca của mình (roster).

**Điểm nói:** mọi chuyển trạng thái đi qua service, validate server-side; FE chỉ hiển thị.

---

## 4. Kịch bản C — Quản lý cơ sở (FACILITY_MANAGER) (5 phút)

Đăng nhập `tuan@demo.storagehub.vn` → landing `/facility`.

1. **Facility overview**: 4 KPI (công suất, doanh thu, hàng chờ, cảnh báo) + biểu đồ trạng thái unit.
2. Bấm một KPI → **drill-down** danh sách unit/đơn tương ứng.
3. **Quản lý kho** (`/facility/units`): danh sách, trạng thái, bộ lọc.
4. **Ca trực** (`/facility/shifts`): tạo ca cho staff; thử tạo ca trùng giờ → **409 conflict**; xoá ca.
5. **Activity log** (`/facility/activity`): lọc theo entity/ngày, thấy thao tác vừa làm.

---

## 5. Kịch bản D — Vận hành kinh doanh (BUSINESS_OPS) (5 phút)

Đăng nhập `hang@demo.storagehub.vn` → landing `/overview`.

1. **Business overview**: KPI doanh thu, công suất, hợp đồng; biểu đồ doanh thu theo tháng.
2. **Báo cáo** (`/reports`):
   - chọn kỳ (quý/tháng) → financial summary;
   - biểu đồ doanh thu 6 tháng;
   - drill-down từ KPI;
   - **xuất CSV**.
3. **Chính sách** (`/policy`): xem phiên bản policy (màn minh hoạ — xem mục 7).

**Điểm nói:** báo cáo chỉ tổng hợp từ payment/receipt đã ghi, không tính lại từ hợp đồng; tiền dùng `DECIMAL`, không float.

---

## 6. Kịch bản E — Quản trị hệ thống (SYSTEM_ADMIN) (5 phút)

Đăng nhập `nam@demo.storagehub.vn` → landing `/users`.

1. **Người dùng**: danh sách, lọc theo role/status.
2. **Tạo user** mới (chọn role STAFF/FM…).
3. **Đổi role** một user → thử đăng nhập lại user đó thấy landing đổi theo role.
4. **Khoá/mở khoá** user → user bị khoá không gọi API được (token cũ bị vô hiệu).
5. **Reset mật khẩu** → nhận mật khẩu tạm.
6. **Ma trận quyền** (`/users` tab permissions): bảng Role × Permission.
7. **Lịch sử đăng nhập** (`/login-history`): các lần LOGIN/LOGIN_FAILED.
8. **Activity log**: toàn bộ thao tác audit, không sửa/xoá được (append-only).

**Điểm nói:** phân quyền enforce ở **server** (`SecurityConfig` + permission matrix); FE chỉ ẩn menu. Demo nhanh: dùng token customer gọi `/api/v1/users` → 403.

---

## 7. Kịch bản F — DevOps/CI-CD (5 phút, phần “ăn tiền”)

### F1. Pipeline

1. Mở tab GitHub Actions của repo.
2. Sửa nhỏ trên máy (ví dụ đổi text trang chủ) → commit vào nhánh → PR → merge.
3. Chỉ vào run: `backend-test` → `frontend-build` → build 2 image GHCR → `deploy` (Tailscale → Dokploy) → `notify`.
4. Mở Slack `#homeserver-noti`: tin ✅ CI/CD OK kèm link run.
5. Mở site: thay đổi đã lên (container image `:sha-<commit>`).

**Điểm nói:**
- server **không build**; image bất biến theo commit;
- compose được **pin `:sha`** trước khi deploy (nếu không `up -d` với `:latest` sẽ không recreate);
- CI đỏ → không deploy (nhờ `needs`).

### F2. Rollback

- Trong Dokploy: sửa image tag về `sha-<commit cũ>` → deploy.
- Hoặc chạy lại workflow của commit cũ.

### F3. Monitoring & backup

1. `https://status.phucnn.io.vn` — 7 endpoint, 60s/lần; fail 3 lần → Slack DOWN, hồi phục → RESOLVED.
2. Backup: 02:30 hằng ngày (`pg_dump` + `mysqldump` + config), Chủ nhật 03:30 restore drill vào DB tạm.
3. Có thể show nhanh log backup:
   ```bash
   ssh homelab 'journalctl -u homelab-backup.service -n 5'
   ```

---

## 8. Kịch bản G — Sự cố & xử lý (tuỳ chọn, 2 phút)

| Tình huống demo | Cách làm | Kết quả |
|---|---|---|
| Trùng kho | 2 tài khoản đặt cùng unit/ngày | 409 `BOOKING_UNIT_TAKEN` |
| Sai mật khẩu | login `wrongpass` | 401 (password < 6 ký tự → 400 validation) |
| Không có token | mở `/api/v1/units` bằng curl | 401 |
| Sai quyền | customer mở `/api/v1/users` | 403 `ROLE_FORBIDDEN` |
| App down | `docker stop` nginx (nếu có quyền) | Gatus báo DOWN sau ~3 phút, Slack nhận tin |

---

## 9. Những phần **chưa hoàn thiện** (nói trước để tránh bị hỏi khó)

| Hạng mục | Trạng thái |
|---|---|
| Upload ảnh hợp đồng (AD-10) | chưa có endpoint → ảnh seed 404 |
| Ký hợp đồng gốc (chỉ có ký **phụ lục**) | chưa demo |
| Ticket hỗ trợ, Policy, một phần Unit Management | đang dùng dữ liệu/local state ở FE, chưa nối API |
| Thanh toán PayOS thật | tạo QR được; chỉ chuyển SUCCEEDED khi có giao dịch thật/webhook |
| Báo cáo export CSV | có API; kiểm tra định dạng trên máy bạn trước khi demo |

---

## 10. Checklist trước khi bấm “Start”

- [ ] `health` = UP, status page 7/7 xanh
- [ ] Đăng nhập được cả 5 tài khoản
- [ ] Có ít nhất 1 unit **AVAILABLE** cho ngày demo (hiện còn M-2, L-1, …)
- [ ] PayOS: kênh **DEMO-MARKETPLACE** hoạt động, webhook URL đúng domain
- [ ] Slack mở sẵn, tab Actions mở sẵn
- [ ] Tắt thông báo cá nhân trên máy
- [ ] Dự phòng: nếu mạng/PayOS lỗi → dùng MOMO demo, không chuyển sang phần DevOps

## 11. Câu hỏi thường gặp khi demo

**“Dữ liệu có mất khi restart không?”** — Không: MySQL chạy volume trên SSD; backup 02:30 + drill restore.

**“Deploy mất bao lâu?”** — ~2–4 phút (test + build 2 image + deploy), không tính thời gian bạn sửa code.

**“Bảo mật thế nào?”** — JWT + phân quyền server-side, BCrypt, không mở port router, admin chỉ LAN/Tailscale, tunnel outbound-only. Đây là môi trường demo nên seed công khai — production sẽ tắt seed/đổi mật khẩu.

**“Nếu Cloudflare/PayOS sập?”** — App vẫn chạy nội bộ; truy cập qua LAN/Tailscale. PayOS lỗi thì fallback thanh toán demo.

---

## 12. Phụ lục — lệnh kiểm tra nhanh (khi demo bị “đứng”)

```bash
# app
curl -s https://storagehub.phucnn.io.vn/actuator/health
# container
ssh homelab 'docker ps --filter name=storagehub-myzyte'
# log lỗi backend
ssh homelab 'docker logs --since 10m $(docker ps -qf name=storagehub-myzyte-backend) | grep -E "ERROR|Exception"'
# trạng thái monitor
curl -s https://status.phucnn.io.vn/api/v1/endpoints/statuses | head -c 500
```
