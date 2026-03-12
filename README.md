# BiocReviews

Repository for Bioconductor package reviews, including a collection of human
reviews (`packages/`) and an automated review system.

---

## Automated Review System

The automated reviewer analyzes a package's source code together with artifacts
from R CMD check, BiocCheck, and test coverage to generate a structured review
following [Bioconductor contribution guidelines](https://contributions.bioconductor.org).

### Review Guidelines

The guidelines used by the automated reviewer are documented and maintained in
[`.github/bioc-review-guidelines.instructions.md`](.github/bioc-review-guidelines.instructions.md).
Edit that file to adjust reviewer expectations (new rules, exceptions, etc.).

---

### Running a Review

#### Option 1 — Automated (full build + review)

Add the label **`AI review`** to a package submission issue. This triggers the
`build-check.yml` workflow which runs R CMD check, BiocCheck, coverage, and
then posts the review as a comment on the issue.

#### Option 2 — Review only (no build)

Comment `@biocreview` on an existing issue to trigger only the
`auto-review.yml` workflow. This clones the package, runs all checks, and posts
the review. Alternatively, trigger it manually from the
[Actions tab](../../actions/workflows/auto-review.yml) and supply the
`owner/repo` and optional issue number.

If the package being reviewed depends on **another package that is also under
simultaneous review** (i.e., not yet on Bioconductor or CRAN), include a
`Remotes:` line in the same comment to pre-install those packages from GitHub
before the review runs:

```
@biocreview
Remotes: waldronlab/imageTCGAutils
```

Multiple co-dependent packages can be comma-separated:

```
@biocreview
Remotes: waldronlab/imageTCGAutils, waldronlab/anotherPkg
```

When using the **Actions tab** (manual trigger), supply the same comma-separated
list in the `remotes` input field.

#### Option 3 — Local

```bash
# Review a local package checkout and write to a file:
./scripts/generate_local_review.sh ~/reviews/MyPackage 1234 MyPackage_review.md

# Review and print to stdout:
./scripts/generate_local_review.sh ~/reviews/MyPackage

# Call the R script directly (e.g., after running build/check separately):
Rscript generate_review.R \
    /path/to/package \
    check_results.txt \
    bioccheck_results.txt \
    coverage.json \
    1234 \
    output_review.md
```

`1234` above is an **example GitHub issue number**. Replace it with the real
issue ID when posting back to an issue, or omit it for purely local review use.

**Dependencies for local use:** `rcmdcheck`, `BiocCheck`, `covr`, `jsonlite`
(all optional except `rcmdcheck`).

---

### Repository Structure

```
packages/                  Human reviews (one .txt per package)
responses/                 Author responses to review comments
generate_review.R          Core review generation script
scripts/
  generate_local_review.sh Local wrapper (runs checks + review)
.github/
  bioc-review-guidelines.instructions.md   Editable review guidelines
  workflows/
    build-check.yml        Full build + check + review workflow
    auto-review.yml        Review-only standalone workflow
buildcheck.sh              Legacy local build/check helper
clonevim.sh                Clone a package and prepare review file
```
