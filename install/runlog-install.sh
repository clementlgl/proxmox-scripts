#!/usr/bin/env bash

# Author: Clément Laigle
# License: MIT
# Source: https://github.com/clementlgl/runlog

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Source to deploy; `update` keeps tracking whatever was installed
RUNLOG_REPO="${RUNLOG_REPO:-clementlgl/runlog}"
RUNLOG_BRANCH="${RUNLOG_BRANCH:-main}"

msg_info "Installing Dependencies"
$STD apt install -y git curl ca-certificates python3
msg_ok "Installed Dependencies"

# uv only installs packages: Debian's python3 runs them (a uv-managed Python
# would live under /root, unreadable by the runlog service user)
setup_uv
NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_branch "runlog" "$RUNLOG_REPO" "$RUNLOG_BRANCH" "/opt/runlog"
# The checkout belongs to root; services run as the runlog user and only read it
git config --global --add safe.directory /opt/runlog

msg_info "Creating User and Data Directory"
# Persistent state lives outside the git checkout so updates never touch it:
#   data/          exports + runs.duckdb
#   .mifit/        Xiaomi session (HOME of the services, read by mifit)
#   runlog.env     settings of both services
useradd --system --home-dir /opt/runlog-data --shell /usr/sbin/nologin runlog
mkdir -p /opt/runlog-data/data /opt/runlog-data/.mifit
cat <<ENV >/opt/runlog-data/runlog.env
# Public URL of the app, exactly as typed in the browser. Behind Caddy:
# ORIGIN=https://runlog.<domain>
ORIGIN=http://${LOCAL_IP}

# Xiaomi account region, forced when logging in from the app (de = Europe)
MIFIT_REGION=de

# --- internal, no need to change ---
HOME=/opt/runlog-data
DATA_DIR=/opt/runlog-data/data
API_URL=http://127.0.0.1:8000
HOST=0.0.0.0
PORT=80
ENV
chown -R runlog:runlog /opt/runlog-data
chmod 700 /opt/runlog-data/.mifit
chmod 640 /opt/runlog-data/runlog.env
msg_ok "Created User and Data Directory"

msg_info "Building Runlog"
cd /opt/runlog/backend
$STD uv venv --python /usr/bin/python3 .venv
$STD uv pip install --python .venv/bin/python -r pyproject.toml
cd /opt/runlog/frontend
$STD corepack enable
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
# The version that wrote frontend/pnpm-lock.yaml
$STD corepack prepare pnpm@12.18.0 --activate
$STD pnpm install --frozen-lockfile
$STD pnpm run build
rm -rf node_modules .svelte-kit
msg_ok "Built Runlog"

msg_info "Creating Services"
cat <<SERVICE >/etc/systemd/system/runlog-backend.service
[Unit]
Description=Runlog API (FastAPI + DuckDB)
After=network-online.target
Wants=network-online.target

[Service]
User=runlog
Group=runlog
EnvironmentFile=/opt/runlog-data/runlog.env
WorkingDirectory=/opt/runlog/backend
ExecStart=/opt/runlog/backend/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

cat <<SERVICE >/etc/systemd/system/runlog-frontend.service
[Unit]
Description=Runlog web app (SvelteKit)
After=runlog-backend.service
Wants=runlog-backend.service

[Service]
User=runlog
Group=runlog
EnvironmentFile=/opt/runlog-data/runlog.env
Environment=NODE_ENV=production
WorkingDirectory=/opt/runlog/frontend
ExecStart=/usr/bin/node build
# Port 80 without running as root
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE
systemctl enable -q --now runlog-backend runlog-frontend
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
