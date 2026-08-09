#!/bin/bash
# memory-guard.sh: Detect RAG/knowledge base poisoning attempts
# Checks for injection patterns in document metadata and content
# Exit 0 = clean, 1 = warning, 2 = blocked
set -euo pipefail

score=0
warnings=()

# Check for suspicious metadata patterns
check_file() {
  local file="$1"
  
  # Check for embedded instructions in various formats
  if grep -qE '(?i)(system instruction|ignore all|bypass|override|new directive)' "$file" 2>/dev/null; then
    score=$((score + 2))
    warnings+=("Found instruction override patterns in: $file")
  fi
  
  # Check for suspicious XML/JSON metadata
  if grep -qE '(?i)<meta[^>]*role="instruction"|<meta[^>]*data-prompt' "$file" 2>/dev/null; then
    score=$((score + 2))
    warnings+=("Found injected metadata in: $file")
  fi
  
  # Check for encoding tricks (zero-width chars, homoglyphs)
  if grep -qP '[\x00-\x08\x0B\x0C\x0E-\x1F\x80-\xFF]' "$file" 2>/dev/null; then
    score=$((score + 1))
    warnings+=("Found suspicious encoding in: $file")
  fi
}

# Process all input files
for arg in "$@"; do
  if [ -f "$arg" ]; then
    check_file "$arg"
  elif [ -d "$arg" ]; then
    find "$arg" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.json" -o -name "*.yaml" \) | while read -r f; do
      check_file "$f"
    done
  fi
done

# Output results
if [ "$score" -gt 0 ]; then
  echo "⚠️  Memory Guard: $score risk points" >&2
  for w in "${warnings[@]}"; do
    echo "  $w" >&2
  done
  exit 2
fi

exit 0
