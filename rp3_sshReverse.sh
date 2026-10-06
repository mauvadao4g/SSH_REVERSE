#!/bin/bash
# MAUVADAO
# VER: 1.0.0
# DATA: ter 06 out 2026
# TUNEL SSH REVERSO: RASPBERRY -> VPSPRO (autossh + systemd)
#
# Roda AQUI no PC. Copia a chave da vps pra raspberry, instala o autossh
# e cria um servico que mantem a porta 22 da raspberry publicada na vps.
#
# Uso:
#   ./rp3_sshReverse.sh                    # instala (rp3 -> vpspro:2223)
#   ./rp3_sshReverse.sh luiz@192.168.1.50  # outra raspberry
#   ./rp3_sshReverse.sh rp3 2224           # outra porta na vps
#   ./rp3_sshReverse.sh -s [rp]            # status do tunel
#   ./rp3_sshReverse.sh -r [rp]            # remove servico + chave da raspberry

# ========= CONFIG PADRAO =========
RP='rp3'                        # host da raspberry (alias do ~/.ssh/config ou user@ip)
VPS='151.244.242.83'            # vpspro
VPS_USUARIO='root'
VPS_PORTA='22'
VPS_KEY="$HOME/.ssh/vps946"     # chave privada da vpspro aqui no PC (.pub ao lado)
PORTA_REMOTA='2223'             # porta aberta na vps (2222 ja e usada pelo tunel do PC)
PORTA_LOCAL='22'                # ssh da raspberry
KEY_NOME='vpspro'               # nome da chave la na raspberry (~/.ssh/vpspro)
SERVICO='autossh-vpspro'

# ========= FUNCOES =========

_erro() { echo "[ERRO] $*" >&2; exit 1; }

_rp()  { ssh -o ConnectTimeout=8 "$RP" "$@"; }
_vps() { ssh -o ConnectTimeout=8 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
             -i "$VPS_KEY" -p "$VPS_PORTA" "$VPS_USUARIO@$VPS" "$@"; }

_checar() {
    [[ -f "$VPS_KEY" ]]     || _erro "chave nao encontrada: $VPS_KEY"
    [[ -f "$VPS_KEY.pub" ]] || _erro "chave publica nao encontrada: $VPS_KEY.pub"

    echo "[+] Testando raspberry ($RP)..."
    RP_USUARIO=$(_rp -o BatchMode=yes whoami 2>/dev/null | tail -n1)
    [[ -n "$RP_USUARIO" ]] || _erro "sem acesso por chave em '$RP' (rode: ssh $RP)"

    echo "[+] Testando vps ($VPS)..."
    _vps -o BatchMode=yes true 2>/dev/null || _erro "sem acesso na vps com $VPS_KEY"

    # porta ocupada por outro tunel? (ignora se for o nosso servico ja rodando)
    if ! _rp "systemctl is-active --quiet $SERVICO" 2>/dev/null; then
        _vps "ss -ltn | grep -q ':$PORTA_REMOTA '" 2>/dev/null &&
            _erro "porta $PORTA_REMOTA ja esta em uso na vps, escolha outra: $0 $RP <porta>"
    fi
}

_enviar_key() {
    echo "[+] Copiando chave pra raspberry (~/.ssh/$KEY_NOME)..."
    _rp 'mkdir -p ~/.ssh && chmod 700 ~/.ssh' >/dev/null || _erro "falha ao criar ~/.ssh"
    scp -q "$VPS_KEY"     "$RP:.ssh/$KEY_NOME"     || _erro "falha ao copiar a chave"
    scp -q "$VPS_KEY.pub" "$RP:.ssh/$KEY_NOME.pub" || _erro "falha ao copiar a chave publica"
    _rp "chmod 600 ~/.ssh/$KEY_NOME; chmod 644 ~/.ssh/$KEY_NOME.pub" >/dev/null
}

# parte que roda NA raspberry (precisa de sudo -> ssh -t pra pedir a senha)
_instalar_remoto() {
    local TMP="/tmp/$SERVICO.install.sh"

    _rp "cat > $TMP" <<EOF
#!/bin/bash
set -e
KEY="\$HOME/.ssh/$KEY_NOME"

echo "[+] Instalando autossh..."
command -v autossh >/dev/null || { sudo apt-get update -qq; sudo apt-get install -y autossh; }

echo "[+] Testando chave contra a vps..."
ssh -i "\$KEY" -p $VPS_PORTA -o IdentitiesOnly=yes -o BatchMode=yes \\
    -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 $VPS_USUARIO@$VPS true

echo "[+] Criando servico $SERVICO..."
sudo tee /etc/systemd/system/$SERVICO.service >/dev/null <<UNIT
[Unit]
Description=AutoSSH tunel reverso -> $VPS:$PORTA_REMOTA
After=network-online.target
Wants=network-online.target

[Service]
User=\$USER
Environment=AUTOSSH_GATETIME=0
ExecStart=\$(command -v autossh) -M 0 -N \\\\
    -R $PORTA_REMOTA:localhost:$PORTA_LOCAL \\\\
    -i \$KEY -p $VPS_PORTA \\\\
    -o IdentitiesOnly=yes \\\\
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \\\\
    -o ExitOnForwardFailure=yes \\\\
    -o StrictHostKeyChecking=accept-new \\\\
    $VPS_USUARIO@$VPS
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable $SERVICO >/dev/null 2>&1
sudo systemctl restart $SERVICO
sleep 4
systemctl is-active $SERVICO
EOF

    ssh -t "$RP" "bash $TMP; RC=\$?; rm -f $TMP; exit \$RC" || _erro "instalacao na raspberry falhou"
}

_config_local() {
    local HOST_EXT="${RP##*@}-ext" KEY_RP
    [[ "$RP" == *@* || "$RP" == *.* ]] && HOST_EXT="rp-$PORTA_REMOTA-ext"
    KEY_RP=$(ssh -G "$RP" | awk '$1=="identityfile"{print $2; exit}')
    KEY_RP="${KEY_RP/#\~/$HOME}"

    if grep -q "^Host $HOST_EXT\$" "$HOME/.ssh/config" 2>/dev/null; then
        echo "[!] Host $HOST_EXT ja existe no config, pulando"
    else
        echo "[+] Criando entrada '$HOST_EXT' no ~/.ssh/config..."
        cat <<EOF >> "$HOME/.ssh/config"

Host $HOST_EXT
    HostName $VPS
    Port $PORTA_REMOTA
    User $RP_USUARIO
    IdentityFile $KEY_RP
    IdentitiesOnly yes
    StrictHostKeyChecking no

EOF
        chmod 600 "$HOME/.ssh/config"
    fi
    HOST_EXT_NOME="$HOST_EXT"
}

_testar() {
    echo "[+] Testando acesso externo ($VPS:$PORTA_REMOTA)..."
    local i
    for i in 1 2 3 4 5; do
        if ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST_EXT_NOME" true 2>/dev/null; then
            echo "[OK] Tunel funcionando. Use: ssh $HOST_EXT_NOME"
            echo "     ou de qualquer lugar: ssh -p $PORTA_REMOTA $RP_USUARIO@$VPS"
            return 0
        fi
        sleep 3
    done
    _erro "tunel nao respondeu. Veja: $0 -s $RP"
}

_status() {
    echo "== raspberry ($RP) =="
    _rp "systemctl status $SERVICO --no-pager -n 8" 2>&1 | grep -v -e '^=' -e 'ACESSO RESTRITO' -e 'Servidor privado'
    echo
    echo "== vps ($VPS) =="
    _vps "ss -ltnp | grep ':$PORTA_REMOTA ' || echo 'porta $PORTA_REMOTA NAO esta aberta'"
}

_remover() {
    echo "[+] Removendo servico e chave da raspberry ($RP)..."
    ssh -t "$RP" "sudo systemctl disable --now $SERVICO; \
        sudo rm -f /etc/systemd/system/$SERVICO.service; sudo systemctl daemon-reload; \
        rm -f ~/.ssh/$KEY_NOME ~/.ssh/$KEY_NOME.pub" || _erro "falha ao remover"
    echo "[OK] Removido (autossh continua instalado; entrada do ~/.ssh/config local mantida)"
}

# ========= PARAMETROS =========

case "$1" in
    -s) [[ -n "$2" ]] && RP="$2"; [[ -n "$3" ]] && PORTA_REMOTA="$3"; _status ;;
    -r) [[ -n "$2" ]] && RP="$2"; _remover ;;
    -h|--help) sed -n '5,15p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)
        [[ -n "$1" ]] && RP="$1"
        [[ -n "$2" ]] && PORTA_REMOTA="$2"
        _checar
        _enviar_key
        _instalar_remoto
        _config_local
        _testar
    ;;
esac
