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

#### Submission issue format (required)

Open submissions using the issue template in
`.github/ISSUE_TEMPLATE/issue_template.md`.

The workflow parser expects this line in the issue body:

```
Repository: https://github.com/owner/repo
```

Optional field:

```
Branch/Ref: devel
```

After confirming the issue is complete and correctly formatted, a **repository
collaborator** should add the **`AI review`** label to initiate the build/check
workflow.

To rerun the workflow chain later, a collaborator can post an `@biocreview`
comment. If needed, include a `Remotes:` line in the same comment (see below).

#### Option 1 — Automated (full build + review)

Add the label **`AI review`** to a package submission issue. This triggers the
`build-check.yml` workflow which runs R CMD check, BiocCheck, and coverage, then
uploads artifacts and posts a build/check summary comment.

After `build-check.yml` completes, `auto-review.yml` is triggered
and generates/posts the structured automated review using those artifacts.

#### Option 2 — Rerun from issue comment

Comment `@biocreview` on an existing issue to trigger the
workflow chain again. The comment re-runs `build-check.yml`, and then
`auto-review.yml` runs from the resulting artifacts. Alternatively, trigger
`auto-review.yml` manually from the
[Actions tab](../../actions/workflows/auto-review.yml) and supply the
`owner/repo` and optional issue number.

#### Installing co-dependent packages

If the package being reviewed depends on **another package that is also under
simultaneous review** (i.e., not yet on Bioconductor or CRAN), include a
`Remotes:` line in the same `@biocreview` rerun comment so those packages are
pre-installed during the build/check workflow:

```
@biocreview
Remotes: waldronlab/imageTCGAutils
```

Multiple co-dependent packages can be comma-separated:

```
@biocreview
Remotes: waldronlab/imageTCGAutils, waldronlab/anotherPkg
```

This is primarily intended for co-dependent simultaneous submissions.

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
    build-check.yml        Build/check workflow with artifact output
    auto-review.yml        Review-generation workflow (artifact-driven + fallback)
  ISSUE_TEMPLATE/
    issue_template.md      Submission template (includes automation fields)
    config.yml             Issue template routing
buildcheck.sh              Legacy local build/check helper
clonevim.sh                Clone a package and prepare review file
```
