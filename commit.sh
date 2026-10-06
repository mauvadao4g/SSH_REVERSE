#!/bin/bash
# BY:  MAUVADAO
# VER:  1.1.0

set -euo pipefail

# Uso: bash commit.sh [mensagem do commit]
# A mensagem é opcional; sem ela o commit fica só com a versão e o timestamp.
MSG="$*"

# Precisa estar dentro de um repositório git
if ! RAIZ="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    echo "Erro: esta pasta não é um repositório git. Rode o createRepo.sh primeiro." >&2
    exit 1
fi
cd "$RAIZ"

if ! git remote get-url origin &>/dev/null; then
    echo "Erro: remote 'origin' não configurado. Rode o createRepo.sh primeiro." >&2
    exit 1
fi

git add -A

# Sem alterações: não gera versão nova, só envia commits pendentes (se houver).
if git diff --cached --quiet; then
    echo "Nada para commitar."
    git push -u origin HEAD
    exit 0
fi

# Descobre a última versão (arquivos ver1, ver2, ver3... na raiz) e apaga as anteriores.
ULTIMA=0
for ARQ in ver*; do
    [[ "$ARQ" =~ ^ver([0-9]+)$ ]] || continue
    NUM="${BASH_REMATCH[1]}"
    [ "$((10#$NUM))" -gt "$ULTIMA" ] && ULTIMA="$((10#$NUM))"
    rm -f -- "$ARQ"
done

VERSAO="ver$((ULTIMA + 1))"
DATA="$(date '+%Y-%m-%d %H:%M:%S')"

TITULO="$VERSAO: $DATA"
[ -n "$MSG" ] && TITULO="$TITULO - $MSG"

# Arquivo marcador do commit gerado: fica somente o da última versão.
echo "$TITULO" > "$VERSAO"

git add -A
git commit -m "$TITULO"
git push -u origin HEAD

echo "Commit $VERSAO enviado."
