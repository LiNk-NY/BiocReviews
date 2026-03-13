#!/usr/bin/env bash
# generate_local_review.sh
#
# Wrapper script to generate an automated Bioconductor package review locally.
# Runs R CMD check, BiocCheck, test coverage (optional), then generates review.
#
# Usage:
#   ./scripts/generate_local_review.sh <package_dir> [output_file]
#
# Arguments:
#   package_dir   Path to the R package source directory (required)
#   output_file   Where to write the review (optional, default: stdout)
#
# Examples:
#   ./scripts/generate_local_review.sh ~/reviews/MyPackage
#   ./scripts/generate_local_review.sh ~/reviews/MyPackage MyPackage_review.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVIEW_SCRIPT="$SCRIPT_DIR/../generate_review.R"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <package_dir> [output_file]" >&2
  exit 1
fi

PKG_DIR="$(realpath "$1")"
OUTPUT="${2:-}"

if [[ ! -d "$PKG_DIR" ]]; then
  echo "Error: package directory not found: $PKG_DIR" >&2
  exit 1
fi

if [[ ! -f "$REVIEW_SCRIPT" ]]; then
  echo "Error: generate_review.R not found at $REVIEW_SCRIPT" >&2
  exit 1
fi

# Create a temp working directory for artifact files
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

PKG_NAME="$(basename "$PKG_DIR")"
echo "==> Reviewing package: $PKG_NAME" >&2
echo "==> Working directory: $WORK_DIR" >&2

CHECK_FILE="$WORK_DIR/check_results.txt"
BIOCCHECK_FILE="$WORK_DIR/bioccheck_results.txt"
COVERAGE_FILE="$WORK_DIR/coverage.json"

# ---------------------------------------------------------------------------
# R CMD check
# ---------------------------------------------------------------------------
echo "" >&2
echo "==> Running R CMD check..." >&2
Rscript - <<EOF
suppressPackageStartupMessages(library(rcmdcheck))
check <- tryCatch(
  rcmdcheck::rcmdcheck(
    "$PKG_DIR",
    args = "--no-manual",
    error_on = "never",
    check_dir = file.path("$WORK_DIR", "check")
  ),
  error = function(e) {
    message("rcmdcheck failed: ", conditionMessage(e))
    NULL
  }
)
if (!is.null(check)) {
  sink("$CHECK_FILE")
  print(check)
  sink()
}
EOF
echo "==> R CMD check done." >&2

# ---------------------------------------------------------------------------
# Test coverage (optional — skip if covr not installed)
# ---------------------------------------------------------------------------
echo "" >&2
echo "==> Running test coverage (may take a while; skip with Ctrl+C to continue)..." >&2
Rscript - <<EOF || true
if (requireNamespace("covr", quietly = TRUE) &&
    requireNamespace("jsonlite", quietly = TRUE)) {
  cov <- tryCatch(
    covr::package_coverage("$PKG_DIR", quiet = FALSE, type = "all"),
    error = function(e) { message("Coverage failed: ", conditionMessage(e)); NULL }
  )
  if (!is.null(cov)) {
    pct <- round(covr::percent_coverage(cov), 2)
    writeLines(paste0("Total Coverage: ", pct, "%"),
               file.path("$WORK_DIR", "coverage_summary.txt"))
    jsonlite::write_json(
      covr::coverage_to_list(cov),
      "$COVERAGE_FILE",
      auto_unbox = TRUE, pretty = TRUE
    )
    message("Coverage: ", pct, "%")
  }
} else {
  message("Skipping coverage — install 'covr' and 'jsonlite' to enable.")
}
EOF
echo "==> Coverage done." >&2

# ---------------------------------------------------------------------------
# BiocCheck
# ---------------------------------------------------------------------------
echo "" >&2
echo "==> Running BiocCheck..." >&2
Rscript - <<EOF || true
if (requireNamespace("BiocCheck", quietly = TRUE)) {
  sink("$BIOCCHECK_FILE")
  tryCatch(
    BiocCheck::BiocCheck(
      "$PKG_DIR",
      \`quit-with-status\` = FALSE,
      \`no-check-bioc-help\` = TRUE
    ),
    error = function(e) message("BiocCheck error: ", conditionMessage(e))
  )
  sink()
} else {
  message("Skipping BiocCheck — install 'BiocCheck' to enable.")
}
EOF
echo "==> BiocCheck done." >&2

# ---------------------------------------------------------------------------
# Generate review
# ---------------------------------------------------------------------------
echo "" >&2
echo "==> Generating review..." >&2

RSCRIPT_ARGS=(
  "$REVIEW_SCRIPT"
  "$PKG_DIR"
  "$CHECK_FILE"
  "$BIOCCHECK_FILE"
  "$COVERAGE_FILE"
  "$OUTPUT"
)

Rscript "${RSCRIPT_ARGS[@]}"

if [[ -n "$OUTPUT" ]]; then
  echo "" >&2
  echo "==> Review written to: $OUTPUT" >&2
fi
