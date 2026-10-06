# SSH_REVERSE

Scripts de túnel SSH para máquinas sem IP público. Todos usam uma VPS com IP
público (a `vpspro`, `151.244.242.83`) como ponto de passagem.

| Script | Para que serve | Fica rodando como |
|---|---|---|
| [`rp3_sshReverse.sh`](#rp3_sshreversesh) | Acessar o SSH de uma Raspberry de fora de casa | serviço systemd (permanente) |
| [`pc_sshReverse.sh`](#pc_sshreversesh) | Acessar o SSH deste PC de fora de casa | serviço systemd de usuário (permanente) |
| [`reverse_ssh.sh`](#reverse_sshsh) | Mesmo objetivo do anterior, versão antiga (é a que está ativa neste PC) | serviço systemd de usuário (permanente) |
| [`server_public.sh`](#server_publicsh) | Publicar na internet uma porta local qualquer (site, API...) | processo em segundo plano (temporário) |
| [`socks5_tunel.sh`](#socks5_tunelsh) | Navegar saindo pelo IP de um servidor (proxy SOCKS5) | processo em segundo plano (temporário) |

## Como funciona

**Túnel reverso** (`rp3_sshReverse`, `pc_sshReverse`, `reverse_ssh`, `server_public`):
a máquina de casa conecta na VPS e pede para ela abrir uma porta. Tudo que
chegar nessa porta da VPS é entregue na porta local.

```
quem está fora ──► VPS:2223 ══(túnel aberto pela Raspberry)══► Raspberry:22
```

**Túnel SOCKS5** (`socks5_tunel`): é o caminho contrário. O PC abre uma porta
local e tudo que entrar nela sai para a internet pelo servidor.

```
navegador ──► 127.0.0.1:8000 ══(túnel)══► servidor ──► internet
```

## Requisitos

- Linux com `bash`, `ssh` e `systemd` (testado em Ubuntu 24.04).
- `autossh` e `sshpass`: os scripts instalam via `apt` se faltar (pede sudo).
- Chave da VPS em `~/.ssh/vps946` (e `vps946.pub`). É a chave usada pelo alias
  `vpspro` do `~/.ssh/config`.
- Na VPS: `GatewayPorts yes` no `/etc/ssh/sshd_config`. Sem isso a porta abre
  só em `127.0.0.1` da VPS e não é acessível de fora. A `vpspro` já está assim.

## Portas em uso na vpspro

| Porta | Aponta para | Criado por |
|---|---|---|
| 2222 | SSH deste PC | `reverse_ssh.sh` (serviço `reverse-ssh`) |
| 2223 | SSH da Raspberry (`rp3`) | `rp3_sshReverse.sh` (serviço `autossh-vpspro` na Raspberry) |
| 8001–8100 | portas locais publicadas | `server_public.sh` (escolhe a primeira livre) |

Ao instalar em uma máquina nova, escolha uma porta fora dessa lista.

---

## rp3_sshReverse.sh

Roda **neste PC** e configura a Raspberry pela rede local. Ele:

1. Copia a chave da VPS para a Raspberry (`~/.ssh/vpspro`).
2. Instala o `autossh` na Raspberry.
3. Cria o serviço `autossh-vpspro` (sobe no boot e reconecta sozinho).
4. Acrescenta o atalho `rp3-ext` no `~/.ssh/config` deste PC.
5. Testa o acesso pela VPS.

```bash
./rp3_sshReverse.sh                     # instala (rp3 -> vpspro:2223)
./rp3_sshReverse.sh luiz@192.168.1.50   # outra Raspberry
./rp3_sshReverse.sh rp3 2224            # outra porta na VPS
./rp3_sshReverse.sh -s [rp]             # status do serviço e da porta na VPS
./rp3_sshReverse.sh -r [rp]             # remove o serviço e a chave da Raspberry
```

O sudo da Raspberry pede senha durante a instalação, então rode em um terminal
interativo.

Acesso depois de instalado:

```bash
ssh rp3-ext                          # deste PC
ssh -p 2223 luiz@151.244.242.83      # de qualquer lugar
```

Pré-requisito: este PC já precisa entrar na Raspberry por chave (`ssh rp3`).

## pc_sshReverse.sh

Roda **no próprio PC** que vai ser acessado de fora. Publica `127.0.0.1:22` na
VPS com um serviço de usuário (`systemctl --user`, com linger para subir no
boot). Não precisa de sudo se `autossh` e `openssh-server` já estiverem
instalados.

```bash
./pc_sshReverse.sh              # instala (127.0.0.1:22 -> vpspro:2222)
./pc_sshReverse.sh 2224         # outra porta na VPS
./pc_sshReverse.sh -s [porta]   # status do serviço e da porta na VPS
./pc_sshReverse.sh -r           # remove o serviço (a chave fica)
```

Acesso depois de instalado:

```bash
ssh -p <porta> <usuario>@151.244.242.83
```

Neste PC a porta 2222 já é do `reverse_ssh.sh`, então o script aborta avisando
que a porta está em uso. Em um PC novo, use outra porta.

## reverse_ssh.sh

Versão anterior do túnel do PC, copiada de `GITHUB/HOSTINGER/`. Faz o mesmo que
o `pc_sshReverse.sh`, com duas diferenças: depende do alias `vpspro` existir no
`~/.ssh/config` e o serviço (`reverse-ssh`) chama o próprio script, então o
arquivo não pode mudar de lugar depois de instalado.

O serviço ativo neste PC aponta para a cópia em
`GITHUB/HOSTINGER/reverse_ssh.sh`, não para a desta pasta.

```bash
./reverse_ssh.sh install-service     # cria e ativa o serviço reverse-ssh
./reverse_ssh.sh configure-remote    # garante GatewayPorts yes na VPS
./reverse_ssh.sh start|stop|restart|status   # controle manual, sem systemd
```

A porta e o servidor mudam por variável: `REMOTE_HOST`, `REMOTE_PORT`,
`LOCAL_PORT` (padrão `vpspro`, `2222`, `22`).

## server_public.sh

Publica uma porta local na internet. O script procura sozinho uma porta livre
no servidor (faixa 8001–8100) e mostra a URL pública no final.

```bash
./server_public.sh root:151.244.242.83          # publica a porta 80 local
./server_public.sh root:151.244.242.83 3000     # publica a porta 3000 local
./server_public.sh root@151.244.242.83:22 8080  # user@host[:porta_ssh]
./server_public.sh vpspro 8080                  # alias do ~/.ssh/config
./server_public.sh -s                           # lista os túneis ativos
./server_public.sh -p [porta_local]             # para um túnel (ou todos)
```

| Variável | Padrão | Efeito |
|---|---|---|
| `FAIXA` | `8001-8100` | faixa de portas procurada no servidor |
| `KEY` | (automática) | força uma chave SSH |

- O login é por chave. Passando `user:ip`, o script acha a chave certa
  procurando no `~/.ssh/config` um Host com o mesmo IP e usuário.
- Dá para publicar várias portas locais ao mesmo tempo; cada uma ganha a sua
  porta no servidor.
- O túnel não é um serviço: não reconecta se cair e não volta depois de
  reiniciar o PC.
- Os dados dos túneis ativos ficam em `~/.server_public/`.

## socks5_tunel.sh

Abre um proxy SOCKS5 em `127.0.0.1:8000` saindo por um servidor SSH (login com
usuário e senha) e aponta o proxy do sistema (GNOME) para ele.

```bash
./socks5_tunel.sh roberto:12345:51.244.242.83:22
./socks5_tunel.sh roberto@12345:51.244.242.83:22
./socks5_tunel.sh roberto 12345 51.244.242.83 22
./socks5_tunel.sh -s     # status e IP de saída
./socks5_tunel.sh -p     # para o túnel e desliga o proxy do sistema
```

| Variável | Padrão | Efeito |
|---|---|---|
| `SOCKS_PORTA` | `8000` | porta local do SOCKS5 |
| `SISTEMA` | `1` | `0` abre o túnel sem mexer no proxy do sistema |

- Navegador e apps gráficos seguem o proxy do sistema. Programas de terminal
  não; para eles use `export ALL_PROXY=socks5h://127.0.0.1:8000`.
- Não reconecta sozinho. Se a conexão cair, o proxy do sistema continua
  apontando para o túnel morto e a navegação para: rode `-p` ou conecte de novo.
- A senha vai na linha de comando e fica no histórico do shell.
- A abertura do túnel com credenciais reais ainda não foi testada; só a leitura
  dos parâmetros e os erros de senha errada e host inalcançável.

---

## Segurança

- **Chave root na Raspberry:** o `rp3_sshReverse.sh` copia a `vps946`, que dá
  acesso root completo à VPS. Quem comprometer a Raspberry ganha a VPS. O mais
  seguro é uma chave própria para o túnel, restrita a port-forwarding.
- **SSH exposto na internet:** com `GatewayPorts yes`, as portas 2222 e 2223
  ficam abertas para qualquer um. Desative login por senha no sshd das máquinas
  publicadas (`PasswordAuthentication no`).
- **`server_public.sh`:** a porta publicada fica aberta para qualquer um
  enquanto o túnel estiver de pé. Pare com `-p` quando terminar.

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `porta XXXX ja esta em uso na vps` | outro túnel já usa a porta | escolher outra porta |
| Porta abre na VPS mas não acessa de fora | `GatewayPorts` desligado ou firewall | `./reverse_ssh.sh configure-remote` e liberar a porta no firewall |
| `sem acesso na vps com ...` | chave ausente ou não autorizada na VPS | conferir `~/.ssh/vps946` e o `authorized_keys` da VPS |
| Túnel da Raspberry não volta | serviço parado | `./rp3_sshReverse.sh -s`, e na Raspberry `journalctl -u autossh-vpspro` |
| Túnel do PC não volta após reiniciar | linger desativado | `sudo loginctl enable-linger $USER` |
| Internet parou depois do SOCKS5 | túnel caiu com o proxy do sistema ligado | `./socks5_tunel.sh -p` |
