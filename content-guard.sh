#!/bin/bash
# content-guard.sh: Scan file/web content for AI Agent Trap patterns
# Detects: hidden instructions, malicious metadata, suspicious formatting
# Exit 0 = clean, 1 = warnings, 2 = critical
set -euo pipefail

threshold="${1:-2}"  # 0=strict, 1=medium, 2=normal
score=0
issues=()

# --- Pattern categories ---
# Content Injection: hidden text, invisible characters, metadata exploits
injection_patterns=(
  'display:none'
  'visibility:hidden'
  'opacity:0'
  'font-size:0'
  '<meta[^>]*content[^>]*="?system[^"]*instruction'
  '<meta[^>]*name[^>]*="?system[^"]*'
  'role="instruction"'
  'aria-label="instruction"'
  '<style[^>]*>\s*[^<]{200,}'
  'data-role="prompt"'
  'data-instruction'
  'ignore_previous'
  'disregard_above'
)

# Semantic Manipulation: authority pressure, urgency, emotional triggers
semantic_patterns=(
  'URGENT|CRITICAL|EMERGENCY|IMMEDIATE'
  'CONFIDENTIAL|SECRET|CLASSIFIED'
  'IMPORTANT NOTICE|ATTENTION|WARNING'
  'Administrator|Admin|Security Team|IT Department'
  'system override|bypass|elevated'
  'do not question|follow exactly|execute immediately'
  'life|death|emergency|critical failure'
)

# Check each pattern
for pattern in "${injection_patterns[@]}"; do
  if grep -qiE "$pattern" "$@" 2>/dev/null; then
    score=$((score + 2))
    issues+=("[INJECTION] Pattern: $pattern")
  fi
done

for pattern in "${semantic_patterns[@]}"; do
  if grep -qiE "$pattern" "$@" 2>/dev/null; then
    score=$((score + 1))
    issues+=("[SEMANTIC] Pattern: $pattern")
  fi
done

# Output results
if [ "$score" -gt 0 ]; then
  echo "⚠️  Content Guard: $score risk points detected" >&2
  for issue in "${issues[@]}"; do
    echo "  $issue" >&2
  done
  
  if [ "$score" -ge "$threshold" ]; then
    echo "❌ BLOCKED: Content contains suspicious patterns" >&2
    exit 2
  fi
  echo "⚠️  WARNING: Review recommended" >&2
  exit 1
fi

exit 0
