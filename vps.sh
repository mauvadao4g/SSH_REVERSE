#!/bin/bash
# MAUVADAO
# VER: 1.0.0
# DATA: dom 20 set 2026 08:10:24 -03

SSH_OPTS=(
  -o PreferredAuthentications=publickey
  -o PubkeyAuthentication=yes
  -o PasswordAuthentication=no
  -o StrictHostKeyChecking=no
)

declare -A SERVERS=(
  [vps1]="151.244.242.198:22:root:$HOME/.ssh/vps877"
  [vps2]="151.244.242.173:22:root:$HOME/.ssh/vps878"
  [vps3]="151.244.242.83:22:root:$HOME/.ssh/vps946"
  [vpspro]="151.244.242.83:22:root:$HOME/.ssh/vps946"
  [hst]="45.132.157.206:65002:u785023410:$HOME/.ssh/hst"
  [deco1]="192.168.1.128:8022:u0_a60:$HOME/.ssh/deco1"
  [deco2]="192.168.1.128:8022:u0_a58:$HOME/.ssh/deco2"
  [rp3]="151.244.242.83:22:luiz:$HOME/.ssh/rp3"
)

# ============================================================
# CRIA / CONFIGURA CHAVE SSH
# ============================================================

create_chave() {
  local key="$1"
  local host="$2"
  local port="$3"
  local user="$4"
  local name="$5"

  local ssh_dir="$HOME/.ssh"
  local config="$ssh_dir/config"

  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"

  # --------------------------------------------------------
  # Gera a chave se não existir
  # --------------------------------------------------------

  if [[ ! -f "$key" ]]; then
    echo "[+] Chave não existe: $key"
    echo "[+] Gerando chave SSH..."

    ssh-keygen \
      -t ed25519 \
      -f "$key" \
      -N "" \
      -C "$name" || {
      echo "[FAIL] Erro ao gerar a chave SSH."
      return 1
    }

    echo "[OK] Chave criada: $key"
  else
    echo "[OK] Chave já existe: $key"
  fi

  # --------------------------------------------------------
  # Verifica chave pública
  # --------------------------------------------------------

  if [[ ! -f "${key}.pub" ]]; then
    echo "[FAIL] Chave pública não encontrada: ${key}.pub"
    return 1
  fi

  # --------------------------------------------------------
  # Configura ~/.ssh/config
  # --------------------------------------------------------

  touch "$config"
  chmod 600 "$config"

  if grep -qE "^[[:space:]]*Host[[:space:]]+$name([[:space:]]|\$)" "$config"; then
    echo "[OK] Host '$name' já existe em ~/.ssh/config."
  else
    [[ -s "$config" ]] && cp "$config" "$config.bkp.$(date +%Y%m%d%H%M%S)"

    cat >>"$config" <<EOF

Host $name
    HostName $host
    Port $port
    User $user
    IdentityFile $key
    IdentitiesOnly yes
    StrictHostKeyChecking no
EOF

    chmod 600 "$config"

    echo "[OK] Host '$name' adicionado ao ~/.ssh/config."
  fi

  # --------------------------------------------------------
  # Testa autenticação usando a chave
  # --------------------------------------------------------

  echo "[+] Testando acesso SSH..."

  if ssh \
    -p "$port" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -i "$key" \
    "${user}@${host}" \
    exit 2>/dev/null; then
    echo "[OK] Chave já está instalada no servidor."
    return 0
  fi

  # --------------------------------------------------------
  # Instala chave pública
  # --------------------------------------------------------

  echo "[+] Chave ainda não está instalada."
  echo "[+] Copiando chave pública para ${user}@${host}..."

  ssh-copy-id \
    -p "$port" \
    -o IdentitiesOnly=yes \
    -i "${key}.pub" \
    "${user}@${host}" || {
    echo "[FAIL] Erro ao copiar a chave para o servidor."
    return 1
  }

  echo "[OK] Chave pública instalada."
}

# ============================================================
# SSH
# ============================================================

_ssh() {
  local server="$1"

  local host port user key

  IFS=: read -r host port user key <<<"${SERVERS[$server]}"

  # O nome do Host no ~/.ssh/config será o nome do servidor.
  create_chave "$key" "$host" "$port" "$user" "$server" || return 1

  echo
  echo "[+] Conectando em $server..."
  echo

  ssh \
    "${SSH_OPTS[@]}" \
    -i "$key" \
    -p "$port" \
    "$user@$host"
}

# ============================================================
# MAIN
# ============================================================

server="${1,,}"

if [[ -n "${SERVERS[$server]:-}" ]]; then

  _ssh "$server"

else

  printf '\e[1;36mServidores disponíveis:\e[0m\n\n'

  for server in vps1 vps2 vpspro hst; do

    IFS=: read -r host port user key <<<"${SERVERS[$server]}"

    printf '\e[1;36m%-8s\e[0m %s@%s:%s\n' \
      "$server" "$user" "$host" "$port"

    printf '         Chave: %s\n\n' "$key"
  done

fi
