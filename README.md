# codex-account

`codex-account` is a Bash wrapper for keeping several Codex logins on one machine.

Each named account stores its authentication and configuration under `~/.codex-<account>`. Accounts launched through the wrapper share local sessions, SQLite state, and thread writer locks under `~/.codex-shared`. You can resume a local chat with another account without logging out first.

## Requirements

- Bash
- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
- Visual Studio Code for the optional `code` command

## Install

Run:

```bash
./install.sh
```

The installer copies `codex-account` to `~/.local/bin`. Add that directory to `PATH` if your shell does not include it.

## Usage

Create or refresh an account login:

```bash
codex-account login personal
codex-account login work
```

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

| Path | Contents |
| --- | --- |
| `~/.codex-<account>` | Account authentication and Codex configuration |
| `~/.config/Code-codex-<account>` | VS Code user data for the account |
| `~/.codex-shared/sessions` | Shared local session rollouts |
| `~/.codex-shared/sqlite` | Shared thread indexes and other SQLite-backed state |
| `~/.codex-shared/thread-writer-locks` | Locks that prevent concurrent writes to one thread |

Set `CODEX_ACCOUNT_SHARED_HOME` to use another shared root. Codex documents `CODEX_HOME` and `CODEX_SQLITE_HOME` in its [environment variable reference](https://learn.chatgpt.com/docs/config-file/environment-variables).

## Existing accounts

The wrapper creates shared links for a new named account. It stops if an existing `~/.codex-<account>/sessions` directory has not been migrated. This guard prevents the wrapper from overwriting local chats.

Back up existing Codex homes before merging them. Copy their rollout files into one shared `sessions` directory, check for conflicting session IDs, then replace each account's `sessions` and `thread-writer-locks` directories with links to the shared directories. Point all participating accounts at the same SQLite home.

## Notes

- The account used to resume a chat pays for later requests and supplies account-scoped permissions.
- Local transcript history can cross accounts. Cloud resources, workspace access, and MCP credentials still depend on the active account.
- Do not run the same session from two accounts at the same time.
