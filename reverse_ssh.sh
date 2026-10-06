#!/usr/bin/env bash
set -euo pipefail

# Host SSH remoto (deve existir em ~/.ssh/config, ex: "ssh vpspro")
REMOTE_HOST="${REMOTE_HOST:-vpspro}"
# Porta que ficará aberta NO SERVIDOR REMOTO (GatewayPorts yes lá expõe em 0.0.0.0)
REMOTE_PORT="${REMOTE_PORT:-2222}"
# Porta local que será exposta (SSH = 22)
LOCAL_PORT="${LOCAL_PORT:-22}"

SCRIPT_PATH="$(readlink -f "$0")"
STATE_DIR="${HOME}/.reverse_ssh"
PID_FILE="${STATE_DIR}/reverse_ssh.pid"
LOG_FILE="${STATE_DIR}/reverse_ssh.log"
UNIT_DIR="${HOME}/.config/systemd/user"
UNIT_FILE="${UNIT_DIR}/reverse-ssh.service"
mkdir -p "$STATE_DIR"

SSH_OPTS=(
  -N
  -R "${REMOTE_PORT}:localhost:${LOCAL_PORT}"
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
  -o ExitOnForwardFailure=yes
  -o StrictHostKeyChecking=accept-new
)

is_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

# Executa o túnel em foreground (usado internamente pelo systemd e pelo nohup do start)
do_run() {
  if command -v autossh >/dev/null 2>&1; then
    export AUTOSSH_GATETIME=0
    exec autossh -M 0 "${SSH_OPTS[@]}" "$REMOTE_HOST"
  else
    exec ssh "${SSH_OPTS[@]}" "$REMOTE_HOST"
  fi
}

do_start() {
  if is_running; then
    echo "[reverse_ssh] já está rodando (PID $(cat "$PID_FILE"))."
    return 0
  fi
  nohup "$SCRIPT_PATH" run >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  disown
  sleep 1
  if is_running; then
    echo "[reverse_ssh] iniciado (PID $(cat "$PID_FILE")). Log: $LOG_FILE"
  else
    echo "[reverse_ssh] falha ao iniciar, veja $LOG_FILE" >&2
    exit 1
  fi
}

do_stop() {
  if ! is_running; then
    echo "[reverse_ssh] não está rodando."
    rm -f "$PID_FILE"
    return 0
  fi
  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  # cobre o processo ssh filho do autossh, caso o PID registrado seja do pai
  pkill -f -- "-R ${REMOTE_PORT}:localhost:${LOCAL_PORT}" 2>/dev/null || true
  rm -f "$PID_FILE"
  echo "[reverse_ssh] parado."
}

do_status() {
  if is_running; then
    echo "[reverse_ssh] rodando (PID $(cat "$PID_FILE"))."
  else
    echo "[reverse_ssh] parado."
    exit 1
  fi
}

# Garante GatewayPorts yes no sshd remoto (idempotente), para permitir acesso de fora do vpspro
do_configure_remote() {
  echo "[reverse_ssh] verificando GatewayPorts em ${REMOTE_HOST}..."
  ssh "$REMOTE_HOST" '
    set -e
    if ! sudo -n true 2>/dev/null; then
      echo "[reverse_ssh] sudo requer senha em '"$REMOTE_HOST"'; ajuste GatewayPorts manualmente." >&2
      exit 1
    fi
    if sudo grep -qE "^GatewayPorts[[:space:]]+yes" /etc/ssh/sshd_config; then
      echo "[reverse_ssh] GatewayPorts já está yes."
      exit 0
    fi
    if sudo grep -qE "^#?GatewayPorts" /etc/ssh/sshd_config; then
      sudo sed -i -E "s/^#?GatewayPorts.*/GatewayPorts yes/" /etc/ssh/sshd_config
    else
      echo "GatewayPorts yes" | sudo tee -a /etc/ssh/sshd_config >/dev/null
    fi
    sudo sshd -t
    sudo systemctl reload sshd 2>/dev/null || sudo systemctl reload ssh
    echo "[reverse_ssh] GatewayPorts ajustado para yes e sshd recarregado."
  '
}

# Instala/atualiza o serviço systemd --user para o túnel sobreviver a reboot e reiniciar sozinho
do_install_service() {
  mkdir -p "$UNIT_DIR"
  cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Reverse SSH tunnel (expõe porta ${LOCAL_PORT} local via ${REMOTE_HOST}:${REMOTE_PORT})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SCRIPT_PATH} run
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now reverse-ssh.service
  loginctl enable-linger "$USER" 2>/dev/null || echo "[reverse_ssh] não foi possível habilitar linger automaticamente; rode: loginctl enable-linger $USER" >&2

  echo "[reverse_ssh] serviço instalado: $UNIT_FILE"
  echo "[reverse_ssh] use: systemctl --user status reverse-ssh.service"
}

case "${1:-}" in
  start)            do_start ;;
  stop)              do_stop ;;
  status)            do_status ;;
  restart)           do_stop; sleep 1; do_start ;;
  run)               do_run ;;
  configure-remote)  do_configure_remote ;;
  install-service)   do_install_service ;;
  *)
    echo "Uso: $0 <start|stop|status|restart|configure-remote|install-service>" >&2
    exit 1
    ;;
esac
