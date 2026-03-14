# LLM Setup Guide

BiocReviews supports two LLM providers for automated code review: **GitHub Models** (GPT-4o) and **Google Gemini** (gemini-3.1-pro-preview).

## Supported Models

| Provider | Model | API Key Secret | Usage |
|----------|-------|----------------|-------|
| **GitHub Models** | `gpt-4o` (default) | `MODELS_TOKEN` | `@biocreview` or `@biocreview gpt-4o` |
| **Google Gemini** | `gemini-3.1-pro-preview` | `GEMINI_API_KEY` | `@biocreview gemini-3.1-pro-preview` |

## Quick Setup

### Option 1: GitHub Models (GPT-4o)

1. **Create a fine-grained Personal Access Token**:
   - Go to [GitHub Settings > Personal Access Tokens](https://github.com/settings/personal-access-tokens/new)
   - Grant **Models** permission (under "Account permissions")
   - Generate token (starts with `github_pat_...`)

2. **Add as repository secret**:
   - Navigate to **Settings > Secrets and variables > Actions**
   - Create secret: `MODELS_TOKEN` = your PAT

3. **Trigger a review**: Comment `@biocreview` on an issue

See [GitHub's documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token) for more details on PATs.

### Option 2: Google Gemini

1. **Get a Gemini API key**:
   - Visit [Google AI Studio](https://aistudio.google.com/app/api-keys)
   - Create a new API key

2. **Add as repository secret**:
   - Navigate to **Settings > Secrets and variables > Actions**
   - Create secret: `GEMINI_API_KEY` = your API key

3. **Trigger a review**: Comment `@biocreview gemini-3.1-pro-preview` on an issue

See [Google's documentation](https://ai.google.dev/gemini-api/docs/api-key) for more details on Gemini API keys.

## Troubleshooting

### LLM enhancement failed

**Symptoms**: Warning in workflow logs, review falls back to rule-based analysis only.

**Common causes**:
- Missing or expired API key/token
- Token missing required permissions (GitHub Models requires **Models** scope)
- Rate limits exceeded
- Invalid model name specified

**Quick tests**:

```bash
# Test GitHub Models
export GITHUB_TOKEN="github_pat_..."
curl -sS -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"test"}],"max_tokens":5}' \
  https://models.inference.ai.azure.com/chat/completions
```

```bash
# Test Gemini
export GEMINI_API_KEY="..."
curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d '{"contents":[{"parts":[{"text":"test"}]}]}' \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-pro-preview:generateContent?key=$GEMINI_API_KEY"
```

### Rate limits

**GitHub Models**: 15 requests/minute, 150k tokens/day (free tier)
**Gemini**: See [pricing documentation](https://ai.google.dev/pricing)

## Security

- Store API keys only as repository secrets, never commit them
- Use fine-grained PATs with minimal permissions (Models scope only for GitHub)
- Set token expiration and rotate regularly
- Revoke compromised tokens immediately

## Related Documentation

- [GitHub Models](https://github.com/marketplace/models)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Gemini API Documentation](https://ai.google.dev/gemini-api/docs)
