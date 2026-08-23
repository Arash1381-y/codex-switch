#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'codex-account-migrate: %s\n' "$1" >&2
  exit 1
}

if pgrep -u "$UID" -x codex >/dev/null 2>&1; then
  fail "close running Codex CLI processes before migrating"
fi

shared="${CODEX_ACCOUNT_SHARED_HOME:-$HOME/.codex-shared}"
[[ "$shared" != *'"'* ]] || fail "the shared path cannot contain a double quote"

declare -a homes=()
[[ -d "$HOME/.codex" ]] && homes+=("$HOME/.codex")

shopt -s nullglob
for dir in "$HOME"/.codex-*; do
  [[ -d "$dir" ]] || continue
  [[ "$dir" == "$shared" ]] && continue
  [[ "${dir##*/}" == .codex-shared ]] && continue
  [[ "${dir##*/}" == .codex-account-backup-* ]] && continue
  [[ "${dir##*/}" == .codex-account-migration-backup.* ]] && continue
  homes+=("$dir")
done

[[ "${#homes[@]}" -gt 0 ]] || fail "no Codex homes found"

declare -A rollout_path=()
declare -A rollout_rel=()

consider_rollout() {
  local file="$1"
  local root="$2"
  local rel="${file#"$root"/}"
  local key="${file##*/}"
  local current current_size file_size smaller

  if [[ -z "${rollout_path[$key]+set}" ]]; then
    rollout_path[$key]="$file"
    rollout_rel[$key]="$rel"
    return
  fi

  current="${rollout_path[$key]}"
  cmp -s "$current" "$file" && return

  current_size="$(wc -c < "$current")"
  file_size="$(wc -c < "$file")"
  smaller="$current_size"
  (( file_size < smaller )) && smaller="$file_size"

  if ! cmp -s -n "$smaller" "$current" "$file"; then
    fail "conflicting copies of rollout $key: $current and $file"
  fi

  if (( file_size > current_size )); then
    rollout_path[$key]="$file"
    rollout_rel[$key]="$rel"
  fi
}

if [[ -d "$shared/sessions" ]]; then
  while IFS= read -r -d '' file; do
    consider_rollout "$file" "$shared/sessions"
  done < <(find "$shared/sessions" -type f -name '*.jsonl' -print0)
fi

for home_dir in "${homes[@]}"; do
  sessions="$home_dir/sessions"
  locks="$home_dir/thread-writer-locks"
  if [[ -L "$sessions" && "$(readlink -f "$sessions")" != "$shared/sessions" ]]; then
    fail "unexpected sessions link: $sessions"
  fi
  if [[ -L "$locks" && "$(readlink -f "$locks")" != "$shared/thread-writer-locks" ]]; then
    fail "unexpected writer-lock link: $locks"
  fi
  [[ -d "$sessions" && ! -L "$sessions" ]] || continue
  while IFS= read -r -d '' file; do
    consider_rollout "$file" "$sessions"
  done < <(find "$sessions" -type f -name '*.jsonl' -print0)
done

backup="$(mktemp -d "$HOME/.codex-account-migration-backup.XXXXXX")"
chmod 700 "$backup"
install -d -m 700 "$shared" "$shared/sessions" "$shared/sqlite" "$shared/thread-writer-locks"

rollout_keys=()
if (( ${#rollout_path[@]} > 0 )); then
  mapfile -t rollout_keys < <(printf '%s\n' "${!rollout_path[@]}" | sort)
fi
for key in "${rollout_keys[@]}"; do
  source_file="${rollout_path[$key]}"
  target="$shared/sessions/${rollout_rel[$key]}"
  install -d -m 700 "${target%/*}"
  if [[ ! -f "$target" ]]; then
    cp -p "$source_file" "$target"
  elif ! cmp -s "$source_file" "$target"; then
    cp -p "$source_file" "$target"
  fi
done

set_sqlite_home() {
  local config="$1"
  local temp
  temp="$(mktemp "${config}.tmp.XXXXXX")"

  if [[ -f "$config" ]]; then
    if grep -Eq '^[[:space:]]*sqlite_home[[:space:]]*=' "$config"; then
      awk -v setting="sqlite_home = \"$shared/sqlite\"" '
        BEGIN { replaced = 0 }
        /^[[:space:]]*sqlite_home[[:space:]]*=/ {
          if (!replaced) print setting
          replaced = 1
          next
        }
        { print }
      ' "$config" > "$temp"
    else
      {
        printf 'sqlite_home = "%s/sqlite"\n' "$shared"
        sed -n '1,$p' "$config"
      } > "$temp"
    fi
    chmod 600 "$temp"
  else
    printf 'sqlite_home = "%s/sqlite"\n' "$shared" > "$temp"
    chmod 600 "$temp"
  fi
  mv "$temp" "$config"
}

for home_dir in "${homes[@]}"; do
  label="${home_dir##*/}"
  sessions="$home_dir/sessions"
  locks="$home_dir/thread-writer-locks"

  if [[ -f "$home_dir/config.toml" ]]; then
    cp -p "$home_dir/config.toml" "$backup/$label.config.toml"
  fi

  if [[ -d "$sessions" && ! -L "$sessions" ]]; then
    mv "$sessions" "$backup/$label.sessions"
    ln -s "$shared/sessions" "$sessions"
  elif [[ ! -e "$sessions" ]]; then
    ln -s "$shared/sessions" "$sessions"
  elif [[ "$(readlink -f "$sessions")" != "$shared/sessions" ]]; then
    fail "unexpected sessions link: $sessions"
  fi

  if [[ -d "$locks" && ! -L "$locks" ]]; then
    mv "$locks" "$backup/$label.thread-writer-locks"
    ln -s "$shared/thread-writer-locks" "$locks"
  elif [[ ! -e "$locks" ]]; then
    ln -s "$shared/thread-writer-locks" "$locks"
  elif [[ "$(readlink -f "$locks")" != "$shared/thread-writer-locks" ]]; then
    fail "unexpected writer-lock link: $locks"
  fi

  set_sqlite_home "$home_dir/config.toml"
done

if [[ -f "$shared/sqlite/state_5.sqlite" ]]; then
  install -d -m 700 "$backup/shared-sqlite"
  for file in "$shared/sqlite"/state_5.sqlite*; do
    [[ -f "$file" ]] && cp -p "$file" "$backup/shared-sqlite/"
  done

  python3 - "$shared/sqlite/state_5.sqlite" <<'PY'
import sqlite3
import sys
import time

database = sys.argv[1]
connection = sqlite3.connect(database)
try:
    table = connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'backfill_state'"
    ).fetchone()
    if table:
        connection.execute(
            "UPDATE backfill_state "
            "SET status = 'pending', last_watermark = NULL, "
            "last_success_at = NULL, updated_at = ? WHERE id = 1",
            (int(time.time()),),
        )
        connection.commit()
finally:
    connection.close()
PY
fi

printf 'Merged %s rollout files.\n' "${#rollout_keys[@]}"
printf 'Shared storage: %s\n' "$shared"
printf 'Backup: %s\n' "$backup"
printf 'Run codex or codex-account, then open the resume picker to rebuild the index.\n'
