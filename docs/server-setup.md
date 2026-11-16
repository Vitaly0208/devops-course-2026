# Конфигурация виртуальной машины devops-vm

Сведения зафиксированы по фактической конфигурации VirtualBox, настройкам Ubuntu и результатам команд, выполненных в рамках практической работы № 5.

## 1. Параметры машины

| Параметр | Значение |
|---|---:|
| Операционная система | Ubuntu Server 24.04.5 LTS, 64-bit |
| Оперативная память | 2048 МБ |
| Виртуальные процессоры | 2 |
| Виртуальный диск | 25 600 МБ (25 ГБ), VDI |

## 2. Сетевые интерфейсы

| Интерфейс | Тип адаптера VirtualBox | Адрес | Назначение |
|---|---|---|---|
| `enp0s3` | NAT | `10.0.2.15/24` | Исходящий доступ VM в сеть и SSH через перенаправление портов |
| `enp0s8` | Host-only | `192.168.56.102/24` | Прямой доступ с хоста к VM в изолированной сети VirtualBox |

На хостовой Windows имя `devops.local` сопоставлено адресу `192.168.56.102` в файле `C:\Windows\System32\drivers\etc\hosts`. Полное имя узла в Ubuntu: `devops-vm.devops.local`.

## 3. Правило проброса портов

Адаптер 1 (NAT), правило `ssh`, TCP: `127.0.0.1:2222` на хосте перенаправляется на порт `2222` гостевой системы. Правило проверено через `VBoxManage showvminfo`.

## 4. Учётные записи

| Имя | Группы / назначение | Способ аутентификации SSH |
|---|---|---|
| `devops` | `devops`, `sudo`, `users`; основная административная учётная запись для практик | Ключ Ed25519; публичный ключ находится в `/home/devops/.ssh/authorized_keys` |
| `student` | Первоначальная учебная учётная запись, использовавшаяся при настройке VM | SSH-доступ ограничен директивой `AllowUsers devops` |
| `root` | Системная учётная запись | Прямой вход по SSH запрещён |

## 5. Служба SSH

Служба работает через `ssh.service`; активация через `ssh.socket` отключена. Основной файл `/etc/ssh/sshd_config` сохранён как `/etc/ssh/sshd_config.backup`. Изменения внесены в `/etc/ssh/sshd_config.d/99-hardening.conf`.

| Директива | Значение |
|---|---|
| `Port` | `2222` |
| `PermitRootLogin` | `no` |
| `PasswordAuthentication` | `no` |
| `PubkeyAuthentication` | `yes` |
| `PermitEmptyPasswords` | `no` |
| `MaxAuthTries` | `3` |
| `LoginGraceTime` | `30` |
| `AllowUsers` | `devops` |
| `X11Forwarding` | `no` |
| `ClientAliveInterval` | `300` |
| `ClientAliveCountMax` | `2` |

## 6. Правила межсетевого экрана

UFW активен. Политика по умолчанию: входящие соединения — `deny`, исходящие — `allow`, маршрутизируемые — `disabled`.

| Порт / протокол | Действие | Назначение |
|---|---|---|
| `2222/tcp` | `LIMIT IN` | SSH, ограничение частоты подключений |
| `80/tcp` | `ALLOW IN` | HTTP, нужен в практической работе № 6 |
| `443/tcp` | `ALLOW IN` | HTTPS, нужен в практической работе № 6 |

Те же правила UFW применяются и к IPv6.

## 7. Снимки состояния

| Снимок | Момент создания / состояние |
|---|---|
| `01-clean-install` | 10.11.2026, чистая установка Ubuntu Server |
| `02-keys-configured` | 14.11.2026, настроен ключевой доступ SSH для `devops` |
| `03-ssh-hardened` | 14.11.2026, выполнено усиление SSH |
| `04-ufw-and-dns` | 15.11.2026, настроены UFW и имя узла; текущий снимок в VirtualBox |

## Проверка скриптом аудита

Запускать в Ubuntu на VM от пользователя `devops`:

```bash
bash scripts/audit.sh
```

При штатной конфигурации ожидается код возврата `0`. Для предусмотренной заданием отрицательной проверки временно измените `MaxAuthTries` на `10`, примените конфигурацию и снова запустите скрипт: проверка должна завершиться с ненулевым кодом. После проверки верните значение `3` и перезагрузите конфигурацию SSH.

## 8. Веб-сервер и развёртывание сайта

Nginx установлен и запущен как системная служба. Сайт `devops.local` хранится в `/var/www/devops-site`; владельцем файлов является `devops`. Процессы worker Nginx работают от `www-data`: они могут читать файлы сайта, но не могут создавать файлы в каталоге.

Конфигурация виртуального хоста хранится в `/etc/nginx/sites-available/devops-site` и включена ссылкой в `/etc/nginx/sites-enabled/devops-site`. HTTP-запросы перенаправляются с порта 80 на HTTPS, порт 443 обслуживает сайт.

Для учебного HTTPS используется самоподписанный сертификат с SAN `DNS:devops.local`:

- Сертификат: `/etc/nginx/ssl/devops.local.crt`
- Закрытый ключ: `/etc/nginx/ssl/devops.local.key`

Браузер предупреждает, что сертификат не доверен центром сертификации. Это ожидаемо для самоподписанного сертификата. Изначально проверка из WSL выполнялась с `curl -k`; после копирования сертификата сайт проверяется с `curl --cacert ~/devops.crt`.

Исходные файлы сайта `index.html` и `404.html` подготовлены в WSL в `~/devops-site-src` и переданы на VM командой:

```bash
rsync -av ~/devops-site-src/ devops:/var/www/devops-site/
```

Основные проверки (команды curl запускайте из WSL Ubuntu):

```bash
sudo nginx -t
sudo systemctl status nginx --no-pager
curl -k -i https://devops.local
curl -k -i https://devops.local/not-found
```

Ожидаемые результаты: конфигурация Nginx проходит проверку, главная страница возвращает `200 OK`, несуществующий путь — `404 Not Found` с содержимым `404.html`.

### Фактические параметры конфигурации

- Установленный пакет: `nginx`; версия веб-сервера — `1.24.0` на Ubuntu Server `24.04.5 LTS`.
- Конфигурация сайта: `/etc/nginx/sites-available/devops-site`; активна через ссылку `/etc/nginx/sites-enabled/devops-site`.
- Каталог сайта `/var/www/devops-site` принадлежит `devops:devops`, права каталога — `755`; опубликованные HTML-файлы принадлежат `devops:devops`, права — `644`.
- Сертификат `/etc/nginx/ssl/devops.local.crt` принадлежит `root:root`, права — `644`.
- Закрытый ключ `/etc/nginx/ssl/devops.local.key` принадлежит `root:root`, права — `600`.
- Сертификат сформирован на 365 дней командой:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/devops.local.key -out /etc/nginx/ssl/devops.local.crt -subj "/CN=devops.local" -addext "subjectAltName=DNS:devops.local"

```

- Срок действия сертификата: с 15.11.2026 по 15.11.2027 UTC.
- Сертификат скопирован по SSH в WSL как `~/devops.crt`; проверка сайта выполняется командой `curl --cacert ~/devops.crt https://devops.local`.
- Исходники сайта находятся в `site/` репозитория. Доставка выполняется `scripts/deploy.sh`; режим просмотра плана — `scripts/deploy.sh --dry-run`. Сценарий устанавливает права `755` для каталогов и `644` для файлов.
## 9. Docker

Docker Engine и Compose plugin установлены на Ubuntu VM из официального репозитория Docker:

```bash
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops
```

После изменения групп пользователь `devops` повторно вошёл в систему. Членство в группе `docker` даёт права, эквивалентные `root`, поэтому добавлять в неё следует только доверенных пользователей.

### Образ приложения

Исходники находятся в `app/`. Образ собирается на VM:

```bash
cd ~/app
docker build -t devops-app:1.0 .
docker image ls devops-app
docker history devops-app:1.0
```

Dockerfile устанавливает зависимости из `requirements.txt` отдельным слоем для повторного использования кэша. Gunicorn запускает Flask от непривилегированного пользователя `app`. Маршрут `/health` проверяет доступность приложения, а `/` записывает посещение в PostgreSQL и возвращает счётчик.

### Docker Compose и секреты

Файл `app/docker-compose.yml` описывает сервисы `app` и `db`. PostgreSQL использует закреплённый образ `postgres:16-alpine`, healthcheck и именованный том `app_db_data`. Приложение подключается к БД по имени сервиса `db`; `depends_on` с условием `service_healthy` ожидает готовности БД.

В Git хранится только шаблон `app/.env.example`. Настоящий `app/.env` создаётся на VM со случайным паролем, имеет права `600` и исключён из Git правилом `.env` в `.gitignore`. Секреты нельзя включать в образ или коммитить.

Запуск и проверка сервисов:

```bash
docker compose up -d --build
docker compose ps
curl -s http://127.0.0.1:5000/health
curl -s http://127.0.0.1:5000/
```

Порт приложения опубликован только на `127.0.0.1:5000`; PostgreSQL порт `5432` на хост не опубликован. Docker может создавать NAT-правила, обходящие ожидаемую политику UFW, поэтому привязку к loopback необходимо сохранять. Nginx обслуживает HTTPS и проксирует `/app/` на `http://127.0.0.1:5000/`.

Обычный `docker compose down` удаляет контейнеры и сеть, сохраняя том БД. Команда `docker compose down -v` удаляет том и данные посещений; применять её следует только при намеренном сбросе тестовой БД. Для восстановления после теста 502 приложение запускается командой `docker compose start app`.

Для практической работы создан снимок VirtualBox `05-docker-compose`.
