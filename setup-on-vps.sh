#!/usr/bin/env bash
# setup-on-vps.sh — Cài đặt + khởi động static server cho NexConnect updates.
# Chạy 1 lần trên VPS 104.234.180.103 với quyền root.
#
# Usage:
#   scp setup-on-vps.sh root@104.234.180.103:/root/
#   ssh root@104.234.180.103
#   bash /root/setup-on-vps.sh

set -e

PORT="${PORT:-3000}"
WEBROOT="/var/www/updates"

echo "=== [1/5] Cập nhật apt ==="
apt update -y

echo "=== [2/5] Cài nginx ==="
if ! command -v nginx >/dev/null 2>&1; then
    apt install -y nginx
fi

echo "=== [3/5] Tạo thư mục ${WEBROOT} ==="
mkdir -p "${WEBROOT}"
chmod 755 "${WEBROOT}"

echo "=== [4/5] Tạo config nginx ==="
cat > /etc/nginx/sites-available/nexconnect-updates <<EOF
server {
    listen ${PORT} default_server;
    listen [::]:${PORT} default_server;
    server_name _;

    location /updates/ {
        alias ${WEBROOT}/;
        autoindex off;
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header Expires "0" always;

        location = /updates/manifest.json {
            add_header Content-Type application/json always;
        }
    }

    location = /updates {
        return 301 \$scheme://\$host/updates/;
    }
}
EOF

# Disable default site, enable ours
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/nexconnect-updates /etc/nginx/sites-enabled/nexconnect-updates

# Validate
nginx -t

echo "=== [5/5] Khởi động nginx + mở firewall ==="
systemctl enable nginx
systemctl restart nginx
systemctl status nginx --no-pager | head -5

# UFW (if installed)
if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PORT}/tcp || true
fi

echo ""
echo "=== Kiểm tra nhanh ==="
sleep 1
echo "Files in ${WEBROOT}:"
ls -la "${WEBROOT}/" || echo "(empty)"

echo ""
echo "Curl localhost test:"
curl -sS -o /dev/null -w "HTTP %{http_code}  size=%{size_download}\n" \
    "http://127.0.0.1:${PORT}/updates/manifest.json" || true

echo ""
echo "Done. Manifest URL:"
echo "  http://104.234.180.103:${PORT}/updates/manifest.json"
