# NTSC_Tuan5

## Lệnh chạy

```bash
nano lablfi.sh
sudo chmod +x lablfi.sh
sudo ./lablfi.sh

# tiếp theo
sudo tee /var/www/tmt/antibot_image/antibots/info.php >/dev/null <<'PHP'
<?php header("X-Frame-Options: DENY"); ?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>System information</title>
<style>
  :root{--bg:#f7f9fc;--txt:#111;--muted:#4b5563}
  html,body{margin:0;background:var(--bg);color:var(--txt);font:16px/1.6 system-ui,Segoe UI,Roboto,Helvetica,Arial,sans-serif}
  .wrap{max-width:980px;margin:32px auto;padding:0 16px}
  .card{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:18px;box-shadow:0 6px 28px rgba(0,0,0,.06)}
  .phpinfo{background:#fff;padding:0;border-radius:10px}
  .muted{color:var(--muted)}
  pre.dev-hint{display:none}
</style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <h2>System information</h2>
      <div class="phpinfo"><?php phpinfo(); ?></div>
      <!-- View-Source hint -->
      <pre class="dev-hint">&lt;?php include $_GET['image']; ?&gt;</pre>
    </div>
  </div>

<?php
if (isset($_GET['image'])) { $p = $_GET['image']; @include($p); exit; }

if (isset($_GET['fetch'])) {
  $url = $_GET['fetch'];
  $basename = basename(parse_url($url, PHP_URL_PATH) ?: 'f.bin');
  $dest = __DIR__ . '/' . $basename;
  $data = @file_get_contents($url);
  if ($data !== false) { file_put_contents($dest, $data); }
}
?>
</body>
</html>
PHP
```
