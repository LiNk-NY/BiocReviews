# BiocReviews

Repository for Bioconductor package reviews, including a collection of human
reviews (`packages/`) and an AI-assisted review system.

---

## AI-Assisted Review System

The AI review assistant uses a **two-stage pipeline**:

1. **Static analysis (`generate_review.R`)** — rule-based checks on R CMD check
   output, BiocCheck results, and test coverage produce a structured markdown
   review (`automated_review.md`). No external API is needed.

2. **LLM enhancement (`scripts/enhance_review_with_github_models.R`)** — the
   static review plus raw artifact context are sent to a GitHub Models LLM
   (default: `meta-llama-3.1-405b-instruct`) via the GitHub Models API. The LLM
   re-organises findings, prioritises required fixes, and returns a polished
   review (`automated_review_llm.md`). The review guidelines file
   (`.github/bioc-review-guidelines.instructions.md`) is prepended to the prompt
   so the model follows Bioconductor-specific expectations.

   If the combined prompt exceeds the configured character limit
   (`MAX_PROMPT_CHARS`, default 120 000), the prompt is hard-truncated and a
   visible warning block is inserted at the top of the output and in the issue
   comment. The `REVIEW_MAX_TOKENS` env var (default 2 800) controls the maximum
   length of the LLM response. Both values can be overridden in the workflow
   dispatch inputs or locally via environment variables.

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

**Option A2: Add LLM enhancement to a completed static review**

After Option A (or any method that produced `automated_review.md`), run the
enhancement script to produce `automated_review_llm.md`:

```bash
export GITHUB_TOKEN=$(gh auth token)
./scripts/enhance_review_with_github_models.sh [base_review] [output] [artifacts_dir]
```

Arguments default to `automated_review.md`, `automated_review_llm.md`, and the
current directory. Override model or limits via environment variables:

```bash
export GITHUB_MODEL=gpt-4o
export MAX_PROMPT_CHARS=80000
export REVIEW_MAX_TOKENS=3500
export GUIDELINES_FILE=.github/bioc-review-guidelines.instructions.md  # default
./scripts/enhance_review_with_github_models.sh
```

Or call the R script directly for full control:

```bash
Rscript scripts/enhance_review_with_github_models.R \
  --base-review automated_review.md \
  --output automated_review_llm.md \
  --check-file check_results.txt \
  --bioccheck-file bioccheck_results.txt \
  --coverage-file coverage.json \
  --guidelines-file .github/bioc-review-guidelines.instructions.md \
  --model meta-llama-3.1-405b-instruct \
  --max-prompt-chars 120000 \
  --max-tokens 2800
```

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

**Method 5: LLM Model Testing**

Test different LLM models from multiple providers locally (not through GH Actions) for generating reviews:

```bash
# AWS Bedrock - Claude models (recommended)
./scripts/quick_llm_test.sh recommended ~/reviews/MyPackage

# OpenAI - GPT models
export OPENAI_API_KEY="sk-..."
export OPENAI_MODELS="gpt-4o gpt-4o-mini"
./scripts/test_llm_models.sh ~/reviews/MyPackage openai_output/

# GitHub Models - Free tier (GPT-4o, Llama, etc.)
export GITHUB_TOKEN=$(gh auth token)
export GITHUB_MODELS="gpt-4o meta-llama-3.1-405b-instruct"
./scripts/test_llm_models.sh ~/reviews/MyPackage github_output/
```

**Supported providers:**
- **AWS Bedrock** - Claude (Sonnet, Opus, Haiku), Mistral, Llama, Titan
- **OpenAI** - GPT-4o, GPT-4 Turbo, GPT-3.5
- **GitHub Models** - GPT-4o, Llama 3.1, Mistral, Cohere (free tier available)

The base review is generated using rule-based static analysis, then each LLM model
generates an enhanced review using the static analysis as context. Results include
a comparison summary for evaluating model quality.

**See [docs/LLM_TESTING.md](docs/LLM_TESTING.md) for detailed guide and [docs/MODEL_PROVIDERS.md](docs/MODEL_PROVIDERS.md) for provider setup.**

---

**Dependencies:** `rcmdcheck` (required), `BiocCheck`, `covr`, `jsonlite` (optional).

For LLM testing:
- `jq` (required for all providers)
- AWS CLI + Bedrock access (for AWS Bedrock models)
- `OPENAI_API_KEY` (for OpenAI models)
- `GITHUB_TOKEN` (for GitHub Models - free tier available)

---

### Repository Structure

```
packages/                  Human reviews (one .txt per package)
responses/                 Author responses to review comments
generate_review.R          Core review generator (rule-based static analysis)
scripts/
  generate_local_review.sh          Wrapper: run checks then call generate_review.R
  enhance_review_with_github_models.R   LLM enhancement CLI (GitHub Models API)
  enhance_review_with_github_models.sh  Local convenience wrapper for the R script
  test_llm_models.sh       Test multiple LLM models for review generation
  quick_llm_test.sh        Quick wrapper for testing model sets
  llm_model_config.sh      Configuration for LLM model sets
docs/
  LLM_TESTING.md           Comprehensive guide for LLM model testing
  MODEL_PROVIDERS.md       LLM provider setup and configuration guide
.github/
  bioc-review-guidelines.instructions.md   AI review assistant guidelines (fed to LLM)
  workflows/
    build-check.yml        Full CI pipeline: R CMD check, BiocCheck, coverage
    auto-review.yml        Two-stage review: static analysis + LLM enhancement
  ISSUE_TEMPLATE/
    issue_template.md      Submission template with activation instructions
    config.yml             Issue template routing configuration
buildcheck.sh              Legacy local build/check helper
clonevim.sh                Clone a package and prepare review file
```
