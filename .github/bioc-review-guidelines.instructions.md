---
applyTo: "**"
---

# Bioconductor Package Review Guidelines

These guidelines formalize the criteria used to review Bioconductor package submissions.
They are based on the official Bioconductor contribution documentation at
https://contributions.bioconductor.org and distilled from the review history in
this repository. Edit this file to adjust reviewer expectations.

---

## Review Output Format

Write reviews as Markdown. Structure them exactly as follows:

```
# {PackageName}

{Optional 1-3 sentence summary of the package and overall impression.}

## DESCRIPTION
...

## NAMESPACE
...

## vignettes/
...

## R/
...

## tests/
...

## data/ (if present)
...

## man/ (if issues found)
...

## Package Structure (if issues found)
...
```

- Use bullet points (`*`) for individual review items.
- Flag **Required** changes (must fix before acceptance) vs **Suggestions** (recommended but optional).
- Prefix required items with `* **[Required]**` and suggestions with `* **[Suggestion]**`.
- Be specific: include file names, function names, and line numbers where applicable.
- Include short code examples to illustrate better patterns.
- Keep tone professional, constructive, and encouraging.
- If a section has no issues, write `* Looks good.`

---

## 1. DESCRIPTION File

### Required Checks
- **Package name**: Must match the repository name exactly, including case.
- **Version**: Must be `0.99.0` for first submission. Scheme is `x.y.z` (odd `y` = devel, even `y` = release).
- **Title**: Brief, descriptive, title-case, without a trailing period.
- **Description**: At least three complete sentences providing a detailed overview of functionality.
- **Authors@R**: Must use this field (not `Author:`/`Maintainer:`). Exactly one person with `role = "cre"` and an actively maintained email address.
- **ORCiD**: Include ORCiD for at least the maintainer via `comment = c(ORCID = "XXXX-XXXX-XXXX-XXXX")`.
- **License**: Must be an open-source license compatible with redistribution. Non-commercial licenses (e.g., `CC BY-NC 4.0`, `ACM`) are NOT allowed. Typical choices: `Artistic-2.0`, `GPL-2`, `GPL-3`, `MIT + file LICENSE`.
- **biocViews**: Required field. At least two leaf-node terms from https://bioconductor.org/packages/devel/BiocViews.html. All terms must come from the same trunk (`Software`, `AnnotationData`, `ExperimentData`, or `Workflow`). Field name is case-sensitive (`biocViews`).
- **Dependencies**: All dependencies must be available on Bioconductor or CRAN. The `Remotes:` field is NOT supported and will cause rejection. Do not specify version constraints on individual packages.
- **Dependencies**: All dependencies must be available on Bioconductor or CRAN. The `Remotes:` field is NOT supported in the final submission and will cause rejection. Do not specify version constraints on individual packages.
  > **Co-dependent simultaneous submissions**: When a package under review
  > depends on another package being submitted to Bioconductor at the same
  > time (not yet on CRAN/Bioconductor), the reviewer should pre-install the
  > dependency using the `Remotes:` line in the `@biocreview` comment (see
  > README). The `Remotes:` field in DESCRIPTION is still flagged as a
  > required fix before acceptance.
- **Dependency classification**:
  - `Imports:` – packages whose functions are used inside package code.
  - `Depends:` – packages providing essential user-facing functionality (rarely more than 3).
  - `Suggests:` – packages used only in vignettes, examples, or conditional code.
  - `Enhances:` – packages that enhance performance but are not required.
  - A package must appear in exactly one of these fields.

### Suggestions
- **BugReports**: Include a link to the GitHub issue tracker.
- **URL**: Include links to source repository and additional resources.
- **LazyData**: Do not set `LazyData: TRUE` for packages with large data, as it slows loading.
- **BiocType**: Required if submitting a Docker image or Workflow package.

---

## 2. NAMESPACE File

### Required Checks
- **Imports**: Import all symbols used from external packages (except base-package functions). Use `importFrom(pkg, fun)` or `import(pkg)`. Every package in `Imports:` in DESCRIPTION should have a corresponding `importFrom` or `import` declaration.
- **Exports**: Export all user-facing functions. Do not export internal helper functions (prefix internal functions with `.`).
- **S4**: Use `exportMethods()` for S4 methods and `exportClasses()` for S4 classes.

### Suggestions
- Prefer explicit `importFrom` over `import(wholePackage)` to keep the namespace minimal.
- Avoid importing a package just for one rarely used function; use `pkg::fun()` instead.

---

## 3. Vignettes

### Required Checks
- **Format**: Use `Rmd` (RMarkdown) or `Rnw` (Sweave). Must be buildable from source.
- **Evaluated code**: Avoid `eval=FALSE` chunk options. Provide a small, self-contained dataset so all code evaluates during `R CMD build`.
- **sessionInfo**: Must include `sessionInfo()` (or `sessioninfo::session_info()`) at the end of each vignette.
- **Static images**: Do not embed static images generated outside the vignette. Use evaluated R code to regenerate all figures.
- **Pre-computed results**: Do not paste pre-computed output. All results should be reproduced during build.
- **Line width**: Keep lines ≤ 80 characters where possible.
- **GitHub installation section**: Remove any `BiocManager::install()` or `devtools::install_github()` instructions from vignettes before acceptance (users will install from Bioconductor).

### Suggestions
- Include `package: {PackageName}` in the YAML front matter.
- Break large vignettes into multiple smaller vignettes organized by functionality.
- Provide clear section headings.
- Show a complete a realistic workflow from data import to result.

---

## 4. R/ Code

### Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Functions | `camelCase` | `computeScore()` |
| Variables | `camelCase` | `sampleData` |
| Classes (S4) | `UpperCamelCase` | `GeneExpressionSet` |
| Internal functions | prefix `.` | `.helperFn()` |
| File names | `.R` extension | `methods-coverage.R` |
| S4 class files | `AllClasses.R` | |
| S4 generic files | `AllGenerics.R` | |
| S4 method files | `methods-{generic}.R` | `methods-show.R` |

- **Do not** use `.` in function names (conflicts with S3 dispatch).
- **Do not** use capitalization patterns that imply qualitative/temporal hierarchy (e.g., `MyPackage2`, `MyPackagePlus`).

### Required Code Practices

**Vectorization & Iteration**
- Use `vapply()` instead of `sapply()` (explicit return type, safer).
- Use `lapply()` over `for` loops for building lists.
- Use `seq_len(n)` or `seq_along(x)` instead of `1:n` or `1:length(x)` (fails when `n == 0`).
- Pre-allocate result containers; never use copy-and-append patterns in loops.

**Logic & Syntax**
- Use `TRUE`/`FALSE`, not `T`/`F`.
- Use `is()` for type checking, not `class() ==` or `class() !=`.
- Use `<-` for assignment (not `=` outside function arguments).
- Use `identical()` or `all.equal()` for equality checks, not `==` on complex objects.
- Avoid `<<-` (global assignment).
- Avoid `eval(parse(...))`.
- Avoid `set.seed()` in package code.
- Avoid `browser()` in package code (debug artifact).
- Avoid unused `rm()` and `gc()` calls (R's garbage collector handles this).

**Messages & Errors**
- Use `message()` for informational output (not `cat()` or `print()`).
- Use `warning()` for unusual but handled conditions.
- Use `stop()` for unrecoverable errors.
- Use `cat()` and `print()` only in custom `show()` methods.

**S4 Classes**
- Prefer S4 over S3.
- Provide a constructor function (plain function, not a generic/method) for each class.
- Implement a `show()` method for each class.
- Create and use accessor functions; avoid direct slot access with `@` outside accessors.
- Only define methods for classes exported within your own package — avoid defining methods on classes from external packages.
- Use `setGeneric()` directly (do not conditionally define generics).
- When creating a new generic, provide the full argument list matching the method signature.
- Use `setAs()` (with the `as()` mechanism) for coercion rather than custom `as.ClassName()` functions.

**Function Argument Design**
- Provide default values for all function arguments where sensible.
- Validate arguments using `stopifnot()` or explicit checks; emit informative error messages.
- Use descriptive argument names — avoid single-letter or cryptic names (`x`, `k`, `y`) in exported functions.

**Conditionals & Complexity**
- Simplify redundant logic: `sum(logicalVec)` equals `sum(ifelse(logicalVec, 1, 0))`.
- Reduce cyclomatic complexity by extracting nested logic into helper functions.
- Keep individual functions short (ideally fitting on one screen). If a function exceeds ~50 lines, consider breaking it up.

**Dependencies & System Calls**
- Do NOT auto-install packages for users anywhere in package code.
- Use `requireNamespace("pkg", quietly = TRUE)` checks for optional functionality in `Suggests`.
  ```r
  if (!requireNamespace("pkg", quietly = TRUE))
      stop("Install 'pkg' to use this function.")
  pkg::fun()
  ```
- Do not use `library()` or `require()` inside package functions; use `pkg::fun()` or `importFrom`.
- Use `system2()` instead of `system()` for external calls. Prefer existing R/Bioc packages over shell commands.
- Do not hard-code file paths outside of `tempdir()` / `BiocFileCache`.

**File Caching & Web Access**
- Use `BiocFileCache` for downloaded files that should persist.
- Alternatively use `tools::R_user_dir(package, which = "cache")` for custom cache directories.
- Use `tempdir()` / `tempfile()` for non-persistent intermediate files.
- Never write to the user's home directory, working directory, or package installation directory.
- Do not use `x11()` or `X11()` for graphics; use `dev.new()`.

**Parallelism**
- Use `BiocParallel` for parallel computation.
- Default to 1 or 2 workers; let users override via `BiocParallel::register()`.

**Bioconductor Class Integration (HIGH PRIORITY)**
- Reviewers are strict about this. Reuse standard Bioconductor classes:
  - Expression data: `SummarizedExperiment`, `SingleCellExperiment`
  - Genomic ranges: `GenomicRanges::GRanges`, `GenomicRanges::GRangesList`
  - Sequences: `Biostrings::DNAStringSet`, `Biostrings::AAStringSet`
  - Annotations: `AnnotationDbi`, `TxDb` objects
  - Files: Inherit from `BiocIO::BiocFile`
- Do not re-implement import/export methods for file formats already handled by Bioconductor packages (e.g., BAM via `Rsamtools`, GFF via `rtracklayer`, VCF via `VariantAnnotation`).
- Re-use generics from `BiocGenerics` when the method contract aligns (e.g., `rowSums`, `colSums`, `counts`).

### Coding Style (Suggestions)
- Indent with 4 spaces (no tabs).
- Maximum 80 characters per line.
- Space after commas: `a, b, c`.
- No space around `=` in function arguments: `fun(a=1, b=2)`.
- Space around binary operators: `a == b`, `x <- 5`.
- Use `##` for full-line comments.
- Remove commented-out code that is not used.
- Remove TODO comments before submission.
- Avoid nesting helper functions inside other functions; place them at the end of the file or in a separate `utils.R`/`helpers.R`.

---

## 5. Tests

### Required Checks
- A test suite must be present using one of: `testthat`, `tinytest`, or `RUnit`.
- Tests must be runnable via `R CMD check` (place in `tests/` directory with correct structure).
- Do not use `skip_on_bioc()` broadly; tests should pass on the Bioconductor build machines.
- Tests must cover the main exported functions.

### Suggestions
- Aim for meaningful coverage of code paths, especially edge cases (0-length inputs, NAs, boundary values).
- Higher coverage is better; target ≥ 80% where achievable.
- Prefer `testthat` for new packages (active development, widely used).
- Test that invalid inputs produce informative errors (using `expect_error()` / `checkException()`).

---

## 6. data/ and inst/extdata/

### Required Checks
- Bundled data must be necessary for examples and tests — do not include data just for convenience.
- Data in `data/` must have corresponding documentation in `man/` (`.Rd` files generated by `@docType data` roxygen tags).
- Do not store large files in `data/` or `inst/extdata/` — use `ExperimentHub` or `AnnotationHub` for large datasets.
- Do not duplicate data already available in Bioconductor packages or `AnnotationHub`/`ExperimentHub`.

### Suggestions
- Keep example datasets minimal (just enough rows/features to demonstrate functionality).
- Prefer `ExperimentHub` for data packages with large datasets.

---

## 7. man/ (Documentation)

### Required Checks
- Every exported function, class, method, and data object must have a `.Rd` documentation file.
- `@return` (Value section): Describe the return value for all functions that return something. This is checked by `BiocCheck`.
- `@examples`: Include runnable examples for all exported functions. Do not use `if (FALSE)` to wrap examples.
- `@param`: Document all arguments.

### Suggestions
- Document parameter types and acceptable values.
- Cross-reference related functions with `\seealso{}`.
- Describe the class slots in S4 class documentation.

---

## 8. Package Structure

### Required Checks
- Package must be installable from source via `R CMD INSTALL`.
- No `.git/objects/pack` large files (use BFG Repo Cleaner to remove from history if present).
- Source code files should not be committed that do not belong to the R package (e.g., no large binary files, data dumps, IDE config files).
- All file paths in code must be portable (use `file.path()`, not hardcoded `/` or `\\` separators).
- `inst/` subdirectory contents:
  - `inst/extdata/` for small data files used in examples/tests.
  - `inst/scripts/` for scripts used to generate data.
  - `inst/unitTests/` for RUnit test files.
  - Move development scripts (e.g., `dev/`) to `inst/` or a separate repository.
- Root-level non-standard files (e.g., `tissue_label.csv`) should be moved into `inst/extdata/`.

### Suggestions
- Include a `NEWS.md` or `NEWS` file documenting changes between versions.
- Include a `README.md` linking to the Bioconductor landing page, vignette, and installation instructions.
- Keep the package focused on one coherent set of functionality. If two distinct purposes exist (e.g., analysis + Shiny UI), consider splitting into two packages.
- Graphing/visualization functionality that is heavy can be separated into a companion package.

---

## 9. Interpreting Workflow Artifacts

When artifacts from the `build-check.yml` workflow are available, interpret them as follows:

### R CMD Check (`check_results.txt`)
- **ERRORs**: Must be fixed before acceptance. Flag each with `[Required]`.
- **WARNINGs**: Must be investigated and resolved. Almost always require fixing.
- **NOTEs**: Some are informational (e.g., "New submission"), but most should be addressed. Comment on each NOTE.
  - `no visible binding for global variable` → use `utils::globalVariables()` or restructure code.
  - Documentation-related NOTEs → add missing documentation.
  - Dependency NOTEs → review DESCRIPTION classification.

### BiocCheck (`bioccheck_results.txt`)
- **Required**: Must be addressed before acceptance.
- **Recommended**: Should be addressed; comment on any not addressed.
- **Considerations**: Optional but worth noting in the review.
- Common BiocCheck items to highlight:
  - T/F used instead of TRUE/FALSE
  - `1:n` style iterations
  - `sapply` usage
  - Functions longer than 50 lines (cyclomatic complexity)
  - Missing `sessionInfo()` in vignettes
  - Missing value/return documentation

### Test Coverage (`coverage.json` / `coverage_summary.txt`)
- Coverage < 20%: Flag as **Required** — package is under-tested.
- Coverage 20–50%: Flag as **Suggestion** — more tests recommended.
- Coverage 50–80%: Note the current level and areas that could benefit from more tests.
- Coverage > 80%: Mention positively.
- Always identify specific untested exported functions by name.

---

## 10. Review Tone and Language

- Be professional, specific, and constructive.
- Always explain *why* a change is needed (e.g., "Use `seq_len(n)` instead of `1:n` to safely handle the edge case when `n` is 0.").
- Provide brief code examples for non-obvious suggestions.
- Acknowledge good practices when you see them.
- Avoid vague comments like "improve this" — always suggest the concrete change.
- If a section is well-implemented, state `* Looks good.` rather than omitting the section.
