# BiocReviews

Repository for Bioconductor package reviews, including a collection of human
reviews (`packages/`) and an AI-assisted review system.

---

## AI-Assisted Review System

The AI review assistant analyzes a package's source code together with artifacts
from R CMD check, BiocCheck, and test coverage to generate a structured review
following [Bioconductor contribution guidelines](https://contributions.bioconductor.org).

These reviews are preliminary assessments that assist human reviewers in the
final evaluation process.

### Review Guidelines

The guidelines used by the AI review assistant are documented and maintained in
[`.github/bioc-review-guidelines.instructions.md`](.github/bioc-review-guidelines.instructions.md).
Edit that file to adjust the assistant's expectations (new rules, exceptions, etc.).

---

### Running a Review

#### Submission Issue Format

Open submissions using the issue template in
`.github/ISSUE_TEMPLATE/issue_template.md`.

**Required field in issue body:**
```
Repository: https://github.com/owner/repo
```

**Optional field:**
```
Branch/Ref: devel
```

---

#### Triggering Methods

**Method 1: Initial Review Trigger (AI Review Assistant Activation)**

A **repository collaborator** adds the **`AI review`** label to a package submission
issue. This initiates:

1. `build-check.yml` runs R CMD check, BiocCheck, and test coverage
2. Artifacts are uploaded and a build/check summary is posted to the issue
3. `auto-review.yml` automatically triggers and generates the structured review

**Note:** Co-dependent remotes are NOT supported on initial runs. Use Method 2
to rerun with remotes.

---

**Method 2: Rerun with Co-dependent Packages**

Comment `@biocreview` on an existing issue to rerun the full workflow chain:

```
@biocreview
Remotes: waldronlab/imageTCGAutils, waldronlab/anotherPkg
```

- The `Remotes:` line is **optional** and only needed when the package depends on
  other GitHub packages not yet on Bioconductor/CRAN
- Multiple remotes can be comma-separated
- This reruns both `build-check.yml` and `auto-review.yml` with artifacts
- **Important:** Remotes can ONLY be specified via `@biocreview` comments,
  NOT on initial runs or in the issue body

---

**Method 3: Manual Review-Only Trigger**

Trigger `auto-review.yml` manually from the
[Actions tab](../../actions/workflows/auto-review.yml) using workflow_dispatch:

- Supply the `owner/repo` and optional issue number
- Generates review without running build/check
- Useful for re-reviewing after code changes without full CI rerun

---

**Method 4: Local Review

**Option A: Complete workflow (recommended)**

Use the wrapper script to run all checks and generate the review in one command:

```bash
# Review a local package and write to a file:
./scripts/generate_local_review.sh ~/reviews/MyPackage MyPackage_review.md

# Review and print to stdout:
./scripts/generate_local_review.sh ~/reviews/MyPackage
```

This script runs R CMD check, BiocCheck, test coverage, then calls `generate_review.R`
with the results.

**Option B: Review from existing check results**

If you've already run checks separately, call the R script directly:

```bash
Rscript generate_review.R \
    /path/to/package \
    check_results.txt \
    bioccheck_results.txt \
    coverage.json \
    output_review.md
```

This is useful when reusing check artifacts or integrating into custom workflows.

---

**Dependencies:** `rcmdcheck` (required), `BiocCheck`, `covr`, `jsonlite` (optional).

---

### Repository Structure

```
packages/                  Human reviews (one .txt per package)
responses/                 Author responses to review comments
generate_review.R          Core review generator (takes check artifacts as input)
scripts/
  generate_local_review.sh Wrapper script (runs checks, then calls generate_review.R)
.github/
  bioc-review-guidelines.instructions.md   AI review assistant guidelines
  workflows/
    build-check.yml        Full CI pipeline: R CMD check, BiocCheck, coverage
    auto-review.yml        AI review assistant workflow (artifact-driven)
  ISSUE_TEMPLATE/
    issue_template.md      Submission template with activation instructions
    config.yml             Issue template routing configuration
buildcheck.sh              Legacy local build/check helper
clonevim.sh                Clone a package and prepare review file
```
