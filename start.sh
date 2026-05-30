#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$PROJECT_ROOT/examples"
ENV_FILE="$PROJECT_ROOT/.env"
DEFAULT_HOST="127.0.0.1"
DEFAULT_PORT="8765"

ENV_KEYS=(
  "OPENAI_API_KEY"
  "EXIFTOOL_PATH"
  "AZURE_CLIENT_ID"
  "AZURE_TENANT_ID"
  "AZURE_CLIENT_SECRET"
  "MARKITDOWN_ENABLE_PLUGINS"
)

ENV_HELP_OPENAI_API_KEY="Optional. Used for LLM image captioning and OCR plugin workflows."
ENV_HELP_EXIFTOOL_PATH="Optional. Path to exiftool, for example /usr/bin/exiftool."
ENV_HELP_AZURE_CLIENT_ID="Optional. Azure service-principal client ID."
ENV_HELP_AZURE_TENANT_ID="Optional. Azure tenant ID."
ENV_HELP_AZURE_CLIENT_SECRET="Optional. Azure service-principal secret."
ENV_HELP_MARKITDOWN_ENABLE_PLUGINS="Optional. Set true, 1, or yes to enable installed plugins."

usage() {
  cat <<'EOF'
MarkItDown Workbench launcher

Usage:
  ./start.sh [command] [options]

Common commands:
  run [--host HOST] [--port PORT] [--reload]
      Start the FastAPI UI. This changes into examples/ and runs quick_ui.py.

  install
      Install MarkItDown, FastAPI UI dependencies, and pytest into .venv with uv.

  env status
      Show which optional environment variables are set, without printing secrets.

  env init
      Create .env with the known optional keys if it does not exist.

  env set KEY [VALUE]
      Set or update one key in .env. If VALUE is omitted, you will be prompted.

  env edit
      Open .env in $EDITOR, nano, vi, or sensible-editor.

  test
      Run focused smoke tests for the converter and UI script.

  help, --help, -h
      Show this help.

Examples:
  ./start.sh
  ./start.sh run
  ./start.sh run --port 8766
  ./start.sh run --reload
  ./start.sh env status
  ./start.sh env set OPENAI_API_KEY
  ./start.sh env set MARKITDOWN_ENABLE_PLUGINS true
  ./start.sh install
  ./start.sh test

Notes:
  - .env is loaded before running the UI.
  - Secret values are never printed by env status.
  - If port 8765 is busy, run: ./start.sh run --port 8766
EOF
}

env_key_help() {
  local key="$1"
  local help_var="ENV_HELP_${key}"
  printf '%s' "${!help_var:-Optional MarkItDown environment variable.}"
}

ensure_env_file() {
  if [[ ! -f "$ENV_FILE" ]]; then
    {
      for key in "${ENV_KEYS[@]}"; do
        printf '%s=\n' "$key"
      done
    } > "$ENV_FILE"
    echo "Created $ENV_FILE"
  fi
  chmod 600 "$ENV_FILE"
}

load_env() {
  ensure_env_file
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

python_bin() {
  if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
    printf '%s\n' "$PROJECT_ROOT/.venv/bin/python"
  elif [[ -x "$PROJECT_ROOT/.venv313/bin/python" ]]; then
    printf '%s\n' "$PROJECT_ROOT/.venv313/bin/python"
  elif command -v python3 >/dev/null 2>&1; then
    command -v python3
  else
    echo "Could not find Python. Run ./start.sh install after creating a venv." >&2
    exit 1
  fi
}

uv_bin() {
  if command -v uv >/dev/null 2>&1; then
    command -v uv
  else
    echo "uv is required for install. Install uv first, or run the .venv Python directly." >&2
    exit 1
  fi
}

valid_env_key() {
  local wanted="$1"
  local key
  for key in "${ENV_KEYS[@]}"; do
    if [[ "$key" == "$wanted" ]]; then
      return 0
    fi
  done
  return 1
}

set_env_key() {
  local key="${1:-}"
  local value="${2:-}"

  if [[ -z "$key" ]]; then
    echo "Missing key. Known keys:"
    printf '  %s\n' "${ENV_KEYS[@]}"
    exit 1
  fi

  if ! valid_env_key "$key"; then
    echo "Unknown key: $key"
    echo "Known keys:"
    printf '  %s\n' "${ENV_KEYS[@]}"
    exit 1
  fi

  ensure_env_file

  if [[ $# -lt 2 ]]; then
    read -r -p "Enter value for $key: " value
  fi

  local quoted line tmp
  quoted="$(quote_env_value "$value")"
  line="${key}=${quoted}"
  tmp="$(mktemp)"

  if grep -q "^${key}=" "$ENV_FILE"; then
    awk -v key="$key" -v line="$line" '
      $0 ~ "^" key "=" { print line; next }
      { print }
    ' "$ENV_FILE" > "$tmp"
    mv "$tmp" "$ENV_FILE"
  else
    rm -f "$tmp"
    printf '%s\n' "$line" >> "$ENV_FILE"
  fi

  chmod 600 "$ENV_FILE"
  echo "Updated $key in $ENV_FILE"
}

quote_env_value() {
  local value="$1"
  value="${value//\'/\'\\\'\'}"
  printf "'%s'" "$value"
}

env_status() {
  load_env
  echo "Environment file: $ENV_FILE"
  echo
  local key value state
  for key in "${ENV_KEYS[@]}"; do
    value="${!key:-}"
    if [[ -n "$value" ]]; then
      state="set"
    else
      state="missing"
    fi
    printf '%-32s %-8s %s\n' "$key" "$state" "$(env_key_help "$key")"
  done
}

edit_env() {
  ensure_env_file
  local editor="${EDITOR:-}"
  if [[ -z "$editor" ]]; then
    if command -v nano >/dev/null 2>&1; then
      editor="nano"
    elif command -v sensible-editor >/dev/null 2>&1; then
      editor="sensible-editor"
    else
      editor="vi"
    fi
  fi
  "$editor" "$ENV_FILE"
}

install_deps() {
  local uv python
  uv="$(uv_bin)"
  python="$(python_bin)"
  "$uv" pip install --python "$python" -e "$PROJECT_ROOT/packages/markitdown[all]"
  "$uv" pip install --python "$python" fastapi uvicorn python-multipart jinja2 pytest
}

run_ui() {
  load_env
  local python
  python="$(python_bin)"

  cd "$EXAMPLES_DIR"
  exec "$python" quick_ui.py "$@"
}

run_tests() {
  local python
  python="$(python_bin)"
  "$python" -m py_compile "$PROJECT_ROOT/examples/quick_ui.py"
  "$python" -m pytest "$PROJECT_ROOT/packages/markitdown/tests/test_module_misc.py::test_plain_text_falls_back_from_incorrect_ascii_hint"
  "$python" -m pytest "$PROJECT_ROOT/packages/markitdown/tests/test_module_vectors.py::test_convert_local"
}

main() {
  local command="${1:-run}"
  case "$command" in
    run|serve|server|ui)
      shift || true
      run_ui "$@"
      ;;
    install|setup)
      install_deps
      ;;
    env)
      shift || true
      case "${1:-status}" in
        status|check)
          env_status
          ;;
        init)
          ensure_env_file
          ;;
        set)
          shift || true
          set_env_key "$@"
          ;;
        edit)
          edit_env
          ;;
        *)
          echo "Unknown env command: ${1:-}"
          echo "Try: ./start.sh env status"
          exit 1
          ;;
      esac
      ;;
    test|check)
      run_tests
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      echo "Unknown command: $command"
      echo
      usage
      exit 1
      ;;
  esac
}

main "$@"
