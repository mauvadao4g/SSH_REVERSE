#!/bin/bash
# MAUVADAO
# VER: 1.0.0
# DATA: ter 06 out 2026
# TUNEL SSH REVERSO: PC LOCAL (127.0.0.1) -> VPSPRO (autossh + systemd --user)
#
# Roda no proprio PC que vai ser acessado de fora. Instala o autossh (e o
# openssh-server se faltar) e cria um servico de usuario que mantem a porta 22
# deste PC publicada na vps. Nao precisa de sudo se os pacotes ja existirem.
#
# Uso:
#   ./pc_sshReverse.sh           # instala (127.0.0.1:22 -> vpspro:2222)
#   ./pc_sshReverse.sh 2224      # outra porta na vps
#   ./pc_sshReverse.sh -s [porta]  # status do tunel
#   ./pc_sshReverse.sh -r        # remove o servico

# ========= CONFIG PADRAO =========
VPS='151.244.242.83'            # vpspro
VPS_USUARIO='root'
VPS_PORTA='22'
VPS_KEY="$HOME/.ssh/vps946"     # chave privada da vpspro neste PC
PORTA_REMOTA='2222'             # porta aberta na vps (rp3 usa a 2223)
LOCAL='127.0.0.1'
PORTA_LOCAL='22'                # ssh deste PC
SERVICO='autossh-vpspro'
UNIT="$HOME/.config/systemd/user/$SERVICO.service"

# ========= FUNCOES =========

_erro() { echo "[ERRO] $*" >&2; exit 1; }

_vps() { ssh -o ConnectTimeout=8 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
             -i "$VPS_KEY" -p "$VPS_PORTA" "$VPS_USUARIO@$VPS" "$@"; }

_ativo() { systemctl --user is-active --quiet "$SERVICO" 2>/dev/null; }

_pacotes() {
    local FALTA=()
    command -v autossh >/dev/null || FALTA+=(autossh)
    command -v sshd >/dev/null || [[ -x /usr/sbin/sshd ]] || FALTA+=(openssh-server)

    [[ ${#FALTA[@]} -gt 0 ]] && {
        echo "[+] Instalando: ${FALTA[*]}"
        sudo apt-get update -qq && sudo apt-get install -y "${FALTA[@]}" || _erro "falha no apt"
    }

    ss -ltn | grep -q ":$PORTA_LOCAL " || {
        echo "[+] Subindo o ssh local..."
        sudo systemctl enable --now ssh 2>/dev/null || sudo systemctl enable --now sshd
        ss -ltn | grep -q ":$PORTA_LOCAL " || _erro "nada escutando em $LOCAL:$PORTA_LOCAL"
    }
}

_checar() {
    [[ -f "$VPS_KEY" ]] || _erro "chave nao encontrada: $VPS_KEY (copie a chave da vpspro pra ca)"
    chmod 600 "$VPS_KEY"

    echo "[+] Testando vps ($VPS)..."
    _vps -o BatchMode=yes true 2>/dev/null || _erro "sem acesso na vps com $VPS_KEY"

    # porta ocupada por outro tunel? (ignora se for o nosso servico ja rodando)
    if ! _ativo && _vps "ss -ltn | grep -q ':$PORTA_REMOTA '" 2>/dev/null; then
        local OUTRO
        OUTRO=$(pgrep -af -- "-R $PORTA_REMOTA:" | head -n1)
        [[ -n "$OUTRO" ]] && echo "[!] Este PC ja tem um tunel nessa porta: $OUTRO" >&2
        _erro "porta $PORTA_REMOTA ja esta em uso na vps, escolha outra: $0 <porta>"
    fi
}

_instalar() {
    echo "[+] Criando servico $SERVICO..."
    mkdir -p "$(dirname "$UNIT")"
    cat > "$UNIT" <<EOF
[Unit]
Description=AutoSSH tunel reverso $LOCAL:$PORTA_LOCAL -> $VPS:$PORTA_REMOTA
After=network-online.target
Wants=network-online.target

[Service]
Environment=AUTOSSH_GATETIME=0
ExecStart=$(command -v autossh) -M 0 -N \\
    -R $PORTA_REMOTA:$LOCAL:$PORTA_LOCAL \\
    -i $VPS_KEY -p $VPS_PORTA \\
    -o IdentitiesOnly=yes \\
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \\
    -o ExitOnForwardFailure=yes \\
    -o StrictHostKeyChecking=accept-new \\
    $VPS_USUARIO@$VPS
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable "$SERVICO" >/dev/null 2>&1
    systemctl --user restart "$SERVICO" || _erro "servico nao subiu"

    # linger: o servico sobe no boot, sem precisar de login
    loginctl enable-linger "$USER" 2>/dev/null ||
        echo "[!] Nao consegui habilitar o linger; rode: sudo loginctl enable-linger $USER"
}

# confere se quem responde na porta da vps e mesmo este PC (compara a host key)
_testar() {
    echo "[+] Testando acesso externo ($VPS:$PORTA_REMOTA)..."
    local i LOCAL_KEY REMOTA_KEY
    LOCAL_KEY=$(ssh-keyscan -t ed25519 -p "$PORTA_LOCAL" "$LOCAL" 2>/dev/null | awk '{print $3}')
    for i in 1 2 3 4 5; do
        REMOTA_KEY=$(ssh-keyscan -T 5 -t ed25519 -p "$PORTA_REMOTA" "$VPS" 2>/dev/null | awk '{print $3}')
        if [[ -n "$REMOTA_KEY" && "$REMOTA_KEY" == "$LOCAL_KEY" ]]; then
            echo "[OK] Tunel funcionando. De fora use: ssh -p $PORTA_REMOTA $USER@$VPS"
            return 0
        fi
        sleep 3
    done
    _erro "tunel nao respondeu. Veja: $0 -s $PORTA_REMOTA"
}

_status() {
    echo "== pc local ($LOCAL:$PORTA_LOCAL) =="
    systemctl --user status "$SERVICO" --no-pager -n 8 2>&1
    echo
    echo "== vps ($VPS) =="
    _vps "ss -ltnp | grep ':$PORTA_REMOTA ' || echo 'porta $PORTA_REMOTA NAO esta aberta'"
}

_remover() {
    echo "[+] Removendo servico $SERVICO..."
    systemctl --user disable --now "$SERVICO" 2>/dev/null
    rm -f "$UNIT"
    systemctl --user daemon-reload
    systemctl --user reset-failed "$SERVICO" 2>/dev/null
    echo "[OK] Removido (autossh continua instalado; chave $VPS_KEY mantida)"
}

# ========= PARAMETROS =========

case "$1" in
    -s) [[ -n "$2" ]] && PORTA_REMOTA="$2"; _status ;;
    -r) _remover ;;
    -h|--help) sed -n '5,15p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)
        [[ -n "$1" ]] && PORTA_REMOTA="$1"
        _pacotes
        _checar
        _instalar
        _testar
    ;;
esac
