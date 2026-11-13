#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/clementlgl/proxmox-scripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Author: Clément Laigle
# License: MIT
# Source: https://github.com/clementlgl/runlog

APP="Runlog"
var_tags="${var_tags:-running;tracker}"
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
  if [[ ! -d /opt/runlog/.git ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Track whatever repo/branch the container was installed from
  local repo branch
  repo="$(git -C /opt/runlog remote get-url origin | sed -E 's#^https://github.com/##; s#\.git$##')"
  branch="$(git -C /opt/runlog rev-parse --abbrev-ref HEAD)"

  if check_for_gh_branch "runlog" "$repo" "$branch"; then
    # Restarting the backend kills a running sync: wait for it instead
    if curl -fsS http://127.0.0.1:8000/api/sync/current 2>/dev/null | grep -q '"status":"running"'; then
      msg_error "A sync is running in ${APP}: wait for it to finish, then run update again."
      exit
    fi

    msg_info "Stopping Services"
    systemctl stop runlog-frontend runlog-backend
    msg_ok "Stopped Services"

    msg_info "Backing up Database"
    mkdir -p /opt/runlog-data/backups
    if [[ -f /opt/runlog-data/data/runs.duckdb ]]; then
      cp /opt/runlog-data/data/runs.duckdb "/opt/runlog-data/backups/runs-$(date +%Y%m%d-%H%M%S).duckdb"
      # Keep the 5 most recent backups
      find /opt/runlog-data/backups -name 'runs-*.duckdb' -printf '%T@ %p\n' | sort -rn | tail -n +6 | cut -d' ' -f2- | xargs -r rm -f
    fi
    chown -R runlog:runlog /opt/runlog-data/backups
    msg_ok "Backed up Database"

    fetch_and_deploy_gh_branch "runlog" "$repo" "$branch" "/opt/runlog"

    msg_info "Updating ${APP}"
    cd /opt/runlog/backend
    [[ -x .venv/bin/python ]] || $STD uv venv --python /usr/bin/python3 .venv
    $STD uv pip install --python .venv/bin/python -r pyproject.toml
    cd /opt/runlog/frontend
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    $STD pnpm install --frozen-lockfile
    $STD pnpm run build
    rm -rf node_modules .svelte-kit
    msg_ok "Updated ${APP}"

    msg_info "Starting Services"
    systemctl start runlog-backend runlog-frontend
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
