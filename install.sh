#!/usr/bin/env bash
#
# install_myapp.sh – «всё-в-одном»: установка *или* удаление
#                    (Ubuntu 24, root-only, amd64/arm64)

set -euo pipefail

GITHUB_OWNER="base-cloud-engine"           # ← замените
GITHUB_REPO="bce-installer-dl"             # ← замените
BIN_BASENAME="bce-installer"             # ← замените (без -linux-amd64)

SERVICE_NAME="bce-installer.service"
BIN_PATH="/usr/local/bin/${BIN_BASENAME}"

uninstall() {
  echo "⏹  Останавливаем службу (если запущена)…"
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true

  echo "🚫  Отключаем автозапуск…"
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true

  echo "🗑  Удаляем unit-файл…"
  rm -f "/etc/systemd/system/$SERVICE_NAME"

  echo "🗑  Удаляем бинарь…"
  rm -f "$BIN_PATH"

  echo "🔄  Обновляем кэш systemd…"
  systemctl daemon-reload

  echo "✅  Приложение удалено.  (Если OVN больше не нужен, выполните:"
  echo "    sudo apt purge openvswitch-switch ovn-common ovn-central && sudo apt autoremove )"
}

## ----- Проверка root и Ubuntu 24 ----------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Скрипт должен запускаться от root." >&2
  exit 1
fi

source /etc/os-release
if [[ ${ID:-} != "ubuntu" || ${VERSION_ID:-} != 24.* ]]; then
  echo "Поддерживается только Ubuntu 24.*" >&2
  exit 1
fi

## ----- Режим удаления ----------------------------------------------------
if [[ ${1:-} == "--uninstall" ]]; then
  uninstall
  exit 0
fi

## ----- Помощь / проверка аргументов для установки ------------------------
usage() {
  echo "Использование:"
  echo "  $0 --shard-id=<id> --storage-url=<url> --informer-url=<url>"
  echo "  $0 --uninstall"
  exit 1
}
[[ $# -eq 3 ]] || usage
ARGS=("$@")          # передаём как есть в ExecStart

## ----- Определяем архитектуру и URL релиза ------------------------------
ARCH_RAW=$(dpkg --print-architecture)     # amd64 или arm64
case "$ARCH_RAW" in
  amd64)  BIN_FILE="${BIN_BASENAME}-linux-amd64" ;;
  arm64|aarch64) BIN_FILE="${BIN_BASENAME}-linux-arm64" ;;
  *)  echo "Неподдерживаемая архитектура: $ARCH_RAW" >&2; exit 1 ;;
esac
BIN_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/v0.0.1/download/${BIN_FILE}"

## ----- Устанавливаем зависимости ----------------------------------------
apt-get update
DEBIAN_FRONTEND=noninteractive \
apt-get install -y --no-install-recommends \
  openvswitch-switch ovn-common ovn-central \
  curl

## ----- Скачиваем бинарь --------------------------------------------------
echo "⬇️  Скачиваем ${BIN_URL}"
curl -fsSL "$BIN_URL" -o "$BIN_PATH"
chmod +x "$BIN_PATH"

## ----- Создаём systemd-unit ---------------------------------------------
cat >"/etc/systemd/system/${SERVICE_NAME}" <<EOF
[Unit]
Description=My-bin service (auto-installed)
After=network.target ovn-central.service
Requires=ovn-central.service

[Service]
Type=simple
ExecStart=${BIN_PATH} ${ARGS[*]}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

## ----- Активируем --------------------------------------------------------
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

echo "✅ Установка завершена. Статус:"
systemctl --no-pager status "$SERVICE_NAME"
