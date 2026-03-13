#!/usr/bin/env bash
# enhance_review_with_github_models.sh
#
# Local convenience wrapper for enhance_review_with_github_models.R.
#
# Usage:
#   ./scripts/enhance_review_with_github_models.sh [base_review] [output_review] [artifacts_dir]
#
# Arguments:
#   base_review    Base markdown review to enhance (default: automated_review.md)
#   output_review  Output markdown path (default: automated_review_llm.md)
#   artifacts_dir  Directory containing check_results.txt, bioccheck_results.txt,
#                  coverage.json (default: current directory)
#
# Environment variables:
#   GITHUB_TOKEN       Required for GitHub Models API
#   GITHUB_MODEL       Optional, default: meta-llama-3.1-405b-instruct
#   MAX_PROMPT_CHARS   Optional, default: 120000
#   REVIEW_MAX_TOKENS  Optional, default: 2800

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENHANCER_SCRIPT="$SCRIPT_DIR/enhance_review_with_github_models.R"

BASE_REVIEW="${1:-automated_review.md}"
OUTPUT_REVIEW="${2:-automated_review_llm.md}"
ARTIFACTS_DIR="${3:-.}"

if [[ ! -f "$ENHANCER_SCRIPT" ]]; then
  echo "Error: enhancer script not found: $ENHANCER_SCRIPT" >&2
  exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Error: GITHUB_TOKEN is not set." >&2
  echo "Set it first, e.g. export GITHUB_TOKEN=\$(gh auth token)" >&2
  exit 1
fi

cd "$PROJECT_ROOT"

if [[ ! -f "$BASE_REVIEW" ]]; then
  echo "Error: base review not found: $BASE_REVIEW" >&2
  exit 1
fi

if [[ ! -d "$ARTIFACTS_DIR" ]]; then
  echo "Error: artifacts directory not found: $ARTIFACTS_DIR" >&2
  exit 1
fi

CHECK_FILE="$ARTIFACTS_DIR/check_results.txt"
BIOCCHECK_FILE="$ARTIFACTS_DIR/bioccheck_results.txt"
COVERAGE_FILE="$ARTIFACTS_DIR/coverage.json"

if [[ ! -f "$CHECK_FILE" ]]; then CHECK_FILE=""; fi
if [[ ! -f "$BIOCCHECK_FILE" ]]; then BIOCCHECK_FILE=""; fi
if [[ ! -f "$COVERAGE_FILE" ]]; then COVERAGE_FILE=""; fi

GUIDELINES_FILE="${GUIDELINES_FILE:-$PROJECT_ROOT/.github/bioc-review-guidelines.instructions.md}"

echo "Enhancing review with GitHub Models..." >&2
echo "  Base:      $BASE_REVIEW" >&2
echo "  Output:    $OUTPUT_REVIEW" >&2
echo "  Artifacts: $ARTIFACTS_DIR" >&2
echo "  Model:     ${GITHUB_MODEL:-meta-llama-3.1-405b-instruct}" >&2

Rscript "$ENHANCER_SCRIPT" \
  --base-review "$BASE_REVIEW" \
  --output "$OUTPUT_REVIEW" \
  --check-file "$CHECK_FILE" \
  --bioccheck-file "$BIOCCHECK_FILE" \
  --coverage-file "$COVERAGE_FILE" \
  --model "${GITHUB_MODEL:-meta-llama-3.1-405b-instruct}" \
  --max-prompt-chars "${MAX_PROMPT_CHARS:-120000}" \
  --max-tokens "${REVIEW_MAX_TOKENS:-2800}" \
  --guidelines-file "$GUIDELINES_FILE"

echo "Done: $OUTPUT_REVIEW" >&2