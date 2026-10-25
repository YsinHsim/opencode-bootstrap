# opencode-bootstrap

Set up [OpenCode](https://opencode.ai) on a new machine with one command — macOS,
Linux, or Termux on Android.

There are two paths. Pick the one that fits you.

| You are | Use this | What you get |
|---|---|---|
| **Yasin** (repo author, known setup) | `./install.sh` | The reference config: Rootsys provider, Aztra MCP, caveman skill |
| **Everyone else** | `./install.sh --interview` | A config generated from your answers — your provider, your keys, nothing you didn't ask for |

---

## For everyone else — the interview

```bash
git clone https://github.com/YsinHsim/opencode-bootstrap.git
cd opencode-bootstrap
./install.sh --interview
```

You'll be asked, each with a default you can accept by pressing Enter:

| Question | Options | Default |
|---|---|---|
| Agent name | any name | `assistant` |
| Tone | terse / friendly / formal | terse |
| Response language | English / Bahasa Melayu / both | English |
| Provider | custom endpoint / OpenAI / Anthropic / Ollama / skip | custom endpoint |
| Provider endpoint + model | free text (custom and Ollama) | — |
| API key | hidden input | — |
| MCP server | endpoint URL + key, or skip | skip |
| Google tools | y / n | n |
| Caveman skill | y / n | n |

Then it writes:

- `~/.config/opencode/opencode.json` — only the provider and MCP entries you chose
- `~/.config/opencode/AGENTS.md` — a working SOP in the tone and language you picked
- `~/.config/opencode/<provider>.key` — your API key, chmod 600

Nothing is installed that you didn't ask for. Declining a question removes its
section from the generated files entirely rather than leaving a placeholder.

### Provider options

| Choice | Endpoint needed | Notes |
|---|---|---|
| **OpenAI-compatible (custom endpoint)** | Yes, an OpenAI-format base URL | Works with most hosted and self-hosted gateways. See the example below. |
| **OpenAI** | No | Uses `@ai-sdk/openai`. Needs an OpenAI API key. |
| **Anthropic** | No | Uses `@ai-sdk/anthropic`. Needs an Anthropic API key. |
| **Ollama (local)** | Defaults to `http://localhost:11434/v1` | No API key. The model must already be pulled. |
| **Skip** | — | Installs OpenCode with no provider. Add one later by re-running. |

**Example of a custom endpoint:** [Rootsys](https://rootsys.cloud/) is an
OpenAI-compatible gateway that works with this option. Enter its base URL
(ending in `/v1`) and the model ID exactly as the service names it. It is one
example, not a requirement — any OpenAI-format endpoint works the same way.

### MCP servers

If you already have an MCP server — a hosted endpoint plus an API key — the
interview asks for its URL and key and writes the entry for you. This is
optional and generic: point it at any MCP endpoint you have. The key goes to
`~/.config/opencode/mcp.key` with chmod 600.

**Aztra is not installed by this script.** Aztra is a private workspace service;
its endpoint only works if you have an account there. If you don't, answer `n`
and nothing related to it is written.

### Google tools

Answer `y` and the script prints the install command for the companion repo —
it does not install it inline, because that repo runs a browser OAuth flow and
should be run on its own:

```bash
git clone https://github.com/YsinHsim/opencode-google.git
cd opencode-google && ./install.sh
```

---

## For Yasin — the scripted path

No flag. Non-interactive, same behaviour as before, for machines already known
to be yours:

```bash
git clone git@github.com:YsinHsim/opencode-bootstrap.git
cd opencode-bootstrap
./install.sh
```

It merges `config/opencode.json` (Rootsys provider, model list) into
`~/.config/opencode/`, copies `skills/`, prompts once for the Rootsys and Aztra
keys, and prints the companion repos.

Secrets can come from `.env` instead of prompts:

```bash
cp .env.example .env
chmod 600 .env
# edit .env, then ./install.sh
```

---

## What it installs (both paths)

- **OpenCode CLI** via the official installer, if missing
- **GitHub CLI** (`gh`) if missing, plus `gh auth login` when authenticated
- **Config** under `~/.config/opencode/`
- **`service.json`** — a freshly generated random password for `opencode serve` /
  `opencode web`, chmod 600. Each machine gets its own.

Safe to re-run. It backs up any existing `opencode.json` before touching it.

## Secrets

| Secret | Stored at | Referenced in config as |
|---|---|---|
| Provider API key | `~/.config/opencode/<provider>.key` | `{file:~/.config/opencode/<provider>.key}` |
| MCP key | `~/.config/opencode/mcp.key` | `{file:~/.config/opencode/mcp.key}` |
| Service password | `~/.config/opencode/service.json` | read by OpenCode itself |

Every secret file is chmod 600 and covered by `.gitignore`. **No API key is ever
written into a tracked file** — the JSON config holds `{file:...}` references,
which OpenCode resolves at runtime, so the config itself is safe to commit.

Before any commit in this repo, run the scanner:

```bash
./scripts/secret-scan.sh
```

It checks staged content, tracked files, and full git history. A secret deleted
in a later commit is still in history — the scan catches that, a filename check
does not.

## Companion repos

Not required. Install only what you use.

| Repo | Adds |
|---|---|
| [`opencode-google`](https://github.com/YsinHsim/opencode-google) | Google Calendar, Gmail, Drive, Docs, Sheets, Tasks, Contacts |
| [`opencode-aztra`](https://github.com/YsinHsim/opencode-aztra) | Aztra workspace tools — only useful if you have an Aztra account |

## Files

| Path | Purpose |
|---|---|
| `install.sh` | Installer. Default mode, or `--interview` |
| `config/opencode.json` | Reference config for the scripted path (no secrets) |
| `scripts/secret-scan.sh` | Pre-commit / pre-push secret scan |
| `skills/caveman/SKILL.md` | Terse-reply skill, installed only if you say yes |
| `AGENTS.md` | Working SOP template |

## Troubleshooting

**"stdin is not a terminal and has no answers to read."**
`--interview` needs a terminal to ask questions. Run it directly rather than
through a script with redirected input, or pipe answers:
`printf '\n\n\n5\n\n\n\n' | ./install.sh --interview`.

**"opencode not on PATH after install."**
Open a new shell. The installer puts the binary in `~/.opencode/bin`.

**On Termux**, Android may kill background sessions — run OpenCode inside `tmux`.
