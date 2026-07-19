# NexConnect Updater

Repo này chỉ chứa **manifest + script publish** cho auto-update của NexConnect.
Source code chính ở máy local / repo riêng; repo này đóng vai trò **host lưu trữ release artifacts** qua GitHub Releases.

## Cấu trúc

```
.
├── .gitignore         # Bỏ qua binary, log, stage/
├── manifest.json      # Manifest mẫu (URL trỏ GitHub Releases)
├── publish-update.ps1 # Script build + tạo GitHub Release + upload
└── README.md          # File này
```

## Lần đầu: cài `gh` CLI + đăng nhập

```powershell
winget install --id GitHub.cli --accept-source-agreements --accept-package-agreements --silent
gh auth login
```

## Publish bản mới

Trong `CMakeLists.txt` đã có `project(NexConnect VERSION 1.0.X LANGUAGES CXX)`. Script sẽ bump version tự động nếu truyền `-NewVersion`.

```powershell
# Trong thư mục source gốc (F:\Nexconnect), KHÔNG phải dist-update/
cd F:\Nexconnect
$env:Path = "C:\Program Files\GitHub CLI;" + $env:Path

powershell -ExecutionPolicy Bypass -File .\dist-update\publish-update.ps1 `
    -NewVersion "1.0.5" `
    -GitHubRepo "MouseTi/NexConnect"
```

Script sẽ:
1. Sửa `CMakeLists.txt` lên version mới (nếu khác)
2. `cmake --build build --config Release --target NexConnect`
3. Tính SHA256 của `NexConnect.exe` và `nexus_runtime.dll`
4. `gh release create v<NewVersion>` + upload 3 file:
   - `manifest.json` (cập nhật version + URL + hash mới)
   - `NexConnect.exe`
   - `nexus_runtime.dll`
5. Nếu release đã tồn tại, script fail (cần xoá thủ công hoặc dùng `-Force`).

## Cách client cập nhật

Hard-coded URL trong `UpdateManager.cpp`:

```cpp
#define NEXCONNECT_UPDATE_MANIFEST_URL \
  "https://github.com/MouseTi/NexConnect/releases/latest/download/manifest.json"
```

`releases/latest/download/...` luôn trỏ về release mới nhất — không cần update URL khi bump version.

## Manifest schema

```json
{
  "version": "1.0.4",
  "url":     "https://github.com/MouseTi/NexConnect/releases/latest/download/NexConnect.exe",
  "sha256":  "abc123...",
  "required": false,
  "message": "Tu v1.0.3 len v1.0.4",
  "files": [
    {
      "path":   "build/Release/nexus_runtime.dll",
      "url":    "https://github.com/MouseTi/NexConnect/releases/latest/download/nexus_runtime.dll",
      "sha256": "def456...",
      "action":  "replace"
    }
  ]
}
```

| Field | Bắt buộc | Ý nghĩa |
|---|---|---|
| `version` | ✅ | SemVer-ish |
| `url` | ✅ | Trỏ tới binary installer/launcher |
| `sha256` | ✅ | Client verify sau khi download |
| `required` |  | Nếu `true`, client bắt buộc update không cho skip |
| `message` |  | Hiện trong dialog |
| `files[]` |  | File phụ cần thay kèm (DLL, data…) |

## Xử lý lỗi thường gặp

| Lỗi | Nguyên nhân | Fix |
|---|---|---|
| `gh: command not found` | `gh` chưa trong PATH | `winget install GitHub.cli` hoặc đặt `C:\Program Files\GitHub CLI` vào PATH |
| `Invalid target_commitish` | Repo rỗng, chưa có branch `main` | `git init -b main && git add . && git commit` rồi `git push -u origin main` |
| `Release.tag_name already exists` | Tag `v<NewVersion>` đã tồn tại | Đổi `-NewVersion`, hoặc `gh release delete v<X.Y.Z> --repo MouseTi/NexConnect` rồi chạy lại |

## Debug nhanh

```powershell
# Xem release hiện tại
gh release view --repo MouseTi/NexConnect

# Xem manifest đang phát
curl https://github.com/MouseTi/NexConnect/releases/latest/download/manifest.json
```
