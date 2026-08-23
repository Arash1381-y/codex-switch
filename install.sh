#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
install_dir="${1:-$HOME/.local/bin}"

install -d -m 700 "$install_dir"
install -m 700 "$script_dir/codex-account" "$install_dir/codex-account"

printf 'Installed %s\n' "$install_dir/codex-account"
