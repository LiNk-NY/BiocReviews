# GitHub Models Token Setup

This guide explains how to configure a Personal Access Token (PAT) for GitHub Models API access in the auto-review workflow.

## Why is this needed?

The default `GITHUB_TOKEN` provided by GitHub Actions has limited permissions and cannot access the GitHub Models API endpoint (`models.inference.ai.azure.com`). To enable LLM enhancement in the automated reviews, you need to provide a Personal Access Token with the appropriate scopes.

## Symptoms of Missing Token

If the `GITHUB_MODELS_TOKEN` is not configured, you'll see:

1. **In the workflow run**: A warning message:
   ```
   ⚠️ LLM enhancement failed and fell back to rule-based review only.
   ```

2. **In the review output**: A fallback message:
   ```markdown
   ## LLM enhancement unavailable
   - Attempted model: `meta-llama-3.1-405b-instruct`
   - Error: `simpleError`

   The rule-based review is provided below.
   ```

3. **In the issue comment**: The review will only contain the basic rule-based analysis, without LLM insights.

## Setup Instructions

### Step 1: Create a Personal Access Token

1. Go to [GitHub Settings > Personal Access Tokens](https://github.com/settings/tokens)

2. Click **"Generate new token"** > **"Generate new token (classic)"**

3. Configure the token:
   - **Note**: `BiocReviews GitHub Models API Access` (or any descriptive name)
   - **Expiration**: Choose an appropriate expiration period (90 days, 1 year, or no expiration)
   - **Scopes**: Select the following permissions:
     - ✅ `repo` (Full control of private repositories)
       - This is required for the token to work with repository secrets
     - ✅ `read:user` (Read user profile data)
       - This is the minimum scope for GitHub Models free tier access
     - Optional: `read:org` if this is for an organization repository

4. Click **"Generate token"** at the bottom

5. **IMPORTANT**: Copy the token immediately! You won't be able to see it again.
   - The token will look like: `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

### Step 2: Add Token as Repository Secret

1. Go to your BiocReviews repository on GitHub

2. Navigate to **Settings > Secrets and variables > Actions**

3. Click **"New repository secret"**

4. Configure the secret:
   - **Name**: `GITHUB_MODELS_TOKEN`
   - **Value**: Paste the PAT you generated in Step 1

5. Click **"Add secret"**

### Step 3: Verify the Setup

Trigger a workflow run to verify the token works:

1. **Option A - Via workflow_dispatch**:
   - Go to **Actions > AI Review Assistant**
   - Click **"Run workflow"**
   - Fill in the package details and click **"Run workflow"**

2. **Option B - Trigger from build-check workflow**:
   - Comment `@biocreview` on an issue to trigger the full review pipeline

3. **Check the results**:
   - The workflow should complete without the LLM fallback warning
   - The review should include LLM-generated insights
   - The review header should show:
     ```markdown
     *Review enhanced by **meta-llama-3.1-405b-instruct (GitHub Models)** on YYYY-MM-DD.*
     ```

## Testing Locally

You can test the token locally before adding it as a secret:

```bash
# Set the token
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Test the GitHub Models API
curl -sS -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"meta-llama-3.1-405b-instruct","messages":[{"role":"user","content":"test"}],"max_tokens":5}' \
  https://models.inference.ai.azure.com/chat/completions

# Should return a JSON response like:
# {"choices":[{"finish_reason":"length","index":0,"message":{"content":"...","role":"assistant"}}],...}
```

If you get an error like `{"error":{"code":"401","message":"Unauthorized"}}`, the token doesn't have the right permissions.

## Troubleshooting

### Error: "Unauthorized" or "Access Denied"

**Cause**: The token doesn't have the required scopes.

**Solution**:
1. Delete the old token
2. Create a new token with `repo` and `read:user` scopes
3. Update the `GITHUB_MODELS_TOKEN` secret

### Error: "Rate limit exceeded"

**Cause**: You've exceeded the GitHub Models free tier limits (15 requests/minute, 150k tokens/day).

**Solution**:
- Wait 1 minute and retry
- Consider reducing the frequency of reviews
- Contact GitHub for higher rate limits if needed

### Warning still appears after adding token

**Cause**: The secret may not be properly configured or the token is invalid.

**Solution**:
1. Verify the secret name is exactly `GITHUB_MODELS_TOKEN` (case-sensitive)
2. Check the token hasn't expired
3. Re-test the token locally using the command above
4. If needed, regenerate the token and update the secret

### LLM enhancement works locally but not in Actions

**Cause**: The repository secret isn't accessible to the workflow.

**Solution**:
1. Verify the secret is added to the correct repository
2. For organization repositories, check organization secret policies
3. Ensure the workflow has permission to access secrets

## Alternative: Use AWS Bedrock Instead

If you prefer not to manage a GitHub PAT, you can switch to AWS Bedrock for Claude models:

1. Configure AWS credentials as repository secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

2. Update the workflow environment variable:
   ```yaml
   GITHUB_MODEL: "anthropic.claude-3-5-sonnet-20241022-v2:0"
   ```

3. Modify the enhancement script call to use Bedrock instead of GitHub Models

See [MODEL_PROVIDERS.md](MODEL_PROVIDERS.md) for more details.

## Security Considerations

- **Token permissions**: The PAT has broad access to your repositories. Store it securely.
- **Expiration**: Set a reasonable expiration period and plan to rotate tokens regularly.
- **Revocation**: If the token is compromised, revoke it immediately at https://github.com/settings/tokens
- **Secret storage**: Never commit tokens to the repository or expose them in logs.
- **Organization policies**: Some organizations may restrict PAT usage or require admin approval.

## Related Documentation

- [GitHub Personal Access Tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [GitHub Models Documentation](https://github.com/marketplace/models)

## Support

If you continue to experience issues:
1. Check the workflow logs for detailed error messages
2. Verify the token works with the local test command above
3. Open an issue at the repository with relevant error logs (redact any sensitive information)
