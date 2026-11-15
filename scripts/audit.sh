#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"
        ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
SSH_CONFIG="$(sudo sshd -T)"
check "Вход от имени root запрещён" "no" \
    "$(awk '$1 == "permitrootlogin" {print $2; exit}' <<< "$SSH_CONFIG")"
check "Парольная аутентификация отключена" "no" \
    "$(awk '$1 == "passwordauthentication" {print $2; exit}' <<< "$SSH_CONFIG")"

SSH_PORT="$(awk '$1 == "port" {print $2; exit}' <<< "$SSH_CONFIG")"
if [[ -n "$SSH_PORT" && "$SSH_PORT" != "22" ]]; then
    PORT_IS_NONSTANDARD="yes"
else
    PORT_IS_NONSTANDARD="no"
fi
check "Порт SSH отличается от 22 (фактически: ${SSH_PORT:-не определён})" "yes" "$PORT_IS_NONSTANDARD"

check "Максимум попыток аутентификации равен 3" "3" \
    "$(awk '$1 == "maxauthtries" {print $2; exit}' <<< "$SSH_CONFIG")"

echo "[2] Межсетевой экран"
UFW_STATUS="$(sudo ufw status)"
check "Межсетевой экран активен" "active" \
    "$(awk '/^Status:/ {print $2; exit}' <<< "$UFW_STATUS")"

UFW_DEFAULT="$(sudo ufw status verbose | awk -F': ' '/^Default:/ {if ($2 ~ /^deny \(incoming\),/) print "deny"; else print "other"; exit}')"
check "Политика входящего трафика по умолчанию — deny" "deny" "$UFW_DEFAULT"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
NGINX_STATUS="$(systemctl is-active nginx)"
check "Служба Nginx активна" "active" "$NGINX_STATUS"
check "Виртуальный хост devops.local включён" "yes" "$(test -L /etc/nginx/sites-enabled/devops-site && echo yes || echo no)"
check "Порт HTTP 80 слушается" "yes" "$(sudo ss -ltn | grep -q ":80 " && echo yes || echo no)"
check "Порт HTTPS 443 слушается" "yes" "$(sudo ss -ltn | grep -q ":443 " && echo yes || echo no)"
check "TLS-сертификат существует" "yes" "$(test -s /etc/nginx/ssl/devops.local.crt && echo yes || echo no)"


# Дополнительные проверки веб-сервера по ПР № 6
NGINX_CONFIG_OK="$(sudo nginx -t >/dev/null 2>&1 && echo yes || echo no)"
check "Конфигурация Nginx синтаксически корректна" "yes" "$NGINX_CONFIG_OK"

CERT_VALID="$(sudo openssl x509 -in /etc/nginx/ssl/devops.local.crt -checkend 2592000 -noout >/dev/null 2>&1 && echo yes || echo no)"
check "Сертификат действителен ещё минимум 30 дней" "yes" "$CERT_VALID"

WORLD_WRITABLE="$(find /var/www/devops-site -perm -o+w -print -quit)"
if [[ -z "$WORLD_WRITABLE" ]]; then WORLD_WRITABLE_OK=yes; else WORLD_WRITABLE_OK=no; fi
check "В каталоге сайта нет файлов с записью для всех" "yes" "$WORLD_WRITABLE_OK"

KEY_MODE="$(sudo stat -c "%a" /etc/nginx/ssl/devops.local.key)"
check "Права закрытого ключа равны 600" "600" "$KEY_MODE"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
