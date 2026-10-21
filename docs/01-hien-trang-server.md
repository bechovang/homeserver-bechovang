# 01 — Hiện trạng server (audit 21/10/2026)

> Nguồn: SSH trực tiếp `phuc@192.168.1.140`, chạy `lscpu`, `dmidecode`, `smartctl`, `lsblk`, `networkctl`, `systemctl`...

## 1. Phần cứng

### CPU
- Intel Core i5-3470 (Ivy Bridge, 2012) — 4 cores / 4 threads
- 3.2 GHz base, Turbo 3.6 GHz, TDP 77W
- Nhiệt độ khi idle: 27–48°C ✅

### RAM
- **2× 4GB DDR3-1600 dual channel = 8GB vật lý** (ChannelA-DIMM0 + ChannelB-DIMM0)
- Kernel chỉ thấy **~6.6GB, usable ~5.9GiB** — iGPU Intel HD chiếm ~1.4GB
- → Lập kế hoạch tài nguyên theo **6GB usable**, không phải 8GB

### Mainboard / BIOS
- Onboard LAN Intel 82579V (subsystem LG Electronics), WiFi PCIe Intel AC-8265
- BIOS American Megatrends (AMI), version PVI0G, date 10/22/2012
- Boot mode: **UEFI** (có efivarfs, /boot/efi 1GB vfat)

### Ổ cứng

| Ổ | Model | Dung lượng | Vai trò | SMART | Đánh giá |
|---|---|---|---|---|---|
| `/dev/sda` | KimMiDi SSD TB90 | 119.2 GB | OS `/` (ext4) | PASSED — 6.356 giờ, 0 bad sector, 30°C | ✅ Khỏe, chạy OS + Docker + DB |
| `/dev/sdb` | Seagate ST9500325AS (2.5" 5400rpm, ~2009) | 465.8 GB | `/data` (ext4, mount bằng UUID) | PASSED — **21.839 giờ (~2.5 năm quay), 1 reallocated sector**, 38°C | ⚠️ Già — **chỉ dùng backup/scratch**, không chứa dữ liệu duy nhất |
| `/dev/sdc` | USB "ProductCode" (bridge 346d:5678) | 0 B | — | Unknown USB bridge | ❌ Rác — nên rút ra |

### USB devices khác
- YICHIP 2.4G Receiver (chuột/bàn phím không dây), Apple Aluminium Keyboard — bình thường

## 2. Mạng

| Interface | Chipset | Driver | Trạng thái |
|---|---|---|---|
| `wlp2s0` (WiFi) | Intel Wireless-AC 8265 (PCIe) | `iwlwifi` | ✅ **Đang dùng** — join SSID, DHCP → 192.168.1.140 |
| `eno1` (LAN) | Intel 82579V onboard | `e1000e` | ⚠️ DOWN — **không cắm dây** (máy CÓ port LAN hoạt động được) |

**Quyết định (đã chốt với user):** chỉ dùng được WiFi → set static IP 192.168.1.140 qua netplan, giữ driver Intel chuẩn (không phải USB TP-Link như kế hoạch gốc lo ngại).

- Router/gateway: `192.168.1.1`, DNS set: 1.1.1.1 / 8.8.8.8 / 192.168.1.1
- Mạng nhà có IPv6 (DHCPv6 + prefix delegation từ ISP)
- ⚠️ Việc cần làm ở router: **DHCP reservation cho MAC `ae:ed:5c:bc:d3:33`** (WiFi) giữ IP .140, tránh đụng IP sau này

## 3. Hệ điều hành & dịch vụ

- **Ubuntu 26.04.1 LTS "Resolute Raccoon"**, kernel 7.0.0-38-generic
- Cài sạch bằng subiquity (netplan `00-installer-config.yaml`), UEFI, swap 4GB (`/swap.img` trên SSD)
- Ngày audit: máy uptime 43 phút, `/` dùng 7.6GB/116GB
- Có sẵn: git 2.53, python3, chrony (NTP), unattended-upgrades ✅, OpenSSH (password auth)
- ufw: **inactive** lúc audit → đã bật (xem docs/03)
- `authorized_keys` trống — toàn bộ SSH bằng password (có fail2ban rồi; cân nhắc add SSH key)

## 4. Lệch so với kế hoạch gốc (file deploy-CICD/*.txt)

Kế hoạch gốc viết dựa trên ảnh CPU-Z/DxDiag cũ. Audit thực tế phát hiện:

| Kế hoạch gốc nghĩ là | Thực tế | Tác động |
|---|---|---|
| USB WiFi TP-Link TL-WN21N V6 (RTL8192EU) — lo driver Linux | **Card PCIe Intel AC-8265** (`iwlwifi`) chạy sẵn | ✅ Hết lo driver, bỏ qua toàn bộ hướng dẫn rtl8xxxu/DKMS |
| HDD 252GB | **Seagate 500GB** (nhưng là ổ 2009, 21.839 giờ) | Nhiều chỗ hơn nhưng kém tin cậy — chỉ làm ổ backup |
| Máy chưa có OS, cần cài Ubuntu | **Đã cài Ubuntu 26.04.1 sẵn** | Bỏ qua Giai đoạn 1 cài OS của plan gốc |
| RAM 8GB | 8GB vật lý nhưng **~6GB usable** (iGPU giành 1.4GB) | RAM budget tính theo 6GB |
| Chưa rõ có Ethernet không | Có Intel 82579V onboard, driver loaded, chỉ thiếu dây | Nếu sau này cắm được dây LAN thì cực tốt cho server |

## 5. Vấn đề phát hiện khi audit (và tình trạng xử lý)

1. `systemd-networkd-wait-online.service` FAIL → boot chậm ~2 phút do `eno1` không carrier → **đã fix** (`optional: true` cho eno1)
2. ufw inactive → **đã bật** với rules whitelist
3. `sdc` USB 0B vô dụng → chờ user rút physical
4. HDD già + 1 reallocated sector → đã bật smartd test định kỳ; **bắt buộc phải có backup off-server** (Phase 6)
