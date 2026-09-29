#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/clementlgl/proxmox-scripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Author: Clément Laigle
# License: MIT
# Source: https://logr.beer | Github: https://github.com/clementlgl/logr-app (fork of logr-beer/logr-app)

APP="Logr"
var_tags="${var_tags:-beer;tracker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/logr/.git ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # /opt/logr belongs to www-data: let root's git work on it
  git config --global --get-all safe.directory | grep -qx /opt/logr || git config --global --add safe.directory /opt/logr

  # Track whatever repo/branch the container was installed from
  local repo branch
  repo="$(git -C /opt/logr remote get-url origin | sed -E 's#^https://github.com/##; s#\.git$##')"
  branch="$(git -C /opt/logr rev-parse --abbrev-ref HEAD)"

  if check_for_gh_branch "logr" "$repo" "$branch"; then
    msg_info "Stopping Services"
    systemctl stop logr-queue logr-scheduler nginx
    msg_ok "Stopped Services"

    msg_info "Backing up Database"
    mkdir -p /opt/logr-data/backups
    sqlite3 /opt/logr-data/database/database.sqlite ".backup '/opt/logr-data/backups/database-$(date +%Y%m%d-%H%M%S).sqlite'"
    # Keep the 5 most recent backups
    find /opt/logr-data/backups -name 'database-*.sqlite' -printf '%T@ %p\n' | sort -rn | tail -n +6 | cut -d' ' -f2- | xargs -r rm -f
    msg_ok "Backed up Database"

    fetch_and_deploy_gh_branch "logr" "$repo" "$branch" "/opt/logr"

    msg_info "Updating ${APP}"
    cd /opt/logr
    # git reset may bring back the tracked storage/app directory in place of the link
    rm -rf /opt/logr/storage/app
    ln -s /opt/logr-data/storage /opt/logr/storage/app
    ln -sf /opt/logr-data/database/database.sqlite /opt/logr/database/database.sqlite
    ln -sf /opt/logr-data/.env /opt/logr/.env
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --no-dev --optimize-autoloader --no-interaction
    $STD npm ci
    $STD npm run build
    rm -rf node_modules
    $STD php artisan migrate --force
    $STD php artisan storage:link --force
    $STD php artisan optimize:clear
    chown -R www-data:www-data /opt/logr /opt/logr-data
    msg_ok "Updated ${APP}"

    msg_info "Starting Services"
    systemctl start nginx logr-queue logr-scheduler
    systemctl reload php*-fpm
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
