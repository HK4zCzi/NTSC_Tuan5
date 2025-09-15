#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ===== Tomato stealth but same paths =====
# - Giữ NGUYÊN: /var/www/tomato/antibot_image/antibots/info.php, port 21/80/8888/2211
# - ẨN toàn bộ brand/hint "Tomato", UI trung tính
# - Tự phát hiện PHP-FPM version/socket (Ubuntu 16.04 → 24.04 đều chạy)
# - Có rsyslog để có /var/log/auth.log phục vụ log-poisoning

echo "[*] Installing base packages..."
apt-get update -y
apt-get install -y nginx php-fpm php-cli apache2-utils vsftpd curl unzip gcc make rsyslog imagemagick

# Detect PHP-FPM
PHPVER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')" || PHPVER="8.1"
PHPSOCK="/run/php/php${PHPVER}-fpm.sock"
PHPSVC="php${PHPVER}-fpm"
echo "[*] PHP-FPM: ${PHPSVC} at ${PHPSOCK}"


WEBROOT="/var/www/tomato"
mkdir -p "${WEBROOT}/assets"
mkdir -p "${WEBROOT}/antibot_image/antibots"

# ---- Landing page 
cat > "${WEBROOT}/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><title>Welcome</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link href="/assets/site.css" rel="stylesheet">
</head>
<body class="wrap">
  <header class="hero">
    <h1>Welcome</h1>
    <p>Content is temporarily unavailable.</p>
  </header>
  <main class="card">
    <img src="/assets/banner.jpg" alt="banner" class="banner">
    <p class="muted">Please check back later.</p>
  </main>
  <footer class="foot">© 2025</footer>
</body>
</html>
HTML

# CSS trung tính (giữ đẹp, không gợi ý gì)
cat > "${WEBROOT}/assets/site.css" <<'CSS'
:root{--bg:#0f0f13;--card:#151923;--txt:#f4f6fb;--sub:#a6b0cf}
*{box-sizing:border-box}body{margin:0;background:linear-gradient(180deg,#0b0e13,#12151d);}
.wrap{color:var(--txt);font:16px/1.6 system-ui,Segoe UI,Roboto,Helvetica,Arial,sans-serif;max-width:980px;margin:0 auto;padding:40px 16px}
.hero{display:grid;gap:6px;justify-items:center;margin:12px 0 20px}
.hero h1{font-size:44px;margin:0}
.hero p{color:var(--sub);margin:0}
.card{background:var(--card);border:1px solid #202639;border-radius:16px;padding:18px;box-shadow:0 10px 30px rgba(0,0,0,.2)}
.banner{width:100%;height:auto;border-radius:12px;display:block}
.muted{color:var(--sub)}
.foot{opacity:.7;text-align:center;margin-top:22px}
.hidden{display:none}
CSS

# Banner local (không phụ thuộc mạng)
convert -size 1200x600 xc:"#1d2333" -fill "#e5e7eb" -gravity center -pointsize 72 \
  -annotate 0 "Welcome" "${WEBROOT}/assets/banner.jpg"

# ---- info.php: giữ nguyên VỊ TRÍ & TÊN, ẩn mọi hint, vẫn LFI + fetch ----
cat > "${WEBROOT}/antibot_image/antibots/info.php" <<'PHP'
<?php
header("X-Frame-Options: DENY");
?><!doctype html><html><head>
<meta charset="utf-8"><title>Content</title>
<link rel="stylesheet" href="/assets/site.css">
</head><body class="wrap">
<div class="card">
  <div class="hidden"><?php phpinfo(); ?></div>
  <p class="muted">No content.</p>
</div>
<?php
// LFI giữ nguyên nhưng KHÔNG hiển thị hint trên UI:
if (isset($_GET['image'])) { $p = $_GET['image']; @include($p); exit; }
// "fetch via URL" giữ nguyên (im lặng), lưu ngay tại thư mục hiện tại:
if (isset($_GET['fetch'])) {
  $url = $_GET['fetch'];
  $basename = basename(parse_url($url, PHP_URL_PATH) ?: 'f.bin');
  $dest = __DIR__ . '/' . $basename;
  $data = @file_get_contents($url);
  if ($data !== false) { file_put_contents($dest, $data); }
}
?>
</body></html>
PHP

chown -R www-data:www-data "${WEBROOT}"

# ---- Nginx: GIỮ NGUYÊN tên vhost
htpasswd -bc /etc/nginx/.htpasswd admin abc123 >/dev/null 2>&1

# :80
cat > /etc/nginx/sites-available/tomato_80 <<'NG'
server {
  listen 80;
  server_name _;
  root /var/www/tomato;
  index index.html;
  charset utf-8;
  location / { try_files $uri $uri/ =404; }
}
NG

# :8888 + BasicAuth + autoindex cho /antibot_image/ + PHP-FPM
cat > /etc/nginx/sites-available/tomato_8888 <<NG
server {
  listen 8888;
  server_name _;
  root /var/www/tomato;
  index index.php index.html;
  charset utf-8;

  auth_basic "Restricted Area";
  auth_basic_user_file /etc/nginx/.htpasswd;

  location /antibot_image/ {
    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime on;
  }
  location ~ \\.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:${PHPSOCK};
  }
}
NG

ln -sf /etc/nginx/sites-available/tomato_80   /etc/nginx/sites-enabled/tomato_80
ln -sf /etc/nginx/sites-available/tomato_8888 /etc/nginx/sites-enabled/tomato_8888
rm -f /etc/nginx/sites-enabled/default || true

# ---- SSH port 2211  ----
cp -n /etc/ssh/sshd_config /etc/ssh/sshd_config.bak || true
if grep -qE '^#?\s*Port\s+' /etc/ssh/sshd_config; then
  sed -i 's/^#\?\s*Port\s\+.*/Port 2211/' /etc/ssh/sshd_config
else
  echo "Port 2211" >> /etc/ssh/sshd_config
fi

# ---- FTP anonymous trỏ vào /antibot_image (giữ đúng Tomato) ----
cp -n /etc/vsftpd.conf /etc/vsftpd.conf.orig || true
cat > /etc/vsftpd.conf <<'FTP'
listen=YES
anonymous_enable=YES
local_enable=YES
write_enable=YES
anon_root=/var/www/tomato/antibot_image
chroot_local_user=YES
pasv_enable=YES
pasv_min_port=30000
pasv_max_port=30100
xferlog_enable=YES
ftpd_banner=Welcome.
FTP

# ---- Flags giữ chỗ cũ ----
echo "user_flag_12345"  > /home/user.txt
echo "proof_of_root_from_lab" > /root/proof.txt
chmod 644 /home/user.txt
chmod 600 /root/proof.txt

# ---- Bảo đảm có auth.log ----
systemctl enable --now rsyslog

# ---- Restart services ----
systemctl restart "${PHPSVC}" nginx vsftpd ssh

IP4="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo
echo "=============== STEALTH (same paths) READY ==============="
echo "  VM IP       : ${IP4:-<ip>}"
echo "  HTTP        : http://${IP4:-<ip>}/"
echo "  LISTING     : http://${IP4:-<ip>}:8888/antibot_image/   (BasicAuth: admin / letmein)"
echo "  VULN FILE   : /antibot_image/antibots/info.php"
echo "  SSH         : ssh <user>@${IP4:-<ip>} -p 2211"
echo "  FTP         : ftp ${IP4:-<ip>}  (anonymous → /antibot_image)"
echo "=========================================================="
