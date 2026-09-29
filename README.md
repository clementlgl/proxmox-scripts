# proxmox-scripts

Scripts d'installation de LXC Proxmox VE pour des apps absentes de [community-scripts](https://community-scripts.org/), sur le même modèle.

Ils s'appuient sur le moteur officiel [community-scripts/core](https://github.com/community-scripts/core) (assistant de création du CT, gestion d'erreurs, helpers `setup_php`, `setup_nodejs`…) : seuls les scripts `ct/` et `install/` viennent de ce dépôt, via `_CS_DEFAULT_URL` — le mécanisme utilisé par [ProxmoxVED](https://github.com/community-scripts/ProxmoxVED).

## Scripts

| App | Commande (sur le nœud Proxmox) |
|---|---|
| [Logr](https://logr.beer) — suivi de dégustation de bières, [fork](https://github.com/clementlgl/logr-app) avec scan de code-barres + Open Food Facts | `bash -c "$(curl -fsSL https://raw.githubusercontent.com/clementlgl/proxmox-scripts/main/ct/logr.sh)"` |

## Logr

- Debian 13, unprivileged, 2 vCPU / 2 Go RAM / 6 Go disque (la RAM sert au build des assets à l'install et aux mises à jour).
- Install native, sans Docker : PHP 8.4-FPM + nginx (port 80), SQLite, Node 22 pour compiler les assets (`node_modules` supprimé ensuite).
- Code : `/opt/logr` (checkout git de la branche suivie). Données : `/opt/logr-data` (`.env`, base SQLite, fichiers envoyés, backups), reliées par liens symboliques.
- Services : `nginx`, `php8.4-fpm`, `logr-queue` (jobs en file), `logr-scheduler` (tâches planifiées).
- Premier accès : `http://<ip>/setup` pour créer le compte admin.

Dépôt et branche installés : `clementlgl/logr-app`, branche `feat/barcode-scanner` (`LOGR_REPO` / `LOGR_BRANCH` en tête de `install/logr-install.sh`). Le moteur ne transmet pas les variables du nœud au CT : pour une autre source, modifier ces deux valeurs dans un fork de ce dépôt.

Mise à jour : commande `update` dans le CT. Suit la branche installée, sauvegarde la base dans `/opt/logr-data/backups` (5 dernières gardées), redéploie, rebuild, applique les migrations.

Derrière un reverse proxy HTTPS : `TRUSTED_PROXIES=*` est déjà dans `/opt/logr-data/.env` (à restreindre à l'IP du proxy), mettre `APP_URL=https://…` puis `systemctl restart php8.4-fpm logr-queue logr-scheduler`. La caméra (scan) exige HTTPS.

## Licence

MIT
