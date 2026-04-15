#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
FASTTEXT_GZ="$DATA_DIR/cc.ko.300.vec.gz"
FASTTEXT_VEC="$DATA_DIR/cc.ko.300.vec"
DICT_ZIP="$DATA_DIR/ko-aff-dic-0.7.92.zip"
DICT_DIR="$DATA_DIR/ko-aff-dic-0.7.92"

FASTTEXT_URL="https://dl.fbaipublicfiles.com/fasttext/vectors-crawl/cc.ko.300.vec.gz"
DICT_URL="https://github.com/spellcheck-ko/hunspell-dict-ko/releases/download/0.7.92/ko-aff-dic-0.7.92.zip"

RUNTIME="auto"
REGENERATE_SECRETS=0
PYTHON_BIN="${PYTHON_BIN:-python3}"
FILTER_WORDS_BATCH_SIZE="${FILTER_WORDS_BATCH_SIZE:-32}"
COMPOSE_CMD=()

usage() {
    cat <<'EOF'
Usage: ./scripts/setup-data.sh [--docker | --local] [--regenerate-secrets]

Options:
  --docker              Use Docker Compose for preprocessing.
  --local               Use the local Python environment for preprocessing.
  --regenerate-secrets  Regenerate data/secrets.txt even if it already exists.
  --help                Show this help message.

Notes:
  - If neither --docker nor --local is set, Docker Compose is used when available.
  - Local mode expects dependencies from requirements.txt to already be installed.
EOF
}

log() {
    printf '[setup-data] %s\n' "$*"
}

fail() {
    printf '[setup-data] %s\n' "$*" >&2
    exit 1
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

download_file() {
    local url="$1"
    local target="$2"

    if [[ -f "$target" ]]; then
        log "skip download: $(basename "$target") already exists"
        return
    fi

    if has_command curl; then
        curl -L --fail --output "$target" "$url"
    elif has_command wget; then
        wget -O "$target" "$url"
    else
        fail "curl or wget is required to download setup files"
    fi
}

set_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD=(docker compose)
    elif has_command docker-compose; then
        COMPOSE_CMD=(docker-compose)
    else
        fail "Docker Compose is not available. Use --local or install Docker Compose."
    fi
}

select_runtime() {
    has_command gzip || fail "gzip is required"
    has_command unzip || fail "unzip is required"

    if [[ "$RUNTIME" == "auto" ]]; then
        if docker compose version >/dev/null 2>&1 || has_command docker-compose; then
            RUNTIME="docker"
        else
            RUNTIME="local"
        fi
    fi

    if [[ "$RUNTIME" == "docker" ]]; then
        has_command docker || fail "docker is required for --docker mode"
        set_compose_cmd
    else
        has_command "$PYTHON_BIN" || fail "$PYTHON_BIN is required for --local mode"
    fi
}

prepare_sources() {
    mkdir -p "$DATA_DIR"

    if [[ -f "$FASTTEXT_VEC" ]]; then
        log "skip extract: $(basename "$FASTTEXT_VEC") already exists"
    else
        if [[ ! -f "$FASTTEXT_GZ" ]]; then
            log "downloading $(basename "$FASTTEXT_GZ")"
            download_file "$FASTTEXT_URL" "$FASTTEXT_GZ"
        fi
        log "extracting $(basename "$FASTTEXT_GZ")"
        gzip -d "$FASTTEXT_GZ"
    fi

    if [[ -d "$DICT_DIR" ]]; then
        log "skip extract: $(basename "$DICT_DIR") already exists"
    else
        if [[ ! -f "$DICT_ZIP" ]]; then
            log "downloading $(basename "$DICT_ZIP")"
            download_file "$DICT_URL" "$DICT_ZIP"
        fi
        log "extracting $(basename "$DICT_ZIP")"
        unzip -o "$DICT_ZIP" -d "$DATA_DIR"
    fi
}

run_python_script() {
    local script_name="$1"

    if [[ "$RUNTIME" == "docker" ]]; then
        (
            cd "$ROOT_DIR"
            "${COMPOSE_CMD[@]}" run --rm --entrypoint python app "$script_name"
        )
    else
        (
            cd "$ROOT_DIR"
            export HF_HOME="${HF_HOME:-$ROOT_DIR/.cache/huggingface}"
            export FILTER_WORDS_BATCH_SIZE
            "$PYTHON_BIN" "$script_name"
        )
    fi
}

run_preprocessing() {
    local filtered_words="$DATA_DIR/filtered_frequent_words.txt"
    local filtered_dictionary="$DICT_DIR/ko_filtered.txt"
    local valid_guesses_db="$DATA_DIR/valid_guesses.db"
    local valid_nearest_dat="$DATA_DIR/valid_nearest.dat"
    local secrets_file="$DATA_DIR/secrets.txt"

    if [[ -f "$filtered_words" && -f "$filtered_dictionary" ]]; then
        log "skip filter_words.py: filtered word lists already exist"
    else
        log "running filter_words.py"
        run_python_script "filter_words.py"
    fi

    if [[ -f "$valid_guesses_db" && -f "$valid_nearest_dat" ]]; then
        log "skip process_vecs.py: vector artifacts already exist"
    else
        log "running process_vecs.py"
        run_python_script "process_vecs.py"
    fi

    if [[ "$REGENERATE_SECRETS" -eq 1 || ! -f "$secrets_file" ]]; then
        log "running generate_secrets.py"
        run_python_script "generate_secrets.py"
    else
        log "skip generate_secrets.py: secrets file already exists"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docker)
            RUNTIME="docker"
            ;;
        --local)
            RUNTIME="local"
            ;;
        --regenerate-secrets)
            REGENERATE_SECRETS=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage
            fail "unknown option: $1"
            ;;
    esac
    shift
done

select_runtime
prepare_sources
run_preprocessing

log "done"
if [[ "$RUNTIME" == "docker" ]]; then
    log "next: ${COMPOSE_CMD[*]} up"
else
    log "next: gunicorn semantle:app --bind 0.0.0.0:8899"
fi
