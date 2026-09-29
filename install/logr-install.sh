#!/usr/bin/env bash

# Author: Clément Laigle
# License: MIT
# Source: https://logr.beer | Github: https://github.com/clementlgl/logr-app (fork of logr-beer/logr-app)

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Source to deploy; `update` keeps tracking whatever was installed
LOGR_REPO="${LOGR_REPO:-clementlgl/logr-app}"
LOGR_BRANCH="${LOGR_BRANCH:-feat/barcode-scanner}"

msg_info "Installing Dependencies"
$STD apt install -y nginx sqlite3
msg_ok "Installed Dependencies"

PHP_VERSION="8.4" PHP_FPM="YES" PHP_MODULE="sqlite3" setup_php
setup_composer
NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_branch "logr" "$LOGR_REPO" "$LOGR_BRANCH" "/opt/logr"
# The checkout is chowned to www-data below; updates run git as root
git config --global --add safe.directory /opt/logr

msg_info "Configuring Logr"
# Persistent state lives outside the git checkout so updates never touch it
mkdir -p /opt/logr-data/database /opt/logr-data/storage /opt/logr-data/backups
cp -r /opt/logr/storage/app/. /opt/logr-data/storage/
rm -rf /opt/logr/storage/app
ln -s /opt/logr-data/storage /opt/logr/storage/app
touch /opt/logr-data/database/database.sqlite
ln -sf /opt/logr-data/database/database.sqlite /opt/logr/database/database.sqlite

cat <<ENV >/opt/logr-data/.env
APP_NAME=Logr
APP_ENV=production
APP_DEBUG=false
APP_KEY=base64:$(openssl rand -base64 32)
APP_URL=http://${LOCAL_IP}
APP_TIMEZONE=Europe/Paris

DB_CONNECTION=sqlite
DB_DATABASE=/opt/logr/database/database.sqlite

QUEUE_CONNECTION=database
CACHE_STORE=database
SESSION_DRIVER=database

LOG_CHANNEL=daily
LOG_LEVEL=warning

# Reverse proxy terminating TLS (Caddy...): restrict to its IP once known
TRUSTED_PROXIES=*
ENV
chmod 640 /opt/logr-data/.env
ln -sf /opt/logr-data/.env /opt/logr/.env

cd /opt/logr
export COMPOSER_ALLOW_SUPERUSER=1
$STD composer install --no-dev --optimize-autoloader --no-interaction
$STD npm ci
$STD npm run build
rm -rf node_modules
$STD php artisan migrate --force
$STD php artisan db:seed --force
$STD php artisan storage:link --force
chown -R www-data:www-data /opt/logr /opt/logr-data
msg_ok "Configured Logr"

msg_info "Creating Services"
PHP_FPM_SOCKET="$(get_php_fpm_socket)"
cat <<NGINX >/etc/nginx/sites-available/logr
server {
    listen 80;
    server_name _;
    root /opt/logr/public;
    index index.php;

    client_max_body_size 20M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:${PHP_FPM_SOCKET};
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
NGINX
nginx_enable_site logr

cat <<SERVICE >/etc/systemd/system/logr-queue.service
[Unit]
Description=Logr queue worker
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/opt/logr
ExecStart=/usr/bin/php artisan queue:work --sleep=3 --tries=3 --timeout=300
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

cat <<SERVICE >/etc/systemd/system/logr-scheduler.service
[Unit]
Description=Logr scheduler
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/opt/logr
ExecStart=/usr/bin/php artisan schedule:work
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE
systemctl enable -q --now logr-queue logr-scheduler
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
