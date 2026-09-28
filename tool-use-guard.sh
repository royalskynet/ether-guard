#!/bin/bash
# tool-use-guard.sh: Pre-check for dangerous tool invocations
# Validates tool calls before execution to prevent behavioral control traps
# Exit 0 = allowed, 1 = flagged, 2 = blocked
set -euo pipefail

tool_name="${1:-}"
tool_args="${2:-}"

if [ -z "$tool_name" ] || [ -z "$tool_args" ]; then
  echo "Usage: tool-use-guard.sh <tool_name> <args_json>" >&2
  exit 1
fi

score=0
issues=()

# Block dangerous system commands
dangerous_patterns=(
  'rm\s+-rf\s+/|rm\s+-rf\s+~'
  'dd\s+if=/dev/'
  'mkfs'
  '>\\s*/dev/'
  'curl.*\\|\\s*sh'
  'wget.*\\|\\s*sh'
  'python.*-c.*import\\s+os'
  'python.*-c.*import\\s+subprocess'
  'eval\\s'
  'exec\\s'
  'chmod\\s+777'
  'chmod\\s+[0-7]*[4-7]'
  'sudo'
  'root'
)

# Check for dangerous patterns
for pattern in "${dangerous_patterns[@]}"; do
  if echo "$tool_args" | grep -qE "$pattern" 2>/dev/null; then
    score=$((score + 3))
    issues+=("DANGEROUS: $pattern")
  fi
done

# Check for suspicious URLs (executable downloads)
if echo "$tool_args" | grep -qiE 'https?://[^"]+\.(exe|sh|bat|ps1|cmd)'; then
  score=$((score + 2))
  issues+=("SUSPICIOUS: Executable download URL")
fi

# Check for base64 encoded commands (evasion technique)
if echo "$tool_args" | grep -qE '[A-Za-z0-9+/]{50,}={0,2}'; then
  score=$((score + 1))
  issues+=("WARNING: Potential base64 encoded payload")
fi

# Check for prompt injection patterns in args
injection_patterns=(
  'IGNORE\s+PREVIOUS'
  'DISREGARD\s+ABOVE'
  'NEW\s+INSTRUCTION'
  'SYSTEM\s+OVERRIDE'
  'BYPASS\s+SECURITY'
)

for pattern in "${injection_patterns[@]}"; do
  if echo "$tool_args" | grep -qiE "$pattern"; then
    score=$((score + 2))
    issues+=("INJECTION: $pattern detected")
  fi
done

# Output results
if [ "$score" -gt 0 ]; then
  echo "⚠️  Tool Use Guard: $score risk points" >&2
  for issue in "${issues[@]}"; do
    echo "  $issue" >&2
  done
  
  if [ "$score" -ge 3 ]; then
    echo "❌ BLOCKED: Dangerous tool invocation" >&2
    exit 2
  fi
  
  echo "⚠️  WARNING: Review recommended" >&2
  exit 1
fi

exit 0
