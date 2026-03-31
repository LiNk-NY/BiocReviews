#!/usr/bin/env Rscript
#
# generate_review.R
#
# Minimal artifact reporter for Bioconductor package reviews.
# Reports results from R CMD check, BiocCheck, and covr without duplication.
#
# Usage:
#   Rscript generate_review.R <package_dir> [check_results.txt] \
#                             [bioccheck_results.txt] [coverage.json] \
#                             [output_file] [model_name]
#
# Arguments:
#   package_dir           Path to the package source directory (required)
#   check_results.txt     Path to R CMD check output file  (optional)
#   bioccheck_results.txt Path to BiocCheck output file    (optional)
#   coverage.json         Path to covr JSON output         (optional)
#   output_file           Where to write the review        (optional, stdout)
#   model_name            Name of the AI model used        (optional)
#                         Falls back to REVIEW_MODEL env var, then a default.
#
# All optional arguments can be supplied as "" to skip.

suppressPackageStartupMessages({
  library(methods)
})

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1 || !nzchar(args[[1]])) {
  cat("Usage: Rscript generate_review.R <package_dir> [check_results] ",
      "[bioccheck_results] [coverage.json] [output_file] [model_name]\n")
  quit(status = 1)
}

pkg_dir          <- normalizePath(args[[1]], mustWork = TRUE)
check_file       <- if (length(args) >= 2 && nzchar(args[[2]])) args[[2]] else ""
bioccheck_file   <- if (length(args) >= 3 && nzchar(args[[3]])) args[[3]] else ""
coverage_file    <- if (length(args) >= 4 && nzchar(args[[4]])) args[[4]] else ""
output_file      <- if (length(args) >= 5 && nzchar(args[[5]])) args[[5]] else ""
model_name       <- if (length(args) >= 6 && nzchar(args[[6]])) args[[6]] else ""

# Fall back to environment variable, then a descriptive default
if (!nzchar(model_name)) model_name <- Sys.getenv("REVIEW_MODEL", unset = "")
if (!nzchar(model_name)) model_name <- "Automated Review System"

# Convenience function: read a text file to a single string, return "" on error
read_txt <- function(path) {
  if (!nzchar(path) || !file.exists(path)) return("")
  tryCatch(paste(readLines(path, warn = FALSE), collapse = "\n"),
           error = function(e) "")
}

# Convenience function: grep lines from a character vector
grep_lines <- function(pattern, lines, ...) {
  grep(pattern, lines, perl = TRUE, value = TRUE, ...)
}

# Threshold above which cyclomatic complexity is flagged
CYCLOCOMP_THRESHOLD <- 10

# ---------------------------------------------------------------------------
# Read package metadata
# ---------------------------------------------------------------------------

desc_path <- file.path(pkg_dir, "DESCRIPTION")
if (!file.exists(desc_path)) stop("DESCRIPTION not found in ", pkg_dir)
desc <- read.dcf(desc_path)
desc <- setNames(as.character(desc[1, ]), colnames(desc))

get_field <- function(field, default = "") {
  trimws(if (field %in% names(desc)) desc[[field]] else default)
}

pkg_name    <- get_field("Package")
pkg_version <- get_field("Version")

# ---------------------------------------------------------------------------
# Parse R CMD check results
# ---------------------------------------------------------------------------

check_txt <- read_txt(check_file)
check_summary <- list()

if (nzchar(check_txt)) {
  check_lines <- strsplit(check_txt, "\n")[[1]]

  errors   <- grep_lines("^ERROR|ERROR:", check_lines)
  warnings <- grep_lines("WARNING", check_lines)
  notes    <- grep_lines("^NOTE|^\\* NOTE", check_lines)

  # Extract timing if available
  timing_match <- grep_lines("Duration:|Overall checktime", check_lines)
  if (length(timing_match) > 0) {
    check_summary$timing <- trimws(timing_match[1])
  }

  # Count issues
  check_summary$errors <- length(errors)
  check_summary$warnings <- length(warnings)
  check_summary$notes <- length(notes)

  # Store first few of each for display
  check_summary$error_lines <- head(trimws(errors), 5)
  check_summary$warning_lines <- head(trimws(warnings), 5)
  check_summary$note_lines <- head(trimws(notes), 5)
} else {
  check_summary$errors <- NA
  check_summary$warnings <- NA
  check_summary$notes <- NA
}

# ---------------------------------------------------------------------------
# Parse BiocCheck results
# ---------------------------------------------------------------------------

bioccheck_txt <- read_txt(bioccheck_file)
bioc_summary <- list()

if (nzchar(bioccheck_txt)) {
  bc_lines <- strsplit(bioccheck_txt, "\n")[[1]]

  bc_errors   <- grep_lines("ERROR|\\* REQUIRED", bc_lines, ignore.case = TRUE)
  bc_warnings <- grep_lines("WARNING|\\* RECOMMENDED", bc_lines, ignore.case = TRUE)
  bc_notes    <- grep_lines("NOTE|\\* CONSIDER", bc_lines, ignore.case = TRUE)

  # Remove lines that are just category headers
  bc_errors <- bc_errors[!grepl("^\\s*\\*{3,}|^={3,}", bc_errors)]
  bc_warnings <- bc_warnings[!grepl("^\\s*\\*{3,}|^={3,}", bc_warnings)]
  bc_notes <- bc_notes[!grepl("^\\s*\\*{3,}|^={3,}", bc_notes)]

  bioc_summary$errors <- length(bc_errors)
  bioc_summary$warnings <- length(bc_warnings)
  bioc_summary$notes <- length(bc_notes)

  bioc_summary$error_lines <- head(trimws(bc_errors), 5)
  bioc_summary$warning_lines <- head(trimws(bc_warnings), 5)
  bioc_summary$note_lines <- head(trimws(bc_notes), 5)
} else {
  bioc_summary$errors <- NA
  bioc_summary$warnings <- NA
  bioc_summary$notes <- NA
}

# ---------------------------------------------------------------------------
# Compute cyclomatic complexity
# ---------------------------------------------------------------------------

cyclo_results <- NULL

if (requireNamespace("cyclocomp", quietly = TRUE)) {
  tryCatch({
    r_files <- list.files(file.path(pkg_dir, "R"),
                          pattern = "\\.R$", full.names = TRUE,
                          ignore.case = TRUE)
    if (length(r_files) > 0) {
      cyclo_results <- cyclocomp::cyclocomp_r_files(r_files)
    }
  }, error = function(e) {
    message("cyclocomp failed: ", conditionMessage(e))
  })
}

# ---------------------------------------------------------------------------
# Run pkgndep analysis
# ---------------------------------------------------------------------------

pkgndep_result <- NULL
pkgndep_text   <- NULL

if (requireNamespace("pkgndep", quietly = TRUE)) {
  tryCatch({
    pkgndep_result <- pkgndep::pkgndep(pkg_dir)
    pkgndep_text   <- utils::capture.output(print(pkgndep_result))
  }, error = function(e) {
    message("pkgndep failed: ", conditionMessage(e))
  })
}

# ---------------------------------------------------------------------------
# Parse coverage results
# ---------------------------------------------------------------------------

coverage_pct <- NA_real_
filecoverage <- NULL

if (nzchar(coverage_file) && file.exists(coverage_file)) {
  # First try reading summary text file
  sum_path <- gsub("coverage\\.json$", "coverage_summary.txt", coverage_file)
  if (file.exists(sum_path)) {
    sumtxt <- read_txt(sum_path)
    m <- regmatches(sumtxt, regexpr("[0-9]+\\.?[0-9]*(?=%)", sumtxt, perl = TRUE))
    if (length(m) == 1) {
      coverage_pct <- as.numeric(m)
    }
  }

  # Try parsing JSON for detailed coverage
  if (is.na(coverage_pct) || is.null(filecoverage)) {
    tryCatch({
      cov <- jsonlite::fromJSON(coverage_file)
      if (!is.null(cov$filecoverage)) {
        # Calculate overall coverage
        vals <- unlist(lapply(cov$filecoverage, function(x) x$value))
        if (length(vals) > 0) {
          called <- sum(vapply(vals, function(v) sum(v > 0, na.rm = TRUE), integer(1)))
          total  <- sum(vapply(vals, length, integer(1)))
          if (total > 0 && is.na(coverage_pct)) {
            coverage_pct <- round(100 * called / total, 2)
          }
        }
        # Extract per-file coverage
        filecoverage <- vapply(cov$filecoverage, function(fc) {
          val <- fc$value
          if (length(val) == 0) return(0)
          round(100 * sum(val > 0, na.rm = TRUE) / length(val), 2)
        }, numeric(1))
      }
    }, error = function(e) {
      message("Warning: Could not parse coverage JSON: ", conditionMessage(e))
    })
  }
}

# ---------------------------------------------------------------------------
# Assemble markdown report
# ---------------------------------------------------------------------------

sections <- c(
  sprintf("# %s", pkg_name),
  "",
  "## Package Information",
  "",
  sprintf("* **Package**: %s", pkg_name),
  sprintf("* **Version**: %s", pkg_version),
  ""
)

# R CMD check section
sections <- c(sections, "## R CMD check", "")
if (!is.na(check_summary$errors)) {
  if (check_summary$errors == 0 && check_summary$warnings == 0 && check_summary$notes == 0) {
    sections <- c(sections, "* **Status**: PASS (0 errors, 0 warnings, 0 notes)")
  } else {
    sections <- c(sections, sprintf("* **Status**: %d error(s), %d warning(s), %d note(s)",
                                     check_summary$errors, check_summary$warnings, check_summary$notes))
  }

  if (!is.null(check_summary$timing)) {
    sections <- c(sections, sprintf("* **Timing**: %s", check_summary$timing))
  }

  if (check_summary$errors > 0) {
    sections <- c(sections, "", "### Errors", "")
    sections <- c(sections, paste("*", check_summary$error_lines))
  }

  if (check_summary$warnings > 0) {
    sections <- c(sections, "", "### Warnings", "")
    sections <- c(sections, paste("*", check_summary$warning_lines))
  }

  if (check_summary$notes > 0) {
    sections <- c(sections, "", "### Notes", "")
    sections <- c(sections, paste("*", check_summary$note_lines))
  }
} else {
  sections <- c(sections, "* R CMD check results not available")
}
sections <- c(sections, "")

# BiocCheck section
sections <- c(sections, "## BiocCheck", "")
if (!is.na(bioc_summary$errors)) {
  if (bioc_summary$errors == 0 && bioc_summary$warnings == 0 && bioc_summary$notes == 0) {
    sections <- c(sections, "* **Status**: PASS (0 errors, 0 warnings, 0 notes)")
  } else {
    sections <- c(sections, sprintf("* **Status**: %d error(s), %d warning(s), %d note(s)",
                                     bioc_summary$errors, bioc_summary$warnings, bioc_summary$notes))
  }

  if (bioc_summary$errors > 0) {
    sections <- c(sections, "", "### Errors", "")
    sections <- c(sections, paste("*", bioc_summary$error_lines))
  }

  if (bioc_summary$warnings > 0) {
    sections <- c(sections, "", "### Warnings", "")
    sections <- c(sections, paste("*", bioc_summary$warning_lines))
  }

  if (bioc_summary$notes > 0) {
    sections <- c(sections, "", "### Notes", "")
    sections <- c(sections, paste("*", bioc_summary$note_lines))
  }
} else {
  sections <- c(sections, "* BiocCheck results not available")
}
sections <- c(sections, "")

# Coverage section
sections <- c(sections, "## Test Coverage", "")
if (!is.na(coverage_pct)) {
  sections <- c(sections, sprintf("* **Overall coverage**: %.2f%%", coverage_pct))

  if (!is.null(filecoverage) && length(filecoverage) > 0) {
    sections <- c(sections, sprintf("* **Per-file coverage**: [%s]",
                                     paste(sprintf("%.2f%%", filecoverage), collapse = ", ")))
  }
} else {
  sections <- c(sections, "* Test coverage results not available")
}
sections <- c(sections, "")

# Static analysis section
sections <- c(sections, "## Static Analysis", "")
if (!is.null(cyclo_results) && is.data.frame(cyclo_results) && nrow(cyclo_results) > 0) {
  med_cc  <- median(cyclo_results$cyclocomp)
  max_cc  <- max(cyclo_results$cyclocomp)
  mean_cc <- round(mean(cyclo_results$cyclocomp), 2)

  sections <- c(sections,
    "### Cyclomatic Complexity",
    "",
    sprintf("* **Median**: %g | **Mean**: %g | **Max**: %g",
            med_cc, mean_cc, max_cc),
    ""
  )

  high_cc <- cyclo_results[cyclo_results$cyclocomp > CYCLOCOMP_THRESHOLD, , drop = FALSE]
  if (nrow(high_cc) > 0) {
    high_cc <- high_cc[order(-high_cc$cyclocomp), , drop = FALSE]
    sections <- c(sections,
      sprintf("Functions with cyclomatic complexity > %d (%d):", CYCLOCOMP_THRESHOLD, nrow(high_cc)),
      ""
    )
    top_n <- head(high_cc, 10)
    for (i in seq_len(nrow(top_n))) {
      sections <- c(sections,
        sprintf("* `%s`: %d", top_n$name[i], top_n$cyclocomp[i])
      )
    }
  } else {
    sections <- c(sections,
      sprintf("* No functions with cyclomatic complexity > %d.", CYCLOCOMP_THRESHOLD)
    )
  }
} else {
  sections <- c(sections, "* Cyclomatic complexity results not available")
}
sections <- c(sections, "")

# pkgndep section
sections <- c(sections, "### Dependency Load (pkgndep)", "")
if (!is.null(pkgndep_text) && length(pkgndep_text) > 0) {
  sections <- c(sections, "```", pkgndep_text, "```")
} else {
  sections <- c(sections, "* Dependency load analysis not available")
}
sections <- c(sections, "")

# Footer
repo_url <- "https://github.com/LiNk-NY/BiocReviews"
readme_url <- paste0(repo_url, "#readme")
review_date <- format(Sys.Date(), "%Y-%m-%d")

sections <- c(
  sections,
  "---",
  "",
  sprintf("*Review performed by **%s** on %s.*", model_name, review_date),
  sprintf("*Guidelines: [%s](%s)*", repo_url, readme_url)
)

output_text <- paste(sections, collapse = "\n")

# ---------------------------------------------------------------------------
# Write output
# ---------------------------------------------------------------------------

if (nzchar(output_file)) {
  writeLines(output_text, output_file)
  message("Review written to: ", output_file)
} else {
  cat(output_text, "\n")
}
