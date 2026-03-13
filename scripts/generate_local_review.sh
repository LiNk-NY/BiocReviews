#!/usr/bin/env bash
# generate_local_review.sh
#
# Wrapper script to generate an automated Bioconductor package review locally.
# Runs R CMD check, BiocCheck, test coverage (optional), then generates review.
#
# Usage:
#   ./scripts/generate_local_review.sh <package_dir> [output_file] [artifacts_dir]
#
# Arguments:
#   package_dir     Path to the R package source directory (required)
#   output_file     Where to write the review (optional, default: stdout)
#   artifacts_dir   Where to store check artifacts (optional, default: temp dir)
#                   Use a local directory for Docker compatibility
#
# Examples:
#   ./scripts/generate_local_review.sh ~/reviews/MyPackage
#   ./scripts/generate_local_review.sh package review.md build_artifacts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use relative path for Docker compatibility
REVIEW_SCRIPT="generate_review.R"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <package_dir> [output_file] [artifacts_dir]" >&2
  exit 1
fi

PKG_DIR="$1"
OUTPUT="${2:-}"
ARTIFACTS_DIR="${3:-}"

# Change to PROJECT_ROOT for Docker compatibility (all paths relative to BiocReviews)
cd "$PROJECT_ROOT"

# Verify PKG_DIR exists but keep it as relative path for Docker compatibility
if [[ ! -d "$PKG_DIR" ]]; then
  echo "Error: package directory not found: $PKG_DIR" >&2
  exit 1
fi

if [[ ! -f "$REVIEW_SCRIPT" ]]; then
  echo "Error: generate_review.R not found at $REVIEW_SCRIPT" >&2
  exit 1
fi

# Setup working directory for artifacts
if [[ -n "$ARTIFACTS_DIR" ]]; then
  # Use specified directory (Docker-compatible - under current directory)
  WORK_DIR="$ARTIFACTS_DIR"
  mkdir -p "$WORK_DIR"
  CLEANUP_WORK_DIR=false
else
  # Use temp directory (original behavior, may not work with Docker)
  WORK_DIR="$(mktemp -d)"
  CLEANUP_WORK_DIR=true
  trap 'rm -rf "$WORK_DIR"' EXIT
fi

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

# Get package name from DESCRIPTION for log file location
REAL_PKG_NAME=$(grep "^Package:" "$PKG_DIR/DESCRIPTION" | sed 's/^Package: *//')

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
  # Save the check object summary
  sink("$CHECK_FILE")
  print(check)
  sink()

  # Also copy the detailed 00check.log if available
  check_log <- file.path("$WORK_DIR", "check", paste0("$REAL_PKG_NAME", ".Rcheck"), "00check.log")
  if (file.exists(check_log)) {
    cat("\n\n=== Full R CMD check log ===\n\n", file = "$CHECK_FILE", append = TRUE)
    cat(readLines(check_log, warn = FALSE), sep = "\n", file = "$CHECK_FILE", append = TRUE)
  }
} else {
  file.create("$CHECK_FILE")
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

# Get package name from DESCRIPTION
REAL_PKG_NAME=$(grep "^Package:" "$PKG_DIR/DESCRIPTION" | sed 's/^Package: *//')

# Run BiocCheck (it writes to <package>.BiocCheck/00BiocCheck.log)
Rscript - <<EOF || true
if (requireNamespace("BiocCheck", quietly = TRUE)) {
  tryCatch(
    BiocCheck::BiocCheck(
      "$PKG_DIR",
      \`quit-with-status\` = FALSE,
      \`no-check-bioc-help\` = TRUE
    ),
    error = function(e) message("BiocCheck error: ", conditionMessage(e))
  )
} else {
  message("Skipping BiocCheck — install 'BiocCheck' to enable.")
}
EOF

# Copy BiocCheck log file to artifacts
if [[ -f "${REAL_PKG_NAME}.BiocCheck/00BiocCheck.log" ]]; then
  cp "${REAL_PKG_NAME}.BiocCheck/00BiocCheck.log" "$BIOCCHECK_FILE"
  echo "==> BiocCheck results copied from ${REAL_PKG_NAME}.BiocCheck/00BiocCheck.log" >&2
else
  echo "==> BiocCheck log not found at ${REAL_PKG_NAME}.BiocCheck/00BiocCheck.log" >&2
  touch "$BIOCCHECK_FILE"
fi
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
