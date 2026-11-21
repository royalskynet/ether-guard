#!/bin/bash
# ether-guard: Multi-layer defense for AI agents
# Combines: claude-safe-guard + content-guard + memory-guard + tool-use-guard
#
# Usage:
#   ether-guard [mode] [args...]
#
# Modes:
#   scan [threshold] <file> - Scan file for content traps
#   check <tool> <args> - Pre-check tool invocation
#   all <dir>       - Full scan of directory
#
# Exit codes: 0=clean, 1=warning, 2=blocked
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

scan_content_files() {
  local file status worst=0
  while IFS= read -r -d '' file; do
    status=0
    bash "$SCRIPT_DIR/content-guard.sh" "$file" || status=$?
    case "$status" in
      1) printf '⚠️  Warning: %s\n' "$file" >&2 ;;
      2) printf '❌ Blocked: %s\n' "$file" >&2 ;;
    esac
    if [ "$status" -gt "$worst" ]; then
      worst="$status"
    fi
  done
  return "$worst"
}

mode="${1:-scan}"
shift || true

echo "🛡️  Ether Guard - Multi-Layer AI Agent Defense" >&2
echo "   Mode: $mode" >&2
echo "   $(date '+%Y-%m-%d %H:%M:%S')" >&2
echo "" >&2

case "$mode" in
  scan)
    # Content scanning mode
    if [ $# -eq 0 ]; then
      echo "Usage: ether-guard scan [threshold] <file>" >&2
      exit 1
    fi
    bash "$SCRIPT_DIR/content-guard.sh" "$@"
    ;;
    
  check)
    # Tool use validation
    if [ $# -lt 2 ]; then
      echo "Usage: ether-guard check <tool_name> <args_json>" >&2
      exit 1
    fi
    tool_name="$1"
    shift
    bash "$SCRIPT_DIR/tool-use-guard.sh" "$tool_name" "$*"
    ;;
    
  all)
    # Full directory scan
    if [ $# -eq 0 ]; then
      echo "Usage: ether-guard all <directory>" >&2
      exit 1
    fi
    dir="$1"
    if [ ! -d "$dir" ]; then
      printf 'Not a directory: %s\n' "$dir" >&2
      exit 1
    fi
    case "$dir" in
      /*) ;;
      *) dir="./$dir" ;;
    esac
    
    echo "📁 Scanning: $dir" >&2
    echo "" >&2
    
    # Layer 1: Project config scan
    echo "🔍 Layer 1: Project config scan..." >&2
    worst=0
    bash "$SCRIPT_DIR/claude-safe-guard.sh" "$dir" || worst=$?
    
    # Layer 2: Content scan
    echo "🔍 Layer 2: Content trap scan..." >&2
    status=0
    find "$dir" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) -print0 |
      scan_content_files || status=$?
    if [ "$status" -gt "$worst" ]; then
      worst="$status"
    fi
    
    # Layer 3: Memory/RAG scan
    echo "🔍 Layer 3: Memory poisoning scan..." >&2
    status=0
    bash "$SCRIPT_DIR/memory-guard.sh" "$dir" || status=$?
    if [ "$status" -gt "$worst" ]; then
      worst="$status"
    fi
    if [ "$worst" -eq 0 ]; then
      echo "" >&2
      echo "✅ All layers passed" >&2
    fi
    exit "$worst"
    ;;
    
  help|--help|-h)
    cat <<EOF
Ether Guard - Multi-Layer AI Agent Defense

Usage: ether-guard <mode> [args...]

Modes:
  scan [threshold] <file>  Scan file for content traps (default threshold: 2)
  check <tool> <args>  Validate tool invocation before execution
  all <dir>       Full multi-layer scan of directory
  help            Show this help

Layers:
  1. Project config scan (claude-safe-guard)
  2. Content trap detection (content-guard)
  3. Memory poisoning detection (memory-guard)
  4. Tool use validation (tool-use-guard)

Exit codes: 0=clean, 1=warning, 2=blocked
EOF
    ;;
    
  *)
    echo "Unknown mode: $mode" >&2
    echo "Run 'ether-guard help' for usage" >&2
    exit 1
    ;;
esac
