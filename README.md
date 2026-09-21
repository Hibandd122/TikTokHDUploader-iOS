# Hướng dẫn Build & Cài đặt App iOS "TikTok HD Uploader"

Thư mục: `ios_tiktok_uploader/` chứa toàn bộ mã nguồn ứng dụng iOS viết bằng **Swift / SwiftUI thuần**, sử dụng trực tiếp URLSession và thuật toán ký X-Bogus để tải video Full HD lên TikTok ngay trên iPhone.

---

## 1. Cấu trúc Source Code iOS

```
ios_tiktok_uploader/
├── XBogus.swift              # Thuật toán ký số Web X-Bogus viết bằng Swift
├── AWSSigV4.swift            # Chữ ký AWS SigV4 cho ByteDance VOD Ingest
├── CRC32.swift               # Kiểm tra toàn vẹn từng chunk video
├── TikTokUploaderEngine.swift# Engine mạng URLSession tải lên & đăng bài
├── ContentView.swift         # Giao diện SwiftUI hiện đại (chọn video, tag, caption)
├── TikTokUploaderApp.swift   # Điểm khởi chạy ứng dụng
├── Info.plist                # Quyền truy cập Photo Library
└── project.yml               # File cấu hình tạo Project Xcode tự động
```

---

## 2. Cách Build thành file `.ipa`

### Cách 1: Dùng Xcode trên macOS
1. Cài đặt `xcodegen` (nếu chưa có):
   ```bash
   brew install xcodegen
   ```
2. Mở Terminal tại thư mục `ios_tiktok_uploader` và chạy:
   ```bash
   xcodegen generate
   ```
   Lệnh này sẽ tự động sinh file `TikTokHDUploader.xcodeproj`.
3. Mở file project bằng Xcode -> Chọn thiết bị iPhone của bạn hoặc Generic iOS Device.
4. Vào menu **Product -> Archive** -> Chọn **Distribute App** -> **Ad Hoc / Development** để xuất file `.ipa`.

---

## 3. Cách cài file `.ipa` vào iPhone

Có 3 cách cài cực kỳ phổ biến và tiện lợi:
1. **TrollStore** (Dành cho iOS 14.0 - 16.6.1 / 17.0):
   - Chuyển file `.ipa` qua AirDrop hoặc Telegram vào iPhone -> Nhấn mở bằng TrollStore -> Cài vĩnh viễn không bao giờ bị thu hồi chứng chỉ (Revoke).
2. **AltStore / Sideloadly** (Mọi phiên bản iOS):
   - Kết nối iPhone với máy tính qua cáp Lightning/Type-C.
   - Kéo thả file `.ipa` vào Sideloadly, nhập Apple ID để ký chứng chỉ 7 ngày miễn phí.
3. **Scarlet / ESign / Gbox**:
   - Nhập trực tiếp file `.ipa` vào ứng dụng ESign/Scarlet trên iPhone để ký và cài đặt ngay trên điện thoại không cần máy tính.
