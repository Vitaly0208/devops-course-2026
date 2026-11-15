#!/usr/bin/env bash
# Доставка статического сайта на devops-vm
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

DRY_RUN=0
if [[ $# -eq 1 && "$1" == "--dry-run" ]]; then
    DRY_RUN=1
elif [[ $# -ne 0 ]]; then
    echo "Использование: scripts/deploy.sh [--dry-run]" >&2
    exit 2
fi

if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: ${LOCAL_DIR}index.html не найден; доставка отменена." >&2
    exit 1
fi

if [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения; доставка отменена." >&2
    exit 1
fi

RSYNC_ARGS=(-avz --delete --chmod=D755,F644
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5")

if [[ "$DRY_RUN" -eq 1 ]]; then
    rsync "${RSYNC_ARGS[@]}" --dry-run \
        "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"
    exit 0
fi

if [[ ! -r "$CA_CERT" ]]; then
    echo "Ошибка: сертификат не найден или недоступен: $CA_CERT" >&2
    exit 1
fi

rsync "${RSYNC_ARGS[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"

if ! curl --cacert "$CA_CERT" --fail --silent --show-error \
    --max-time 10 "$SITE_URL" -o /dev/null; then
    echo "Ошибка: сайт не прошёл проверку доступности по HTTPS." >&2
    exit 1
fi

COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
echo "Деплой выполнен успешно. Commit: $COMMIT"
