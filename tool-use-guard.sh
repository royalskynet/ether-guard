#!/bin/bash
# tool-use-guard.sh: Pre-check for dangerous tool invocations
# Validates tool calls before execution
# Exit 0 = allowed, 1 = flagged, 2 = blocked
set -euo pipefail

tool_name="$1"
tool_args="$2"  # JSON string

# Define blocked/dangerous patterns
declare -A blocked_patterns=(
  ["rm -rf /"]="System wipe"
  ["rm -rf ~"]="Home directory wipe"
  ["> /dev/sda"]="Disk overwrite"
  ["dd if=/dev/zero"]="Disk zeroing"
  ["curl.*\\|.*sh"]="Pipe to shell"
  ["wget.*\\|.*sh"]="Pipe to shell"
  ["python.*-c.*import os"]="Python OS access"
  ["python.*-c.*import subprocess"]="Python subprocess"
  ["eval"]="Eval execution"
  ["exec"]="Exec execution"
  ["chmod 777"]="World writable"
  ["chmod +s"]="Setuid"
  ["sudo"]="Elevated privileges"
  ["root"]="Root access"
)

# Check for dangerous patterns
for pattern in "${!blocked_patterns[@]}"; do
  if echo "$tool_args" | grep -qE "$pattern"; then
    echo "❌ BLOCKED: Dangerous pattern detected" >&2
    echo "  Pattern: $pattern" >&2
    echo "  Description: ${blocked_patterns[$pattern]}" >&2
    echo "  Tool: $tool_name" >&2
    echo "  Args: $tool_args" >&2
    exit 2
  fi
done

# Check for suspicious URL patterns
if echo "$tool_args" | grep -qE '(?i)(http|https)://[^ ]*\.(exe|sh|bat|ps1|cmd)'; then
  echo "⚠️  WARNING: Executable download URL detected" >&2
  echo "  This could be a behavioral control trap" >&2
  exit 1
fi

# Check for base64 encoded commands (common evasion)
if echo "$tool_args" | grep -qE '[A-Za-z0-9+/]{50,}={0,2}'; then
  echo "⚠️  WARNING: Potential base64 encoded payload" >&2
  echo "  Consider decoding and inspecting" >&2
  exit 1
fi

exit 0
