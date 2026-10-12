# Ether Guard v2

**English** | [繁體中文](README.zh-TW.md)

A multi-layer defense framework for AI agents, built on the "AI Agent Traps"
taxonomy from Google DeepMind. Every layer is a standalone Bash script: install the
whole set, or run the individual scripts by hand.

## Quick install

```bash
git clone https://github.com/royalskynet/ether-guard.git && cd ether-guard && ./install-v2.sh
```

Open a new shell afterwards so the `ether-guard` wrapper is picked up:

```bash
source ~/.zshrc
```

The installer copies every guard script into `~/.claude/scripts/`, marks it
executable, and appends an `ether-guard` shell wrapper to `~/.zshrc` and
`~/.bashrc`. Only shell files that already exist are touched, nothing outside your
home directory is written, and re-running the installer is safe.

## Installers

| Script | What it installs |
|--------|------------------|
| `install-v2.sh` | All five guard scripts plus the `ether-guard` wrapper function (recommended) |
| `install.sh` | `claude-safe-guard.sh` only, plus a wrapper that scans the current directory before the `claude` command runs |

## The six layers

| Layer | Script | Guards against |
|-------|--------|----------------|
| 1 | `claude-safe-guard.sh` | Project config injection (`.mcp.json`, `.claude/settings.*.json`) |
| 2 | `content-guard.sh` | Content injection + semantic manipulation (hidden instructions, authority pressure) |
| 3 | `memory-guard.sh` | RAG / memory poisoning (embedded instructions, encoding tricks) |
| 4 | `tool-use-guard.sh` | Behavioural control (dangerous commands, base64 steganography) |
| 5 | *(planned)* | Systemic traps (multi-agent coordination monitoring) |
| 6 | *(planned)* | Human-in-the-loop traps (decision fatigue, automation bias) |

## Usage

```bash
# Scan a single file
ether-guard scan <file>

# Validate a tool invocation
ether-guard check <tool_name> '<args_json>'

# Full directory scan
ether-guard all <directory>

# Help
ether-guard help
```

Without installing, run the same script straight from a clone:

```bash
bash ether-guard.sh help
bash ether-guard.sh check Bash '{"command":"rm -rf ~"}'
```

Exit codes are the same everywhere: `0` clean, `1` warning, `2` blocked.

## Known limitations

These are current behaviours of the scripts, not design goals:

- `scan` reads its **first argument as the numeric score threshold**, so
  `ether-guard scan <file>` makes layer 2 report `integer expression expected` and
  exit `1`. `ether-guard scan 1 <file>` is the form that actually blocks (exit `2`).
- `all` walks layers 1–3. Layer 4 is only reachable through `check`.
- Layer 3 scores a directory inside a pipeline subshell, so its score is lost and
  directory scans always come back clean.
- Layer 3's encoding check uses `grep -P`; the BSD `grep` shipped with macOS has no
  `-P`, so that single check is silently skipped there.
- Layer 1 is exact-string `grep`, not a JSON parser (as its own comments note), so a
  deliberately crafted config file could evade it. Upgrade to `jq`-based checks if
  evasion resistance matters.

## Design principles

- **Progressive defense**: each layer is independent and can be enabled on its own.
- **Low false positives**: by default only known attack patterns are blocked.
- **Composable**: traps chain together, so defense should chain as well.

## References

- [AI Agent Traps](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6372438) - Google DeepMind, 2026
- [Prompt Guard](https://github.com/seojoonkim/prompt-guard) - detection engine reference
- [Lasso Security](https://github.com/lasso-security/claude-hooks) - Claude Code hooks reference

## License

MIT — see [LICENSE](LICENSE).