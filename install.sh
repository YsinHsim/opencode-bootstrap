#!/usr/bin/env bash
# OpenCode bootstrap — set up an OpenCode environment on a new machine.
#
#   ./install.sh              non-interactive default (Yasin's machines)
#   ./install.sh --interview  guided setup for anyone else
#
# Non-interactive default reads secrets from .env (optional) or prompts once.
# Interview mode asks questions and generates a tailored config.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/opencode"
ENV_FILE="$REPO_DIR/.env"

MODE="default"
for arg in "$@"; do
  case "$arg" in
    --interview) MODE="interview" ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./install.sh [--interview]

  (no flag)     Non-interactive setup with the reference config.
  --interview   Ask questions and generate a config tailored to you.
  -h, --help    Show this help.
USAGE
      exit 0
      ;;
    *) printf '[x] Unknown argument: %s (try --help)\n' "$arg" >&2; exit 2 ;;
  esac
done

info()  { printf '\033[0;32m[+]\033[0m %s\n' "$*"; }
warn()  { printf '\033[0;33m[!]\033[0m %s\n' "$*"; }
fail()  { printf '\033[0;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
ask()   { printf '\033[0;36m[?]\033[0m %s\n' "$*"; }

# A bare `read` under `set -e` with no TTY aborts the whole script — verified: an
# exhausted stdin makes bash exit 1 with no message. Every read goes through the
# helpers below, each with `|| var=""`, so a short answer stream degrades to
# defaults instead of killing the run.
#
# Interactive = stdin is a TTY, or it is a pipe with answers in it. Only a closed
# stdin (/dev/null) is refused, because every answer would silently take a
# default and the user would get a config they never chose.
stdin_usable() {
  [ -t 0 ] && return 0
  [ -p /dev/stdin ] && return 0
  # Not a TTY: check whether anything is actually readable.
  if read -r -t 0 _probe 2>/dev/null; then return 0; fi
  return 1
}

need_tty() {
  stdin_usable && return 0
  fail "stdin is not a terminal and has no answers to read.
     Run ./install.sh --interview from a normal terminal, or pipe answers:
       printf '<answers>' | ./install.sh --interview"
}

# prompt VAR "question" "default"
prompt() {
  local __var="$1" __q="$2" __def="${3:-}" __ans=""
  need_tty
  if [ -n "$__def" ]; then
    read -r -p "$(printf '\033[0;36m[?]\033[0m %s [%s]: ' "$__q" "$__def")" __ans || __ans=""
  else
    read -r -p "$(printf '\033[0;36m[?]\033[0m %s: ' "$__q")" __ans || __ans=""
  fi
  [ -n "$__ans" ] || __ans="$__def"
  printf -v "$__var" '%s' "$__ans"
}

# prompt_secret VAR "question" — hidden input, empty allowed
prompt_secret() {
  local __var="$1" __q="$2" __ans=""
  need_tty
  # -s only makes sense on a terminal; piped input is not echoed anyway.
  if [ -t 0 ]; then
    read -rs -p "$(printf '\033[0;36m[?]\033[0m %s: ' "$__q")" __ans || __ans=""
    echo
  else
    read -r __ans || __ans=""
  fi
  printf -v "$__var" '%s' "$__ans"
}

# yes_no VAR "question" [default]  — default is "n" unless given
yes_no() {
  local __var="$1" __q="$2" __def="${3:-n}" __ans=""
  need_tty
  read -r -p "$(printf '\033[0;36m[?]\033[0m %s [%s]: ' "$__q" "$__def")" __ans || __ans=""
  [ -n "$__ans" ] || __ans="$__def"
  case "$__ans" in
    [yY]|[yY][eE][sS]) printf -v "$__var" 'y' ;;
    *) printf -v "$__var" 'n' ;;
  esac
}

# write_secret FILE VAR — 600 before any bytes land, so the key is never readable
write_secret() {
  local __file="$1" __val="$2"
  mkdir -p "$(dirname "$__file")"
  chmod 700 "$(dirname "$__file")" 2>/dev/null || true
  : > "$__file"
  chmod 600 "$__file"
  printf '%s' "$__val" > "$__file"
}

# ---------- 1. Detect platform ----------
PLATFORM="unknown"
case "$(uname -s)" in
  Darwin) PLATFORM="macos" ;;
  Linux)
    if [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ]; then
      PLATFORM="termux"
    else
      PLATFORM="linux"
    fi
    ;;
esac
info "Platform: $PLATFORM"
info "Mode: $MODE"

# ---------- 2. Dependencies ----------
need() { command -v "$1" >/dev/null 2>&1; }

if ! need git; then
  info "Installing git..."
  case "$PLATFORM" in
    macos)  xcode-select --install 2>/dev/null || true ;;
    linux)  sudo apt-get update && sudo apt-get install -y git ;;
    termux) pkg install -y git ;;
  esac
fi

if ! need gh; then
  info "Installing GitHub CLI..."
  case "$PLATFORM" in
    macos)  need brew && brew install gh || warn "Install Homebrew first: https://brew.sh" ;;
    linux)  sudo apt-get install -y gh || warn "See https://github.com/cli/cli#installation" ;;
    termux) pkg install -y gh ;;
  esac
else
  info "gh CLI already installed."
fi

# ---------- 3. Install OpenCode ----------
if ! need opencode; then
  info "Installing OpenCode..."
  curl -fsSL https://opencode.ai/install | bash
  export PATH="$HOME/.opencode/bin:$PATH"
  need opencode || fail "opencode not on PATH after install. Open a new shell and re-run."
else
  info "OpenCode already installed: $(opencode --version 2>/dev/null || echo 'unknown version')"
fi

# ---------- 4. Collect answers (interview mode only) ----------
mkdir -p "$CONFIG_DIR/skills"

AGENT_NAME="assistant"
TONE="terse"
LANG_CHOICE="english"
PROVIDER_KIND=""
PROVIDER_ID=""
PROVIDER_URL=""
PROVIDER_MODEL=""
PROVIDER_MODELS_JSON=""
USE_MCP="n"
MCP_URL=""
USE_GOOGLE="n"
USE_CAVEMAN="n"
AGENTS_TEMPLATE=""

if [ "$MODE" = "interview" ]; then
  need_tty
  echo
  info "A few questions. Press Enter to accept the default in [brackets]."
  echo

  prompt AGENT_NAME "Agent name" "assistant"
  echo
  echo "  Tone: 1) terse   2) friendly   3) formal"
  prompt TONE_ANS "Tone" "1"
  case "$TONE_ANS" in
    2|friendly) TONE="friendly" ;;
    3|formal)   TONE="formal" ;;
    *)          TONE="terse" ;;
  esac

  echo
  echo "  Language: 1) English   2) Bahasa Melayu   3) Both"
  prompt LANG_ANS "Response language" "1"
  case "$LANG_ANS" in
    2|malay|bm) LANG_CHOICE="malay" ;;
    3|both)     LANG_CHOICE="both" ;;
    *)          LANG_CHOICE="english" ;;
  esac

  echo
  echo "  Provider:"
  echo "    1) OpenAI-compatible (custom endpoint)"
  echo "    2) OpenAI"
  echo "    3) Anthropic"
  echo "    4) Ollama (local)"
  echo "    5) Skip"
  prompt PROV_ANS "Choose 1-5" "1"
  case "$PROV_ANS" in
    2|openai)      PROVIDER_KIND="openai" ;;
    3|anthropic)   PROVIDER_KIND="anthropic" ;;
    4|ollama)      PROVIDER_KIND="ollama" ;;
    5|skip)        PROVIDER_KIND="skip" ;;
    *)             PROVIDER_KIND="custom" ;;
  esac

  case "$PROVIDER_KIND" in
    custom)
      prompt PROVIDER_URL "Endpoint URL (OpenAI-compatible base URL)" ""
      while [ -z "$PROVIDER_URL" ]; do
        warn "An endpoint URL is required for a custom provider."
        prompt PROVIDER_URL "Endpoint URL (OpenAI-compatible base URL)" ""
      done
      prompt PROVIDER_MODEL "Model ID (as the endpoint names it)" ""
      while [ -z "$PROVIDER_MODEL" ]; do
        warn "A model ID is required."
        prompt PROVIDER_MODEL "Model ID (as the endpoint names it)" ""
      done
      PROVIDER_ID="custom"
      ;;
    openai)
      PROVIDER_ID="openai"
      prompt PROVIDER_MODEL "Model ID" "gpt-5"
      ;;
    anthropic)
      PROVIDER_ID="anthropic"
      prompt PROVIDER_MODEL "Model ID" "claude-sonnet-4-5"
      ;;
    ollama)
      PROVIDER_ID="ollama"
      prompt PROVIDER_MODEL "Model ID" "qwen3-coder"
      prompt PROVIDER_URL "Ollama base URL" "http://localhost:11434/v1"
      ;;
  esac

  # API key — hidden input, written to its own 600 file. Ollama is local, no key.
  if [ "$PROVIDER_KIND" != "skip" ] && [ "$PROVIDER_KIND" != "ollama" ]; then
    echo
    prompt_secret PROV_KEY "API key (hidden; stored in $CONFIG_DIR/$PROVIDER_ID.key, chmod 600)"
    if [ -n "${PROV_KEY:-}" ]; then
      write_secret "$CONFIG_DIR/$PROVIDER_ID.key" "$PROV_KEY"
      info "Key stored at $CONFIG_DIR/$PROVIDER_ID.key (chmod 600)"
    else
      warn "No key entered. $PROVIDER_ID will not authenticate until you add:"
      warn "  chmod 600 $CONFIG_DIR/$PROVIDER_ID.key  # then paste the key inside"
    fi
    unset PROV_KEY
  fi

  echo
  yes_no USE_MCP "Do you have an MCP server endpoint URL and API key to add?" "n"
  if [ "$USE_MCP" = "y" ]; then
    prompt MCP_URL "MCP endpoint URL" ""
    while [ -z "$MCP_URL" ]; do
      warn "An endpoint URL is required when adding an MCP server."
      prompt MCP_URL "MCP endpoint URL" ""
    done
    prompt_secret MCP_KEY "MCP API key (hidden; stored in $CONFIG_DIR/mcp.key, chmod 600)"
    if [ -n "${MCP_KEY:-}" ]; then
      write_secret "$CONFIG_DIR/mcp.key" "$MCP_KEY"
      info "MCP key stored at $CONFIG_DIR/mcp.key (chmod 600)"
    else
      warn "No MCP key entered; the server entry will require one later."
    fi
    unset MCP_KEY
  fi

  echo
  yes_no USE_GOOGLE "Do you want Google (Calendar/Gmail/Drive/Docs/Sheets/Tasks/Contacts)?" "n"

  echo
  yes_no USE_CAVEMAN "Add the 'caveman' skill (terse replies on demand, off by default)?" "n"

  echo
  AGENTS_TEMPLATE="$REPO_DIR/AGENTS.md"
fi

# ---------- 5. Backup existing config ----------
if [ -f "$CONFIG_DIR/opencode.json" ]; then
  BACKUP="$CONFIG_DIR/opencode.json.bak.$(date +%Y%m%d%H%M%S)"
  cp "$CONFIG_DIR/opencode.json" "$BACKUP"
  info "Backed up existing config to $BACKUP"
fi
if [ -f "$CONFIG_DIR/AGENTS.md" ] && [ "$MODE" = "interview" ]; then
  cp "$CONFIG_DIR/AGENTS.md" "$CONFIG_DIR/AGENTS.md.bak.$(date +%Y%m%d%H%M%S)"
  info "Backed up existing AGENTS.md"
fi

# ---------- 6a. Default mode: merge the reference config ----------
if [ "$MODE" = "default" ]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$REPO_DIR/config/opencode.json" "$CONFIG_DIR/opencode.json" <<'PYEOF'
import json, os, sys

template_path, target_path = sys.argv[1], sys.argv[2]

with open(template_path, encoding="utf-8") as fh:
    template = json.load(fh)

existing = {}
if os.path.exists(target_path):
    try:
        with open(target_path, encoding="utf-8") as fh:
            existing = json.load(fh)
    except json.JSONDecodeError:
        existing = {}

# Template wins for provider/model/skills; existing MCP servers are always kept.
merged = dict(existing)
merged.update(template)
merged["mcp"] = {**existing.get("mcp", {}), **template.get("mcp", {})}

with open(target_path, "w", encoding="utf-8") as fh:
    json.dump(merged, fh, indent=2)
    fh.write("\n")

kept = sorted(set(existing.get("mcp", {})) - set(template.get("mcp", {})))
print(f"[+] Config merged into {target_path}")
if kept:
    print(f"[+] Preserved existing MCP servers: {', '.join(kept)}")
PYEOF
  else
    warn "python3 not found - copying config without merging (existing MCP entries may be overwritten)."
    cp "$REPO_DIR/config/opencode.json" "$CONFIG_DIR/opencode.json"
  fi

  cp -R "$REPO_DIR/skills/." "$CONFIG_DIR/skills/"

# ---------- 6b. Interview mode: generate the config from answers ----------
else
  command -v python3 >/dev/null 2>&1 || fail "python3 is required for --interview (it writes the JSON config). Install python3 and re-run."

  # Provider fragment. Written by python so nothing is hand-escaped.
  PROVIDER_JSON="$(PROVIDER_KIND="$PROVIDER_KIND" \
                   PROVIDER_ID="$PROVIDER_ID" \
                   PROVIDER_URL="$PROVIDER_URL" \
                   PROVIDER_MODEL="$PROVIDER_MODEL" \
                   python3 - <<'PYEOF'
import json, os

kind = os.environ["PROVIDER_KIND"]
pid  = os.environ["PROVIDER_ID"]
url  = os.environ["PROVIDER_URL"]
mod  = os.environ["PROVIDER_MODEL"]

if kind == "skip":
    print("{}")
    raise SystemExit

keyfile = f"{{file:~/.config/opencode/{pid}.key}}"
model_key = mod if mod else "default"

block = {"models": {model_key: {"name": model_key}}}
if kind == "openai":
    block["npm"] = "@ai-sdk/openai"
    block["options"] = {"apiKey": keyfile}
elif kind == "anthropic":
    block["npm"] = "@ai-sdk/anthropic"
    block["options"] = {"apiKey": keyfile}
elif kind == "ollama":
    block["npm"] = "@ai-sdk/openai-compatible"
    block["name"] = "Ollama (local)"
    block["options"] = {"baseURL": url or "http://localhost:11434/v1"}
else:  # custom OpenAI-compatible endpoint
    block["npm"] = "@ai-sdk/openai-compatible"
    block["name"] = "Custom"
    block["options"] = {"baseURL": url, "apiKey": keyfile}

print(json.dumps({pid: block}))
PYEOF
)"

  AGENT_NAME="$AGENT_NAME" TONE="$TONE" LANG_CHOICE="$LANG_CHOICE" \
  PROVIDER_JSON="$PROVIDER_JSON" PROVIDER_ID="$PROVIDER_ID" PROVIDER_MODEL="$PROVIDER_MODEL" \
  USE_MCP="$USE_MCP" MCP_URL="$MCP_URL" \
  USE_GOOGLE="$USE_GOOGLE" USE_CAVEMAN="$USE_CAVEMAN" \
  CONFIG_DIR="$CONFIG_DIR" REPO_DIR="$REPO_DIR" \
  python3 - <<'PYEOF'
import json, os, shutil

cfg_dir = os.environ["CONFIG_DIR"]
repo_dir = os.environ["REPO_DIR"]
target = os.path.join(cfg_dir, "opencode.json")

provider_new = json.loads(os.environ["PROVIDER_JSON"])
pid = os.environ["PROVIDER_ID"]
model = os.environ["PROVIDER_MODEL"]

existing = {}
if os.path.exists(target):
    try:
        with open(target, encoding="utf-8") as fh:
            existing = json.load(fh)
    except json.JSONDecodeError:
        existing = {}

merged = dict(existing)

# Preserve every provider the user already has; add or replace only ours.
providers = dict(existing.get("provider", {}))
providers.update(provider_new)
if providers:
    merged["provider"] = providers
elif "provider" in merged:
    del merged["provider"]

if provider_new and pid:
    merged["model"] = f"{pid}/{model}"

merged.setdefault("$schema", "https://opencode.ai/config.json")

# MCP: preserve existing entries, add ours only if opted in.
mcp = dict(existing.get("mcp", {}))
if os.environ["USE_MCP"] == "y":
    from urllib.parse import urlparse
    host = (urlparse(os.environ["MCP_URL"]).hostname or "custom")
    # "aztra.my" -> "aztra", "mcp.example.com" -> "example"
    parts = [p for p in host.split(".") if p and p not in ("www", "mcp")]
    key = parts[0] if parts else "custom"
    base, n = key, 2
    while key in mcp:            # never clobber an existing server
        key = f"{base}{n}"; n += 1
    mcp[key] = {
        "type": "remote",
        "url": os.environ["MCP_URL"],
        "oauth": False,
        "headers": {
            "Authorization": "{file:~/.config/opencode/mcp.key}",
            "Accept": "application/json, text/event-stream",
        },
    }
if mcp:
    merged["mcp"] = mcp
elif "mcp" in merged:
    del merged["mcp"]

os.makedirs(cfg_dir, exist_ok=True)
with open(target, "w", encoding="utf-8") as fh:
    json.dump(merged, fh, indent=2)
    fh.write("\n")

print(f"[+] Generated config at {target}")
kept_mcp = sorted(set(existing.get("mcp", {})) - ({"mcp"} if os.environ["USE_MCP"] == "y" else set()))
if kept_mcp:
    print(f"[+] Preserved existing MCP servers: {', '.join(kept_mcp)}")
kept_prov = sorted(set(existing.get("provider", {})) - set(provider_new))
if kept_prov:
    print(f"[+] Preserved existing providers: {', '.join(kept_prov)}")

# --- AGENTS.md from answers ---
TONE_TEXT = {
    "terse": "Terse: fragments OK, no filler, no repeating myself. Keep technical details\n"
             "exact (code, commands, paths, errors, numbers).",
    "friendly": "Friendly and conversational, but still concise. Explain reasoning when it\n"
                "helps; skip preamble and closing pleasantries.",
    "formal": "Formal register, complete sentences, no contractions, no filler. Keep technical\n"
              "details exact (code, commands, paths, errors, numbers).",
}
LANG_TEXT = {
    "english": "Respond in English.",
    "malay": "Respond in Bahasa Melayu.",
    "both": "Respond in English, switching to Bahasa Melayu when I write in Malay.",
}

name = os.environ["AGENT_NAME"]
tone = TONE_TEXT[os.environ["TONE"]]
lang = LANG_TEXT[os.environ["LANG_CHOICE"]]

lines = [
    f"# Working SOP — {name}",
    "",
    f"You are {name}, a coding agent. Follow this flow for every task.",
    "",
    "## Communication",
    f"- {tone}",
    f"- {lang}",
    "- Use clear file paths when referring to files.",
    "- Tables for comparisons, numbered lists for steps.",
    "",
    "## 1. Understand before building",
    "- If a term or tool is unfamiliar or ambiguous, search the web first. Never invent",
    "  definitions. If nothing official exists, say so and show the closest matches.",
    "- Explain the concept briefly before proposing code.",
    "",
    "## 2. Options, then a recommendation",
    "- When there are several ways to do something, list 2-4 options in a short table:",
    "  cost, pros, gotchas.",
    "- End with one recommended pick.",
    "- Flag real-world gotchas up front (region blocks, free-tier limits, background",
    "  processes being killed, battery).",
    "",
    "## 3. Decide, then build",
    "- I choose the option. Do not build before I confirm the direction.",
    "- Once I say go, build it end to end without asking about small details. Pick",
    "  sensible defaults and mention them.",
    "- Prefer the smallest dependency footprint that fits the target platform.",
    "- Secrets live only in untracked files with chmod 600. Commit examples, not values.",
    "",
    "## 4. Verify before claiming done",
    "- Run what can be run locally: syntax checks, a dry run, error paths.",
    "- Fix rough edges found while testing.",
    "- Report clearly what was verified and what was **not**.",
    "",
    "## 5. Git",
    "- Conventional Commits (`feat:`, `fix:`, ...), small focused commits.",
    "- Before every commit, scan for secrets: `./scripts/secret-scan.sh`.",
    "- A secret deleted in a later commit is still in history. Rewrite, do not patch over.",
    "- Ask before outward actions: creating repos, pushing, publishing, sending messages.",
    "",
    "## 6. Guide the real-world setup",
    "- Numbered steps, one command per code block.",
    "- Include a before-you-start checklist (apps installed, accounts or tokens ready).",
    "- Ask me to paste errors back, and debug from the real output.",
]

if os.environ["USE_GOOGLE"] == "y":
    lines += [
        "",
        "## 7. Google MCP",
        "- Calendar, Gmail, Drive, Docs, Sheets, Tasks, Contacts are available via MCP.",
        "- Read SOP.md in the opencode-google repo before any write operation.",
        "- Update/delete tools return a preview and need a confirm_token; never assume consent.",
    ]

lines += ["", "## Handoff", "- When I move to another tool or session, write a handoff: goal, paths,",
          "  decisions with reasons, files, what's verified and not, next tasks, constraints."]

agents_path = os.path.join(cfg_dir, "AGENTS.md")
with open(agents_path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
print(f"[+] Generated {agents_path}")

# --- caveman skill only when opted in ---
src_skill = os.path.join(repo_dir, "skills", "caveman")
dst_skill = os.path.join(cfg_dir, "skills", "caveman")
if os.environ["USE_CAVEMAN"] == "y":
    if os.path.isdir(src_skill):
        os.makedirs(dst_skill, exist_ok=True)
        shutil.copy2(os.path.join(src_skill, "SKILL.md"), os.path.join(dst_skill, "SKILL.md"))
        print("[+] Installed skill: caveman")
elif os.path.isdir(dst_skill):
    print("[!] Skill 'caveman' already present from an earlier run; left untouched.")
PYEOF
fi

# ---------- 7. Secrets ----------
# Default mode: persist secrets in 600 files referenced by {file:...}.
if [ "$MODE" = "default" ]; then
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi

  KEY_FILE="$CONFIG_DIR/rootsys.key"
  if [ ! -s "$KEY_FILE" ]; then
    if [ -n "${ROOTSYS_API_KEY:-}" ]; then
      write_secret "$KEY_FILE" "$ROOTSYS_API_KEY"
    else
      need_tty
      echo
      echo "Enter your Rootsys API key (input hidden, stored in $KEY_FILE):"
      read -rs -p "> " ROOTSYS_API_KEY || ROOTSYS_API_KEY=""
      echo
      [ -n "$ROOTSYS_API_KEY" ] || fail "No key provided."
      write_secret "$KEY_FILE" "$ROOTSYS_API_KEY"
    fi
  fi
  chmod 600 "$KEY_FILE"
  info "API key stored at $KEY_FILE (chmod 600)"

  AZTRA_KEY_FILE="$CONFIG_DIR/aztra.key"
  if [ -s "$AZTRA_KEY_FILE" ]; then
    info "Aztra key already present ($AZTRA_KEY_FILE)."
  elif [ -n "${AZTRA_API_KEY:-}" ]; then
    write_secret "$AZTRA_KEY_FILE" "$AZTRA_API_KEY"
    info "Aztra key stored at $AZTRA_KEY_FILE (chmod 600)"
  else
    echo
    echo "Enter your Aztra API key (input hidden, stored in $AZTRA_KEY_FILE)."
    echo "Press Enter to skip and add it later with ./install.sh from opencode-aztra."
    read -rs -p "> " AZTRA_API_KEY || AZTRA_API_KEY=""
    echo
    if [ -n "${AZTRA_API_KEY:-}" ]; then
      write_secret "$AZTRA_KEY_FILE" "$AZTRA_API_KEY"
      info "Aztra key stored at $AZTRA_KEY_FILE (chmod 600)"
    else
      warn "Skipped. The aztra MCP entry will not authenticate until you add a key."
    fi
  fi
fi

# ---------- 8. Service password (generated, never shipped) ----------
# A local HTTP basic-auth password for `opencode serve` / `opencode web`. It is
# machine-local and regenerable, so it is generated here instead of committed.
SERVICE_FILE="$CONFIG_DIR/service.json"
if [ ! -s "$SERVICE_FILE" ]; then
  if command -v python3 >/dev/null 2>&1; then
    : > "$SERVICE_FILE"
    chmod 600 "$SERVICE_FILE"
    python3 - "$SERVICE_FILE" <<'PYEOF'
import json, secrets, sys
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump({"password": secrets.token_urlsafe(32)}, fh, indent=2)
    fh.write("\n")
PYEOF
    chmod 600 "$SERVICE_FILE"
    info "Generated $SERVICE_FILE (chmod 600)"
  else
    warn "python3 not found; skipped $SERVICE_FILE (only needed for 'opencode serve' / 'opencode web')."
  fi
else
  chmod 600 "$SERVICE_FILE"
  info "Service password already present ($SERVICE_FILE)."
fi

# ---------- 9. GitHub auth ----------
if need gh && ! gh auth status >/dev/null 2>&1; then
  if [ -t 0 ]; then
    info "GitHub CLI not authenticated. Starting login..."
    gh auth login
  else
    warn "gh not authenticated and no TTY; skipping. Run 'gh auth login' later."
  fi
else
  info "GitHub auth OK."
fi

# ---------- 10. Companion repos ----------
echo
if [ "$MODE" = "interview" ]; then
  if [ "$USE_GOOGLE" = "y" ]; then
    info "Google MCP — install separately:"
    echo "  https://github.com/YsinHsim/opencode-google"
    echo "  git clone https://github.com/YsinHsim/opencode-google.git && cd opencode-google && ./install.sh"
  fi
  if [ "$USE_MCP" = "y" ]; then
    info "MCP server '$MCP_URL' written to opencode.json."
  fi
else
  info "Recommended companion repos (install after this one):"
  cat <<'REPOS'
  opencode-google  Calendar, Gmail, Drive, Docs   https://github.com/YsinHsim/opencode-google
REPOS
fi

# ---------- 11. Next steps ----------
echo
info "Done. Next steps:"
if [ "$MODE" = "interview" ]; then
  echo "  1. Verify: opencode --version"
  echo "  2. Launch opencode and ask a test question."
  echo "  3. Project SOP: $CONFIG_DIR/AGENTS.md is loaded globally."
else
  echo "  1. Copy $REPO_DIR/AGENTS.md into any project root where you want your SOP applied."
  echo "  2. Verify: opencode --version"
  echo "  3. Verify provider: run opencode and ask a test question."
fi
