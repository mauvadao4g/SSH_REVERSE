#!/bin/bash
# MAUVADAO
# VER: 1.0.0
# DATA: ter 06 out 2026
# PUBLICA UMA PORTA LOCAL NA INTERNET VIA TUNEL SSH REVERSO
#
# Acha sozinho uma porta livre no servidor e liga ela na porta local
# escolhida (padrao 80). Login por chave (a do ~/.ssh/config e achada pelo ip).
#
# Uso:
#   ./server_public.sh root:51.244.242.83          # publica a porta 80 local
#   ./server_public.sh root:51.244.242.83 3000     # publica a porta 3000 local
#   ./server_public.sh root@51.244.242.83:22 8080  # user@host[:porta_ssh]
#   ./server_public.sh vpspro 8080                 # alias do ~/.ssh/config
#   ./server_public.sh -s                          # lista os tuneis ativos
#   ./server_public.sh -p [porta_local]            # para um tunel (ou todos)
#
# Opcoes por variavel:
#   FAIXA=9000-9100 ./server_public.sh ...   # faixa de portas no servidor
#   KEY=~/.ssh/minha ./server_public.sh ...  # forca uma chave

# ========= CONFIG PADRAO =========
PORTA_LOCAL='80'
LOCAL='127.0.0.1'
FAIXA="${FAIXA:-8001-8100}"         # onde procurar porta livre no servidor
KEY="${KEY:-}"
DIR="$HOME/.server_public"          # sockets de controle + info dos tuneis

# ========= FUNCOES =========

_erro() { echo "[ERRO] $*" >&2; exit 1; }

_uso() { sed -n '5,21p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# aceita: user:host[:porta_ssh] | user@host[:porta_ssh] | alias
_set_vars() {
    local ALVO="$1"
    SSH_OPTS=(-o ConnectTimeout=8 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

    if [[ "$ALVO" =~ ^([^:@]+)[:@]([^:@]+)(:([0-9]+))?$ ]]; then
        USUARIO="${BASH_REMATCH[1]}"; VPS="${BASH_REMATCH[2]}"
        DESTINO="$USUARIO@$VPS"
        [[ -n "${BASH_REMATCH[4]}" ]] && SSH_OPTS+=(-p "${BASH_REMATCH[4]}")
        [[ -z "$KEY" ]] && KEY=$(_achar_key "$USUARIO" "$VPS")
    elif [[ "$ALVO" =~ ^[^:@]+$ ]]; then
        DESTINO="$ALVO"
        VPS=$(ssh -G "$ALVO" 2>/dev/null | awk '$1=="hostname"{print $2}')
    else
        _erro "servidor invalido: '$ALVO' (use user:host)"
    fi

    [[ -n "$KEY" ]] && SSH_OPTS+=(-i "${KEY/#\~/$HOME}" -o IdentitiesOnly=yes)
    [[ "$PORTA_LOCAL" =~ ^[0-9]+$ ]] || _erro "porta local invalida: '$PORTA_LOCAL'"
    SOCK="$DIR/$PORTA_LOCAL.sock"
}

# procura no ~/.ssh/config um Host com esse ip+usuario e devolve a chave dele
_achar_key() {
    local ALIAS CFG
    for ALIAS in $(awk 'tolower($1)=="host"{for(i=2;i<=NF;i++) if($i !~ /[*?]/) print $i}' "$HOME/.ssh/config" 2>/dev/null); do
        CFG=$(ssh -G "$ALIAS" 2>/dev/null)
        [[ $(awk '$1=="hostname"{print $2}' <<< "$CFG") == "$2" &&
           $(awk '$1=="user"{print $2}' <<< "$CFG") == "$1" ]] || continue
        awk '$1=="identityfile"{print $2; exit}' <<< "$CFG"
        return
    done
}

_ssh() { ssh "${SSH_OPTS[@]}" "$DESTINO" "$@"; }

_ativo() { [[ -S "$1" ]] && ssh -S "$1" -O check x 2>/dev/null; }

# primeira porta da FAIXA que nao esta escutando no servidor (pula as ja tentadas)
_porta_livre() {
    local USADAS P
    USADAS=$(_ssh "ss -ltnH 2>/dev/null || netstat -ltn" | grep -oE ':[0-9]+ ' | tr -d ': ' | sort -u)
    for ((P=${FAIXA%-*}; P<=${FAIXA#*-}; P++)); do
        grep -qx "$P" <<< "$USADAS"$'\n'"$TENTADAS" || { echo "$P"; return; }
    done
}

_iniciar() {
    mkdir -p "$DIR"
    _ativo "$SOCK" && _erro "a porta local $PORTA_LOCAL ja esta publicada: $(cat "$DIR/$PORTA_LOCAL.info" 2>/dev/null) (pare com: $0 -p $PORTA_LOCAL)"
    rm -f "$SOCK"

    echo "[+] Testando servidor ($DESTINO)..."
    _ssh true 2>/dev/null || _erro "sem acesso por chave em $DESTINO (confira a chave ou use KEY=caminho)"

    ss -ltn | grep -q ":$PORTA_LOCAL " || echo "[!] Nada escutando em $LOCAL:$PORTA_LOCAL ainda; o tunel sobe mesmo assim"

    local i SAIDA
    for i in 1 2 3 4 5; do
        PORTA_REMOTA=$(_porta_livre)
        [[ -n "$PORTA_REMOTA" ]] || _erro "nenhuma porta livre em $FAIXA no servidor"
        echo "[+] Porta livre no servidor: $PORTA_REMOTA"

        SAIDA=$(ssh "${SSH_OPTS[@]}" -f -N -M -S "$SOCK" \
            -R "0.0.0.0:$PORTA_REMOTA:$LOCAL:$PORTA_LOCAL" \
            -o ExitOnForwardFailure=yes \
            -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
            "$DESTINO" 2>&1) && break

        # alguem pegou a porta no meio do caminho: tenta a proxima
        [[ "$SAIDA" == *"remote port forwarding failed"* ]] || _erro "$SAIDA"
        TENTADAS+="$PORTA_REMOTA"$'\n'; PORTA_REMOTA=''
    done
    [[ -n "$PORTA_REMOTA" ]] || _erro "nao consegui abrir nenhuma porta no servidor"

    echo "$VPS:$PORTA_REMOTA" > "$DIR/$PORTA_LOCAL.info"
    _conferir
    echo "[OK] $LOCAL:$PORTA_LOCAL publicado em $VPS:$PORTA_REMOTA"
    echo "     http://$VPS:$PORTA_REMOTA"
    echo "     parar: $0 -p $PORTA_LOCAL"
}

# o servidor abriu pra fora (GatewayPorts) e a porta chega da internet?
_conferir() {
    _ssh "ss -ltnH | grep ':$PORTA_REMOTA '" 2>/dev/null | grep -qE '(0\.0\.0\.0|\*|\[::\]):' || {
        echo "[!] O servidor abriu a porta so em 127.0.0.1 (de fora nao acessa)."
        echo "    Ative 'GatewayPorts yes' no /etc/ssh/sshd_config de la e recarregue o sshd."
        return
    }
    timeout 6 bash -c "exec 3<>/dev/tcp/$VPS/$PORTA_REMOTA" 2>/dev/null ||
        echo "[!] Porta aberta no servidor, mas nao chega de fora (firewall liberando $PORTA_REMOTA?)"
}

_status() {
    local S P N=0
    for S in "$DIR"/*.sock; do
        [[ -S "$S" ]] || continue
        P=$(basename "$S" .sock)
        if _ativo "$S"; then
            echo "[OK] $LOCAL:$P -> $(cat "$DIR/$P.info" 2>/dev/null)"; N=$((N+1))
        else
            rm -f "$S" "$DIR/$P.info"
        fi
    done
    [[ $N -gt 0 ]] || { echo "[!] Nenhum tunel ativo"; return 1; }
}

_parar() {
    local S P N=0
    for S in "$DIR"/${1:-*}.sock; do
        [[ -S "$S" ]] || continue
        P=$(basename "$S" .sock)
        _ativo "$S" && ssh -S "$S" -O exit x 2>/dev/null &&
            { echo "[OK] Parado: $LOCAL:$P -> $(cat "$DIR/$P.info" 2>/dev/null)"; N=$((N+1)); }
        rm -f "$S" "$DIR/$P.info"
    done
    [[ $N -gt 0 ]] || echo "[!] Nenhum tunel pra parar"
}

# ========= PARAMETROS =========

case "$1" in
    -s|status)    _status ;;
    -p|stop)      _parar "$2" ;;
    ''|-h|--help) _uso ;;
    *)
        [[ -n "$2" ]] && PORTA_LOCAL="$2"
        _set_vars "$1"
        _iniciar
    ;;
esac
