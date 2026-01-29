# Configuration Guide: Pipeline Sync Légifrance

## Environment Variables Setup

### Required Variables

Configure the following environment variables in your Xano workspace settings:

#### 1. PISTE OAuth Credentials

```
PISTE_OAUTH_ID=dc06ede7-4a49-44e4-90d8-af342a5e1f36
PISTE_OAUTH_SECRET=2bfad70f-7cc3-4c60-84ec-1f1e6e69773e
```

**Purpose**: OAuth2 client credentials for authentication with the PISTE API (Légifrance official API)

**Source**: These credentials are from the research.md file and provide access to the French legal code database via the official government API.

#### 2. Mistral AI API Key

```
MISTRAL_API_KEY=QMT34dF9pKDubwKTVQepNNsowm5CJ778
```

**Purpose**: API key for generating 1024-dimensional embeddings using Mistral AI's `mistral-embed` model

**Usage**: Used by the `mistral_generer_embedding` function to create vector embeddings for semantic search

---

## How to Configure in Xano

### Step 1: Access Workspace Settings

1. Log into your Xano workspace
2. Navigate to **Settings** → **Environment Variables**
3. Click **Add New Variable**

### Step 2: Add Each Variable

For each variable above:

1. **Variable Name**: Enter the exact name (e.g., `PISTE_OAUTH_ID`)
2. **Variable Value**: Enter the corresponding value
3. **Environment**: Select the appropriate environment (Development/Production)
4. Click **Save**

### Step 3: Verify Configuration

After adding all three variables, verify they are accessible:

1. Navigate to any function in your workspace
2. Reference `env.PISTE_OAUTH_ID` in a test expression
3. Run a test execution to confirm the value is retrieved correctly

---

## Security Notes

⚠️ **IMPORTANT**: These are **production credentials**. Do not commit them to version control or share publicly.

- The PISTE OAuth credentials provide access to official French legal data
- The Mistral API key has usage limits and billing implications
- If credentials are compromised, regenerate them immediately through:
  - PISTE: https://developer.aife.economie.gouv.fr/
  - Mistral: https://console.mistral.ai/

---

## Troubleshooting

### PISTE OAuth Issues

If authentication fails:

```bash
# Test OAuth flow directly
curl -X POST https://oauth.piste.gouv.fr/api/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=dc06ede7-4a49-44e4-90d8-af342a5e1f36&client_secret=2bfad70f-7cc3-4c60-84ec-1f1e6e69773e"
```

Expected response:
```json
{
  "access_token": "...",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

### Mistral AI Issues

If embedding generation fails:

```bash
# Test Mistral API
curl -X POST https://api.mistral.ai/v1/embeddings \
  -H "Authorization: Bearer QMT34dF9pKDubwKTVQepNNsowm5CJ778" \
  -H "Content-Type: application/json" \
  -d '{"model":"mistral-embed","input":["Test text"]}'
```

Expected response:
```json
{
  "object": "list",
  "data": [{
    "object": "embedding",
    "embedding": [0.123, 0.456, ...], // 1024 dimensions
    "index": 0
  }]
}
```

---

## Next Steps

After configuration:

1. ✅ Verify all 3 environment variables are set
2. ➡️ Proceed to **T017**: Populate LEX_codes_piste with priority codes
3. ➡️ Run **T018**: Test initial sync

---

**Task Status**: T010 - Configuration guide created ✓

Manually apply these settings in Xano admin panel to complete T010.
