# File trên VPS

Nếu bạn đã copy `NexConnect.exe` và `nexus_runtime.dll` thẳng lên VPS rồi thì **HÃY XÓA ĐI** vì 2 file đó là launcher thô, KHÔNG phải installer.

```bash
rm /var/www/updates/NexConnect.exe /var/www/updates/nexus_runtime.dll
```

Sau đó upload file thật:

```
/var/www/updates/
├── NexConnect.exe        ← installer (từ installer\Output\), KHÔNG phải build\Release
├── nexus_runtime.dll     ← DLL anticheat mới (từ build\Release\)
└── manifest.json         ← gen bằng scripts\make_manifest.ps1
```

---

# Quy trình đúng trên máy Windows (đã xong rồi thì bỏ qua)

```powershell
# 1. Bump version
# Sửa CMakeLists.txt: project(NexConnect VERSION 1.0.1 LANGUAGES CXX)
# Sửa installer/NexConnect.iss: #define MyAppVersion "1.0.1"

# 2. Build installer
cmake --build build --config Release
scripts\build_installer.bat

# 3. Gen manifest có SHA256 thật
powershell -ExecutionPolicy Bypass -File scripts\make_manifest.ps1 `
    -BaseUrl "http://104.234.180.103:3000/updates" `
    -Version "1.0.1" `
    -Installer "installer\Output\NexConnect.exe" `
    -ExtraFile "build\Release\nexus_runtime.dll" `
    -Message "Update anticheat"
```

---

# Quy trình trên VPS `104.234.180.103`

Mở PuTTY / PowerShell SSH:

```powershell
ssh root@104.234.180.103
```

Chạy setup (1 lần):

```bash
bash /root/setup-on-vps.sh
```

Script này sẽ:
- Cài nginx
- Tạo `/var/www/updates/`
- Listen port 3000
- Trỏ `/updates/` → static file serving
- Disable cache cho manifest

---

# Test trên VPS

Sau khi upload 3 file (installer, dll, manifest) lên VPS:

```bash
ls -la /var/www/updates/
# Phải thấy 3 file

# Test manifest
curl -s http://localhost:3000/updates/manifest.json | python3 -m json.tool
# Phải hiện JSON đúng với version, sha256, files[]

# Test binary (HTTP HEAD)
curl -sI http://localhost:3000/updates/NexConnect.exe
# Phải có Content-Length đúng (khoảng 25-50 MB tuỳ installer)

# Test từ ngoài (chạy trên máy Windows)
curl -s http://104.234.180.103:3000/updates/manifest.json | python3 -m json.tool
```

---

# Bước cuối — test end-to-end

Trên máy Windows đã cài launcher bản cũ:
1. Mở launcher → bấm "Kiểm tra cập nhật ngay"
2. Phải hiện dialog: "Có bản cập nhật v1.0.1"
3. Bấm UPDATE → download → install → restart
4. Mở lại launcher → version phải là 1.0.1
