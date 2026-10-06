#!/bin/bash
# BY:  MAUVADAO
# VER:  1.2.0

set -euo pipefail

uso() {
    echo "Uso: $0 <--public|--private>" >&2
    exit 1
}

# Lê a flag de visibilidade
[ $# -eq 1 ] || uso
case "$1" in
    --public)  VISIBILIDADE="--public" ;;
    --private) VISIBILIDADE="--private" ;;
    *) uso ;;
esac

# Verifica se o gh CLI está instalado
if ! command -v gh &>/dev/null; then
    echo "Erro: GitHub CLI (gh) não está instalado." >&2
    exit 1
fi

# Se ainda não estiver autenticado:
if ! gh auth status &>/dev/null; then
    gh auth login
fi

DIR="$(pwd)"
# Usa a pasta atual como nome do repositório
NOME="$(basename "$DIR")"

# Evita erro "dubious ownership" quando o dono da pasta difere do usuário atual
git config --global --add safe.directory "$DIR"

# Repo local já existe (ex: criado numa execução anterior deste script)?
if [ -d .git ]; then
    REPO_EXISTENTE=true
else
    REPO_EXISTENTE=false
    git init
fi

git add .

if ! git diff --cached --quiet; then
    if [ "$REPO_EXISTENTE" = true ]; then
        git commit -m "Upgrade: $(date)"
    else
        git commit -m "Primeiro commit: $(date)"
    fi
else
    echo "Nada para commitar."
fi

# Se já existe remote "origin", o repositório remoto normalmente já foi criado antes: só faz push.
if URL_ORIGIN="$(git remote get-url origin 2>/dev/null)"; then
    # O remote pode apontar para um repositório apagado/renomeado no GitHub: recria se não existir.
    if ! gh repo view "$URL_ORIGIN" &>/dev/null; then
        echo "Repositório remoto não encontrado, criando..."
        # Extrai "dono/nome" da URL do remote (SSH ou HTTPS), para criar exatamente o repo apontado.
        REPO_ORIGIN="$(echo "$URL_ORIGIN" | sed -E 's#^(git@|ssh://git@|https://)github\.com[:/]##; s#\.git$##')"
        gh repo create "$REPO_ORIGIN" $VISIBILIDADE
    fi
    echo "Remote 'origin' já configurado, enviando alterações..."
    git push -u origin HEAD
else
    echo "Criando repositório remoto..."
    gh repo create "$NOME" \
        $VISIBILIDADE \
        --source=. \
        --remote=origin \
        --push
fi
