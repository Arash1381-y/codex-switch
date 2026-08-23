# codex-account

`codex-account` is a Bash wrapper for keeping several Codex logins on one machine.

Each named account stores its authentication and configuration under `~/.codex-<account>`. Accounts launched through the wrapper share local sessions, SQLite state, and thread writer locks under `~/.codex-shared`. You can resume a local chat with another account without logging out first.

## Requirements

- Bash 4 or newer
- Python 3
- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
- Visual Studio Code, if you use `codex-account code`

## Install

Run:

```bash
./install.sh
```

The installer copies `codex-account` and `codex-account-migrate` to `~/.local/bin`. Add that directory to `PATH` if your shell does not include it.

## Migrate existing history

Close Codex, then run:

```bash
codex-account-migrate
```

The migration command finds the default `~/.codex` home and named `~/.codex-*` homes. It performs these changes:

- Copies local rollout files into `~/.codex-shared/sessions`.
- Moves the old session and writer-lock directories into a timestamped backup under your home directory.
- Links each Codex home to the shared directories.
- Sets `sqlite_home` in each account config and asks Codex to rebuild its thread index on the next start.

The command keeps each `auth.json` file in its original account home. A named login can resume the migrated local chats, while later requests use the named account's access and limits.

The migration stops before changing files if two accounts contain divergent copies of one rollout. Identical copies and copies where one file extends the other merge without losing messages.

## Usage

Create or refresh an account login:

```bash
codex-account login personal
codex-account login work
```

If an account is already authenticated, `login` prints a message and exits. Use
`codex-account login personal --force` when you intentionally want to replace
its login.

List accounts and check a login:

```bash
codex-account list
codex-account status personal
```

Run the CLI with an account:

```bash
codex-account cli personal
codex-account cli work resume --all
codex-account cli personal resume --last --all
```

Open a separate VS Code window:

```bash
codex-account code personal ~/src/project
```

The wrapper gives each account a separate VS Code user-data directory while reusing the installed extensions directory.

## Storage

The wrapper uses these paths:

| Path                                  | Contents                                            |
| ------------------------------------- | --------------------------------------------------- |
| `~/.codex-<account>`                  | Account authentication and Codex configuration      |
| `~/.config/Code-codex-<account>`      | VS Code user data for the account                   |
| `~/.codex-shared/sessions`            | Shared local session rollouts                       |
| `~/.codex-shared/sqlite`              | Shared thread indexes and other SQLite-backed state |
| `~/.codex-shared/thread-writer-locks` | Locks that prevent concurrent writes to one thread  |

Set `CODEX_ACCOUNT_SHARED_HOME` to use another shared root. Codex documents `CODEX_HOME` and `CODEX_SQLITE_HOME` in its [environment variable reference](https://learn.chatgpt.com/docs/config-file/environment-variables).

## Notes

- The account used to resume a chat pays for later requests and supplies account-scoped permissions.
- Local transcript history can cross accounts. Cloud resources, workspace access, and MCP credentials still depend on the active account.
- Do not run the same session from two accounts at the same time.
