#!/bin/bash
# MAUVADAO
# VER: 1.0.0
# DATA: ter 06 out 2026
# TUNEL SOCKS5 VIA SSH (usuario/senha) + PROXY DO SISTEMA (GNOME)
#
# Abre um socks5 em 127.0.0.1:8000 saindo pela vps e aponta o proxy do
# sistema pra ele. Ao parar, o proxy do sistema volta pra "nenhum".
#
# Uso:
#   ./socks5_tunel.sh roberto:12345:51.244.242.83:22
#   ./socks5_tunel.sh roberto@12345:51.244.242.83:22
#   ./socks5_tunel.sh roberto 12345 51.244.242.83 22
#   ./socks5_tunel.sh -s     # status + ip de saida
#   ./socks5_tunel.sh -p     # para o tunel e desliga o proxy do sistema
#
# Opcoes por variavel:
#   SOCKS_PORTA=1080 ./socks5_tunel.sh ...   # outra porta local
#   SISTEMA=0 ./socks5_tunel.sh ...          # nao mexe no proxy do sistema

# ========= CONFIG PADRAO =========
SOCKS_HOST='127.0.0.1'
SOCKS_PORTA="${SOCKS_PORTA:-8000}"
SISTEMA="${SISTEMA:-1}"
PORTA='22'
SOCK="$HOME/.ssh/socks5-$SOCKS_PORTA.sock"      # socket de controle (status/parar)
TESTE_IP='https://api.ipify.org'

# ========= FUNCOES =========

_erro() { echo "[ERRO] $*" >&2; exit 1; }

_uso() { sed -n '5,19p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# aceita: user:senha:host:porta | user@senha:host:porta | user senha host [porta]
_set_vars() {
    if [[ $# -ge 3 ]]; then
        USUARIO="$1"; SENHA="$2"; VPS="$3"; [[ -n "$4" ]] && PORTA="$4"
    else
        local RESTO="$1" CRED
        [[ "${RESTO##*:}" =~ ^[0-9]+$ ]] || _erro "faltou a porta em '$1'"
        PORTA="${RESTO##*:}"; RESTO="${RESTO%:*}"
        VPS="${RESTO##*:}";   CRED="${RESTO%:*}"
        [[ "$CRED" != "$RESTO" && "$CRED" =~ ^([^:@]+)[:@](.+)$ ]] || _erro "formato invalido: '$1'"
        USUARIO="${BASH_REMATCH[1]}"; SENHA="${BASH_REMATCH[2]}"
    fi
    [[ -n "$USUARIO" && -n "$SENHA" && -n "$VPS" && "$PORTA" =~ ^[0-9]+$ ]] || _erro "parametros invalidos"
}

_ativo() { [[ -S "$SOCK" ]] && ssh -S "$SOCK" -O check x 2>/dev/null; }

_ip_saida() { curl -s --max-time 10 --socks5-hostname "$SOCKS_HOST:$SOCKS_PORTA" "$TESTE_IP"; }

_proxy_sistema() {
    [[ "$SISTEMA" == 1 ]] && command -v gsettings >/dev/null || return 0
    if [[ "$1" == on ]]; then
        gsettings set org.gnome.system.proxy.socks host "$SOCKS_HOST"
        gsettings set org.gnome.system.proxy.socks port "$SOCKS_PORTA"
        gsettings set org.gnome.system.proxy mode 'manual'
        echo "[+] Proxy do sistema: socks5 $SOCKS_HOST:$SOCKS_PORTA"
    else
        gsettings set org.gnome.system.proxy mode 'none'
        echo "[+] Proxy do sistema: desligado"
    fi
}

_iniciar() {
    command -v sshpass >/dev/null || { echo "[+] Instalando sshpass..."; sudo apt-get install -y sshpass || _erro "falha no apt"; }
    _ativo && _erro "tunel ja esta rodando na porta $SOCKS_PORTA (pare com: $0 -p)"
    ss -ltn | grep -q ":$SOCKS_PORTA " && _erro "porta local $SOCKS_PORTA ja esta em uso (use SOCKS_PORTA=xxxx)"
    rm -f "$SOCK"

    echo "[+] Conectando em $USUARIO@$VPS:$PORTA..."
    local SAIDA
    SAIDA=$(SSHPASS="$SENHA" sshpass -e ssh -f -N -C \
        -M -S "$SOCK" \
        -D "$SOCKS_HOST:$SOCKS_PORTA" \
        -p "$PORTA" \
        -o PreferredAuthentications=password,keyboard-interactive \
        -o PubkeyAuthentication=no \
        -o NumberOfPasswordPrompts=1 \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=10 \
        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        "$USUARIO@$VPS" 2>&1)
    local RC=$?
    SAIDA=$(grep -v 'Permanently added' <<< "$SAIDA")
    if [[ $RC -ne 0 ]]; then
        [[ $RC -eq 5 || "$SAIDA" == *"Permission denied"* ]] && _erro "usuario ou senha incorretos"
        _erro "${SAIDA:-falha na conexao ssh}"
    fi

    echo "[+] Testando o socks5..."
    local IP
    IP=$(_ip_saida)
    [[ -n "$IP" ]] || { ssh -S "$SOCK" -O exit x 2>/dev/null; _erro "tunel abriu mas nao navega (a vps permite TcpForwarding?)"; }

    _proxy_sistema on
    echo "[OK] Tunel socks5 ativo em $SOCKS_HOST:$SOCKS_PORTA | ip de saida: $IP"
    echo "     no terminal: export ALL_PROXY=socks5h://$SOCKS_HOST:$SOCKS_PORTA"
    echo "     parar:       $0 -p"
}

_parar() {
    if _ativo; then
        ssh -S "$SOCK" -O exit x 2>/dev/null
        echo "[OK] Tunel parado"
    else
        echo "[!] Tunel nao estava rodando"
    fi
    rm -f "$SOCK"
    _proxy_sistema off
}

_status() {
    if _ativo; then
        echo "[OK] Tunel rodando em $SOCKS_HOST:$SOCKS_PORTA | ip de saida: $(_ip_saida)"
    else
        echo "[!] Tunel parado"
    fi
    command -v gsettings >/dev/null && echo "     proxy do sistema: $(gsettings get org.gnome.system.proxy mode)"
    _ativo
}

# ========= PARAMETROS =========

case "$1" in
    -s|status)   _status ;;
    -p|stop)     _parar ;;
    ''|-h|--help) _uso ;;
    *)
        _set_vars "$@"
        _iniciar
    ;;
esac
