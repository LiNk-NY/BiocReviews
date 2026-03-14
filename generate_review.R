#!/usr/bin/env Rscript
#
# generate_review.R
#
# Automated Bioconductor package reviewer.
# Analyzes package source code and workflow artifacts (R CMD check, BiocCheck,
# coverage) to produce a structured review following Bioconductor guidelines.
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
if (!nzchar(model_name)) model_name <- "GitHub Copilot (automated reviewer)"

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

# Append a bullet to the section list (text may be multiple strings, collapsed)
bullet <- function(tag, ...) list(tag = tag, text = paste0(..., collapse = ""))

# Combine bullets into a section string
render_section <- function(heading, bullets) {
  lines <- paste("*", vapply(bullets, `[[`, character(1), "text"))
  if (length(lines) == 0) lines <- "* Looks good."
  paste(c(paste("##", heading), lines, ""), collapse = "\n")
}

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
pkg_title   <- get_field("Title")
pkg_desc    <- get_field("Description")
pkg_authors <- get_field("Authors@R")
pkg_author  <- get_field("Author")       # old style
pkg_license <- get_field("License")
pkg_views   <- get_field("biocViews")
pkg_depends <- get_field("Depends")
pkg_imports <- get_field("Imports")
pkg_suggests<- get_field("Suggests")
pkg_remotes <- get_field("Remotes")
pkg_bug     <- get_field("BugReports")
pkg_url     <- get_field("URL")
pkg_lazy    <- get_field("LazyData")
pkg_sysreq  <- get_field("SystemRequirements")

# Directories present
has_vignettes <- dir.exists(file.path(pkg_dir, "vignettes"))
has_tests     <- dir.exists(file.path(pkg_dir, "tests"))
has_data      <- dir.exists(file.path(pkg_dir, "data"))
has_man       <- dir.exists(file.path(pkg_dir, "man"))
has_src       <- dir.exists(file.path(pkg_dir, "src"))
has_inst      <- dir.exists(file.path(pkg_dir, "inst"))

r_files <- list.files(file.path(pkg_dir, "R"), pattern = "\\.R$",
                       full.names = TRUE, recursive = TRUE)
r_src   <- lapply(r_files, function(f)
  tryCatch(readLines(f, warn = FALSE), error = function(e) character(0)))
names(r_src) <- basename(r_files)
r_all_lines <- unlist(r_src)

vignette_files <- list.files(file.path(pkg_dir, "vignettes"),
                              pattern = "\\.(Rmd|Rnw|rmd)$",
                              full.names = TRUE, recursive = TRUE)
vignette_src   <- lapply(vignette_files, function(f)
  tryCatch(readLines(f, warn = FALSE), error = function(e) character(0)))
names(vignette_src) <- basename(vignette_files)
vignette_all_lines  <- unlist(vignette_src)

namespace_path  <- file.path(pkg_dir, "NAMESPACE")
namespace_lines <- if (file.exists(namespace_path))
  readLines(namespace_path, warn = FALSE) else character(0)

# ---------------------------------------------------------------------------
# Read artifact files
# ---------------------------------------------------------------------------

check_txt     <- read_txt(check_file)
bioccheck_txt <- read_txt(bioccheck_file)
coverage_txt  <- read_txt(coverage_file)

# Parse coverage percentage from summary text or JSON
parse_coverage_pct <- function(cov_json_path) {
  if (!nzchar(cov_json_path) || !file.exists(cov_json_path)) return(NA_real_)
  tryCatch({
    cov <- jsonlite::fromJSON(cov_json_path)
    # covr JSON structure: list with $filecoverage
    vals <- unlist(lapply(cov$filecoverage, function(x) x$value))
    if (length(vals) == 0) return(NA_real_)
    called <- sum(vapply(vals, function(v) sum(v > 0, na.rm = TRUE), integer(1)))
    total  <- sum(vapply(vals, length, integer(1)))
    if (total == 0) return(NA_real_)
    round(100 * called / total, 2)
  }, error = function(e) NA_real_)
}

cov_pct <- if (nzchar(coverage_file) && file.exists(coverage_file)) {
  # First try reading summary
  sum_path <- gsub("coverage\\.json$", "coverage_summary.txt", coverage_file)
  if (file.exists(sum_path)) {
    sumtxt <- read_txt(sum_path)
    m <- regmatches(sumtxt, regexpr("[0-9]+\\.?[0-9]*(?=%)", sumtxt, perl = TRUE))
    if (length(m) == 1) as.numeric(m) else parse_coverage_pct(coverage_file)
  } else {
    parse_coverage_pct(coverage_file)
  }
} else NA_real_

# ---------------------------------------------------------------------------
# Section 1: DESCRIPTION review
# ---------------------------------------------------------------------------

desc_bullets <- list()

# Version check
if (!grepl("^0\\.99", pkg_version)) {
  desc_bullets[[length(desc_bullets)+1]] <- bullet("version",
    paste0("Version `", pkg_version, "` — first Bioconductor submissions should ",
           "use version `0.99.0`."))
}

# Title
if (!nzchar(pkg_title)) {
  desc_bullets[[length(desc_bullets)+1]] <- bullet("title",
    "**[Required]** `Title` field is missing.")
} else if (grepl("\\.$", pkg_title)) {
  desc_bullets[[length(desc_bullets)+1]] <- bullet("title",
    "Remove the trailing period from the `Title` field.")
}

# Description length
n_sentences <- length(gregexpr("[.!?]\\s", pkg_desc)[[1]])
if (nchar(pkg_desc) < 120 || n_sentences < 2) {
  desc_bullets[[length(desc_bullets)+1]] <- bullet("description",
    "**[Required]** The `Description` field should contain at least three ",
    "complete sentences providing a detailed overview of the package.")
}

# Authors@R
if (!nzchar(pkg_authors)) {
  if (nzchar(pkg_author)) {
    desc_bullets[[length(desc_bullets)+1]] <- bullet("authors",
      "**[Required]** Use `Authors@R` instead of the deprecated `Author:` ",
      "and `Maintainer:` fields.")
  } else {
    desc_bullets[[length(desc_bullets)+1]] <- bullet("authors",
      "**[Required]** `Authors@R` field is missing.")
  }
} else {
  if (!grepl("cre", pkg_authors)) {
    desc_bullets[[length(desc_bullets)+1]] <- bullet("authors",
      "**[Required]** No maintainer (`role = \"cre\"`) found in `Authors@R`.")
  }
  if (!grepl("ORCID", pkg_authors, ignore.case = TRUE)) {
    desc_bullets[[length(desc_bullets)+1]] <- bullet("orcid",
      "Consider adding an ORCiD identifier for the maintainer via ",
      "`comment = c(ORCID = \"XXXX-XXXX-XXXX-XXXX\")` in `Authors@R`.")
  }
}

# License
bad_licenses <- c("CC BY-NC", "CC-BY-NC", "ACM", "CC BY-ND", "CC BY-SA")
if (any(vapply(bad_licenses, function(l) grepl(l, pkg_license, fixed = TRUE),
               logical(1)))) {
  desc_bullets[[length(desc_bullets)+1]] <- bullet("license",
    paste0("**[Required]** License `", pkg_license, "` restricts use and is ",
           "not compatible with Bioconductor. Use an open license such as ",
           "`Artistic-2.0`, `GPL-2`, `GPL-3`, or `MIT + file LICENSE`."))
}

# biocViews
if (!nzchar(pkg_views)) {
  desc_bullets[[length(desc_bullets)+1]] <- bullet("biocViews",
    "**[Required]** `biocViews` field is missing. Provide at least two leaf-node ",
    "terms from the same trunk category (Software, AnnotationData, etc.).")
} else {
  views_vec <- trimws(strsplit(pkg_views, ",")[[1]])
  if (length(views_vec) < 2) {
    desc_bullets[[length(desc_bullets)+1]] <- bullet("biocViews",
      "**[Required]** Provide at least two `biocViews` leaf-node terms.")
  }
}

# Remotes field
if (nzchar(pkg_remotes)) {
  desc_bullets[[length(desc_bullets)+1]] <- bullet("remotes",
    "**[Required]** The `Remotes:` field is not supported by Bioconductor. All ",
    "dependencies must be available on Bioconductor or CRAN.")
}

# BugReports
if (!nzchar(pkg_bug)) {
  desc_bullets[[length(desc_bullets)+1]] <- bullet("bugreports",
    "Consider adding a `BugReports` field linking to the GitHub issue tracker.")
}

# URL
if (!nzchar(pkg_url)) {
  desc_bullets[[length(desc_bullets)+1]] <- bullet("url",
    "Consider adding a `URL` field linking to the source repository.")
}

# LazyData
if (grepl("true", pkg_lazy, ignore.case = TRUE)) {
  desc_bullets[[length(desc_bullets)+1]] <- bullet("lazydata",
    "`LazyData: TRUE` can slow down package loading for packages with data. ",
    "Remove this field unless there is a specific reason to keep it.")
}

if (length(desc_bullets) == 0) {
  desc_bullets[[1]] <- bullet("ok", "Looks good.")
}

# ---------------------------------------------------------------------------
# Section 2: NAMESPACE review
# ---------------------------------------------------------------------------

ns_bullets <- list()

# Check for import(wholePkg) for non-trivial packages
whole_imports <- grep_lines("^import\\(", namespace_lines)
if (length(whole_imports) > 3) {
  ns_bullets[[length(ns_bullets)+1]] <- bullet("imports",
    paste0("Found ", length(whole_imports), " whole-package `import()` calls. ",
           "Prefer explicit `importFrom(pkg, fun)` to minimize namespace ",
           "pollution and make dependencies explicit."))
}

# Exported functions: check for undocumented exports
exported_fns <- gsub("export\\((.+)\\)", "\\1",
                     grep_lines("^export\\(", namespace_lines))
exported_fns <- trimws(exported_fns)

# Check if exported names use dots (S3-problematic)
dot_exports <- exported_fns[grepl("\\.", exported_fns) &
                              !grepl("^\\.", exported_fns)]
if (length(dot_exports) > 0) {
  ns_bullets[[length(ns_bullets)+1]] <- bullet("dots",
    paste0("Exported function(s) contain `.` in their names: ",
           paste(head(dot_exports, 5), collapse = ", "),
           ". This can conflict with S3 dispatch. ",
           "Prefer `camelCase` naming."))
}

if (length(ns_bullets) == 0) {
  ns_bullets[[1]] <- bullet("ok", "Looks good.")
}

# ---------------------------------------------------------------------------
# Section 3: Vignette review
# ---------------------------------------------------------------------------

vig_bullets <- list()

if (!has_vignettes || length(vignette_files) == 0) {
  vig_bullets[[length(vig_bullets)+1]] <- bullet("missing",
    "**[Required]** No vignettes found. A vignette demonstrating package ",
    "usage is required.")
} else {
  # eval=FALSE usage
  eval_false_count <- sum(grepl("eval\\s*=\\s*FALSE|eval=FALSE",
                                vignette_all_lines, perl = TRUE))
  if (eval_false_count > 0) {
    vig_bullets[[length(vig_bullets)+1]] <- bullet("eval_false",
      paste0("`eval=FALSE` found in ", eval_false_count,
             " vignette line(s). Avoid disabling code evaluation — provide a ",
             "small dataset so all examples run during `R CMD build`."))
  }

  # sessionInfo
  has_session <- any(grepl("sessionInfo\\(|session_info\\(",
                           vignette_all_lines, perl = TRUE))
  if (!has_session) {
    vig_bullets[[length(vig_bullets)+1]] <- bullet("sessioninfo",
      "**[Required]** Include `sessionInfo()` at the end of each vignette.")
  }

  # GitHub install instructions
  has_gh_install <- any(grepl("install_github|BiocManager.*install",
                               vignette_all_lines, perl = TRUE))
  if (has_gh_install) {
    vig_bullets[[length(vig_bullets)+1]] <- bullet("install",
      "Remove GitHub/BiocManager installation instructions from vignettes ",
      "before submission. Users will install from Bioconductor.")
  }

  # Static images
  static_img <- any(grepl("knitr::include_graphics|!\\[.*\\]\\(",
                           vignette_all_lines, perl = TRUE))
  if (static_img) {
    vig_bullets[[length(vig_bullets)+1]] <- bullet("static_img",
      "Avoid embedding static images. Regenerate all figures from evaluated ",
      "R code within the vignette.")
  }

  # Long lines
  long_lines <- sum(nchar(vignette_all_lines) > 100)
  if (long_lines > 10) {
    vig_bullets[[length(vig_bullets)+1]] <- bullet("linelen",
      paste0(long_lines, " vignette lines exceed 100 characters. ",
             "Aim for ≤ 80 characters per line where practical."))
  }
}

if (length(vig_bullets) == 0) {
  vig_bullets[[1]] <- bullet("ok", "Looks good.")
}

# ---------------------------------------------------------------------------
# Section 4: R/ code review
# ---------------------------------------------------------------------------

r_bullets <- list()

check_r <- function(pattern, msg, ...) {
  hits <- grep_lines(pattern, r_all_lines, ...)
  if (length(hits) > 0) {
    r_bullets[[length(r_bullets)+1]] <<- bullet(msg,
      paste0(msg, " (`", head(trimws(hits), 1), "`...)"))
  }
}

# 1:n style
colon_seq <- grep("\\b1:[a-zA-Z_.(]|\\b1:length\\(",
                  r_all_lines, perl = TRUE, value = TRUE)
if (length(colon_seq) > 0) {
  r_bullets[[length(r_bullets)+1]] <- bullet("seq_len",
    paste0("Use `seq_len(n)` or `seq_along(x)` instead of `1:n` patterns. ",
           "Found ", length(colon_seq), " occurrence(s). Example: `",
           trimws(colon_seq[[1]]), "`."))
}

# sapply usage
sapply_hits <- grep("\\bsapply\\(", r_all_lines, perl = TRUE, value = TRUE)
if (length(sapply_hits) > 0) {
  r_bullets[[length(r_bullets)+1]] <- bullet("sapply",
    paste0("Replace `sapply()` with `vapply()` (", length(sapply_hits),
           " occurrence(s)). `vapply()` requires an explicit return type and ",
           "is safer and more predictable."))
}

# T/F usage
tf_hits <- grep("\\bT\\b|\\bF\\b", r_all_lines, perl = TRUE, value = TRUE)
# Filter out common false positives (e.g., variable names, comments)
tf_hits <- tf_hits[!grepl("^\\s*##|TRUE|FALSE|[A-Z]{2,}", tf_hits)]
if (length(tf_hits) > 3) {
  r_bullets[[length(r_bullets)+1]] <- bullet("TF",
    paste0("Use `TRUE`/`FALSE` instead of `T`/`F` (",
           length(tf_hits), " potential occurrence(s))."))
}

# browser() calls
browser_hits <- grep("\\bbrowser\\(\\)", r_all_lines, perl = TRUE, value = TRUE)
if (length(browser_hits) > 0) {
  r_bullets[[length(r_bullets)+1]] <- bullet("browser",
    paste0("**[Required]** Remove `browser()` calls before submission. ",
           "Found ", length(browser_hits), " occurrence(s)."))
}

# set.seed() in package code
seed_hits <- grep("\\bset\\.seed\\(", r_all_lines, perl = TRUE, value = TRUE)
if (length(seed_hits) > 0) {
  r_bullets[[length(r_bullets)+1]] <- bullet("set.seed",
    paste0("Avoid `set.seed()` in package functions (",
           length(seed_hits), " occurrence(s)). It modifies global R state."))
}

# eval(parse(...))
evalparse_hits <- grep("eval\\s*\\(.*parse\\s*\\(",
                       r_all_lines, perl = TRUE, value = TRUE)
if (length(evalparse_hits) > 0) {
  r_bullets[[length(r_bullets)+1]] <- bullet("evalparse",
    paste0("**[Required]** Avoid `eval(parse(...))` (",
           length(evalparse_hits), " occurrence(s)). ",
           "This is a security and maintainability risk."))
}

# Direct slot access @ outside accessor pattern
slot_access <- grep("@[a-zA-Z_]",
                    r_all_lines[!grepl("^\\s*#", r_all_lines)],
                    perl = TRUE, value = TRUE)
slot_access <- slot_access[!grepl("importMethodsFrom|ORCID|\\@.*\\<-|\"@|'@", slot_access)]
if (length(slot_access) > 5) {
  r_bullets[[length(r_bullets)+1]] <- bullet("slot_access",
    paste0("Direct slot access with `@` found in ", length(slot_access),
           " line(s). Define and use accessor functions; ",
           "use `@` only inside accessors."))
}

# <<- usage
arrow_global <- grep("<<-", r_all_lines, fixed = TRUE, value = TRUE)
if (length(arrow_global) > 0) {
  r_bullets[[length(r_bullets)+1]] <- bullet("global_assign",
    paste0("Avoid `<<-` for global assignment (",
           length(arrow_global), " occurrence(s)). ",
           "Use `<-` with appropriate scoping, or a package environment."))
}

# print/cat outside show methods
print_hits <- grep("^[^#]*\\b(cat|print)\\(",
                   r_all_lines, perl = TRUE, value = TRUE)
print_hits <- print_hits[!grepl("show|message|warning|stop", print_hits)]
if (length(print_hits) > 3) {
  r_bullets[[length(r_bullets)+1]] <- bullet("print",
    paste0("Found ", length(print_hits), " use(s) of `cat()` or `print()` ",
           "outside of `show()` methods. Use `message()` for diagnostic output."))
}

# library/require() inside functions — exclude comment lines and roxygen lines
lib_hits <- grep("\\blibrary\\(|\\brequire\\(",
                 r_all_lines, perl = TRUE, value = TRUE)
lib_hits <- lib_hits[!grepl("^\\s*#", lib_hits)]
if (length(lib_hits) > 0) {
  r_bullets[[length(r_bullets)+1]] <- bullet("library",
    paste0("**[Required]** Do not use `library()` or `require()` inside ",
           "package functions (",  length(lib_hits), " occurrence(s)). ",
           "Use `importFrom` in NAMESPACE or `requireNamespace()` with an ",
           "explicit error for `Suggests` dependencies."))
}

# system() usage
system_hits <- grep("\\bsystem\\([^2]|\\bsystem\\(\"",
                    r_all_lines, perl = TRUE, value = TRUE)
if (length(system_hits) > 0) {
  r_bullets[[length(r_bullets)+1]] <- bullet("system",
    paste0("Replace `system()` with `system2()` (",
           length(system_hits), " occurrence(s))."))
}

# Bioconductor class usage check (look for data.frame-centric design)
uses_se <- any(grepl("SummarizedExperiment|SingleCellExperiment|RangedSE",
                     r_all_lines, perl = TRUE))
uses_granges <- any(grepl("GRanges|GenomicRanges", r_all_lines, perl = TRUE))
uses_biostrings <- any(grepl("DNAStringSet|AAStringSet|Biostrings",
                              r_all_lines, perl = TRUE))
# Heuristic: if package uses a lot of data.frames but no Bioconductor classes,
# flag this
df_heavy <- sum(grepl("data\\.frame|data_frame|as\\.data\\.frame",
                      r_all_lines, perl = TRUE))
if (df_heavy > 20 && !uses_se && !uses_granges && !uses_biostrings) {
  r_bullets[[length(r_bullets)+1]] <- bullet("bioc_classes",
    paste0("The package makes heavy use of `data.frame` (",
           df_heavy, " occurrence(s)) but does not appear to use standard ",
           "Bioconductor classes (`SummarizedExperiment`, `GRanges`, etc.). ",
           "Consider whether the data could be represented using an existing ",
           "Bioconductor class to improve interoperability."))
}

# Long functions
long_fns <- character(0)
for (fname in names(r_src)) {
  lines <- r_src[[fname]]
  start_idx <- grep("<-\\s*function\\(|= function\\(", lines, perl = TRUE)
  for (start in start_idx) {
    fn_match <- regmatches(lines[[start]],
                           regexpr("[a-zA-Z._][a-zA-Z0-9._]*\\s*(<-|=)\\s*function",
                                   lines[[start]], perl = TRUE))
    end_search <- min(start + 200, length(lines))
    brace_count <- 0
    end_found <- start
    for (i in seq(start, end_search)) {
      brace_count <- brace_count + 
        nchar(gsub("[^{]", "", lines[[i]])) -
        nchar(gsub("[^}]", "", lines[[i]]))
      if (brace_count <= 0 && i > start) { end_found <- i; break }
    }
    fn_len <- end_found - start
    if (fn_len > 60) {
      long_fns <- c(long_fns, paste0(fname, ": ~", fn_len, " lines"))
    }
  }
}
if (length(long_fns) > 0) {
  r_bullets[[length(r_bullets)+1]] <- bullet("long_fns",
    paste0("Functions exceeding ~60 lines found (consider breaking these up): ",
           paste(head(long_fns, 5), collapse = "; "), "."))
}

if (length(r_bullets) == 0) {
  r_bullets[[1]] <- bullet("ok", "Looks good.")
}

# ---------------------------------------------------------------------------
# Section 5: Tests review
# ---------------------------------------------------------------------------

test_bullets <- list()

if (!has_tests) {
  test_bullets[[length(test_bullets)+1]] <- bullet("missing",
    "**[Required]** No `tests/` directory found. A unit test suite is required. ",
    "Use `testthat`, `tinytest`, or `RUnit`.") 
} else {
  test_files <- list.files(file.path(pkg_dir, "tests"),
                           pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
  test_lines <- unlist(lapply(test_files, function(f)
    tryCatch(readLines(f, warn = FALSE), error = function(e) character(0))))

  skip_bioc <- sum(grepl("skip_on_bioc\\(", test_lines, perl = TRUE))
  if (skip_bioc > 0) {
    test_bullets[[length(test_bullets)+1]] <- bullet("skip_bioc",
      paste0("Avoid `skip_on_bioc()` (",  skip_bioc,
             " occurrence(s)). Tests should pass on the Bioconductor build machines."))
  }

  if (!is.na(cov_pct)) {
    if (cov_pct < 20) {
      test_bullets[[length(test_bullets)+1]] <- bullet("coverage",
        paste0("**[Required]** Test coverage is very low at ",
               cov_pct, "%. The package is significantly under-tested. ",
               "Add tests for all exported functions."))
    } else if (cov_pct < 50) {
      test_bullets[[length(test_bullets)+1]] <- bullet("coverage",
        paste0("Test coverage is ", cov_pct,
               "%. Consider adding more tests, especially for exported ",
               "functions and edge cases."))
    } else if (cov_pct < 80) {
      test_bullets[[length(test_bullets)+1]] <- bullet("coverage",
        paste0("Test coverage is ", cov_pct,
               "%. There is room to improve coverage for exceptional paths ",
               "and less-tested functions."))
    } else {
      test_bullets[[length(test_bullets)+1]] <- bullet("coverage",
        paste0("Test coverage is ", cov_pct, "% — well done."))
    }
  }

  if (length(test_files) == 0) {
    test_bullets[[length(test_bullets)+1]] <- bullet("empty",
      "**[Required]** `tests/` directory is present but contains no `.R` files.")
  }
}

if (length(test_bullets) == 0) {
  test_bullets[[1]] <- bullet("ok", "Looks good.")
}

# ---------------------------------------------------------------------------
# Section 6: data/ review
# ---------------------------------------------------------------------------

data_bullets <- list()

if (has_data) {
  data_files <- list.files(file.path(pkg_dir, "data"), full.names = TRUE)
  data_size_mb <- sum(file.size(data_files), na.rm = TRUE) / 1e6
  if (data_size_mb > 5) {
    data_bullets[[length(data_bullets)+1]] <- bullet("data_size",
      paste0("Data files in `data/` total ~",
             round(data_size_mb, 1),
             " MB. Large datasets should be hosted on `ExperimentHub` or ",
             "`AnnotationHub` rather than bundled with the package."))
  }

  rda_files <- data_files[grepl("\\.rda$|\\.RData$|\\.rds$",
                                data_files, ignore.case = TRUE)]
  r_data_files <- list.files(file.path(pkg_dir, "R"),
                              pattern = "data\\.R$|data-doc|datasets",
                              full.names = TRUE)
  if (length(rda_files) > 0 && length(r_data_files) == 0) {
    data_bullets[[length(data_bullets)+1]] <- bullet("data_doc",
      "Bundled data objects should have documentation. Add a `.R` file with ",
      "`@docType data` (`roxygen2`) documentation for each dataset.")
  }
}

if (length(data_bullets) == 0 && has_data) {
  data_bullets[[1]] <- bullet("ok", "Looks good.")
}

# ---------------------------------------------------------------------------
# Section 7: man/ review
# ---------------------------------------------------------------------------

man_bullets <- list()

if (has_man) {
  rd_files  <- list.files(file.path(pkg_dir, "man"),
                           pattern = "\\.Rd$", full.names = TRUE)
  rd_src    <- lapply(rd_files, function(f)
    tryCatch(readLines(f, warn = FALSE), error = function(e) character(0)))
  rd_all    <- unlist(rd_src)

  # Missing \value sections
  no_value <- vapply(rd_src, function(lines) {
    has_usage  <- any(grepl("\\\\usage", lines))
    has_value  <- any(grepl("\\\\value", lines))
    has_usage && !has_value
  }, logical(1))
  if (sum(no_value) > 0) {
    files_no_val <- basename(rd_files)[no_value]
    man_bullets[[length(man_bullets)+1]] <- bullet("no_value",
      paste0("**[Required]** Missing `\\value` (return value) documentation in ",
             sum(no_value), " man page(s): ",
             paste(head(files_no_val, 5), collapse = ", "), "."))
  }

  # if(FALSE) in examples
  if_false <- grep_lines("if\\s*\\(\\s*FALSE\\s*\\)", rd_all)
  if (length(if_false) > 0) {
    man_bullets[[length(man_bullets)+1]] <- bullet("if_false",
      paste0("**[Required]** `if (FALSE)` found in examples (",
             length(if_false), " occurrence(s)). Examples must be runnable. ",
             "Use `\\donttest{}` for slow examples instead."))
  }
}

if (length(man_bullets) == 0) {
  man_bullets[[1]] <- bullet("ok", "Looks good.")
}

# ---------------------------------------------------------------------------
# Section 8: Artifact analysis
# ---------------------------------------------------------------------------

artifact_bullets <- list()

if (nzchar(check_txt)) {
  errors   <- grep_lines("^ERROR|ERROR:", strsplit(check_txt, "\n")[[1]])
  warnings <- grep_lines("WARNING", strsplit(check_txt, "\n")[[1]])
  notes    <- grep_lines("^NOTE|^\\* NOTE", strsplit(check_txt, "\n")[[1]])

  if (length(errors) > 0) {
    artifact_bullets[[length(artifact_bullets)+1]] <- bullet("errors",
      paste0("**[Required]** R CMD check produced ", length(errors),
             " ERROR(s) that must be resolved:\n  - ",
             paste(trimws(head(errors, 5)), collapse = "\n  - ")))
  }
  if (length(warnings) > 0) {
    artifact_bullets[[length(artifact_bullets)+1]] <- bullet("warnings",
      paste0("R CMD check produced ", length(warnings),
             " WARNING(s) that should be resolved:\n  - ",
             paste(trimws(head(warnings, 5)), collapse = "\n  - ")))
  }
  if (length(notes) > 0) {
    artifact_bullets[[length(artifact_bullets)+1]] <- bullet("notes",
      paste0("R CMD check produced ", length(notes), " NOTE(s):\n  - ",
             paste(trimws(head(notes, 5)), collapse = "\n  - ")))
  }
}

if (nzchar(bioccheck_txt)) {
  bc_lines  <- strsplit(bioccheck_txt, "\n")[[1]]
  bc_req    <- grep_lines("ERROR|\\[required\\]", bc_lines, ignore.case = TRUE)
  bc_rec    <- grep_lines("WARNING|\\[recommended\\]", bc_lines, ignore.case = TRUE)
  bc_cons   <- grep_lines("NOTE|\\[consider\\]", bc_lines, ignore.case = TRUE)

  if (length(bc_req) > 0) {
    artifact_bullets[[length(artifact_bullets)+1]] <- bullet("bioccheck_req",
      paste0("**[Required]** BiocCheck errors/required items (",
             length(bc_req), "):\n  - ",
             paste(trimws(head(bc_req, 5)), collapse = "\n  - ")))
  }
  if (length(bc_rec) > 0) {
    artifact_bullets[[length(artifact_bullets)+1]] <- bullet("bioccheck_rec",
      paste0("BiocCheck recommended items (", length(bc_rec), ") — please address:\n  - ",
             paste(trimws(head(bc_rec, 5)), collapse = "\n  - ")))
  }
  if (length(bc_cons) > 0) {
    artifact_bullets[[length(artifact_bullets)+1]] <- bullet("bioccheck_cons",
      paste0("BiocCheck considerations (", length(bc_cons), "):\n  - ",
             paste(trimws(head(bc_cons, 5)), collapse = "\n  - ")))
  }
}

if (length(artifact_bullets) == 0) {
  if (nzchar(check_txt) || nzchar(bioccheck_txt)) {
    artifact_bullets[[1]] <- bullet("ok",
      "No ERRORs or WARNINGs found in R CMD check / BiocCheck output.")
  }
}

# ---------------------------------------------------------------------------
# Assemble final review
# ---------------------------------------------------------------------------

repo_url <- "https://github.com/LiNk-NY/BiocReviews"
readme_url <- paste0(repo_url, "#readme")
review_date <- format(Sys.Date(), "%Y-%m-%d")

footer <- paste0(
  "---\n\n",
  "*Review performed by **", model_name, "** on ", review_date, ".  \n",
  "Guidelines and more information: [", repo_url, "](", readme_url, ")*"
)

sections <- paste(c(
  paste0("# ", pkg_name),
  "",
  render_section("DESCRIPTION", desc_bullets),
  render_section("NAMESPACE", ns_bullets),
  render_section("vignettes/", vig_bullets),
  render_section("R/", r_bullets),
  render_section("tests/", test_bullets),
  if (has_data) render_section("data/", data_bullets) else NULL,
  render_section("man/", man_bullets),
  if (length(artifact_bullets) > 0) render_section("Build Artifacts", artifact_bullets) else NULL,
  footer
), collapse = "\n")

# ---------------------------------------------------------------------------
# Write output
# ---------------------------------------------------------------------------

if (nzchar(output_file)) {
  writeLines(sections, output_file)
  message("Review written to: ", output_file)
} else {
  cat(sections, "\n")
}
