# Troubleshooting: Pipeline Sync Légifrance

## Overview

This document provides solutions to common issues encountered during the implementation and operation of the LegalKit vector sync pipeline.

**Last Updated**: 2026-01-29
**Feature**: 001-legalkit-vector-sync

---

## Table of Contents

1. [PISTE API Issues](#piste-api-issues)
2. [Mistral AI Embedding Issues](#mistral-ai-embedding-issues)
3. [Database & Schema Issues](#database--schema-issues)
4. [Sync Performance Issues](#sync-performance-issues)
5. [Data Quality Issues](#data-quality-issues)
6. [Vector Search Issues](#vector-search-issues)

---

## PISTE API Issues

### Issue: OAuth 401 Unauthorized Errors

**Symptoms**:
- Function `piste_auth_token` returns 401 error
- Sync fails with "Authentication failed" message

**Causes**:
1. Invalid OAuth credentials
2. Credentials not configured in environment variables
3. Token expired during long-running sync

**Solutions**:

**Check 1: Verify credentials**
```bash
curl -X POST https://oauth.piste.gouv.fr/api/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=dc06ede7-4a49-44e4-90d8-af342a5e1f36&client_secret=2bfad70f-7cc3-4c60-84ec-1f1e6e69773e"
```

Expected response includes `access_token` field.

**Check 2: Verify environment variables**
```xanoscript
return {
  oauth_id: env.PISTE_OAUTH_ID,
  oauth_secret_length: env.PISTE_OAUTH_SECRET?.length || 0
}
```

If either is null/undefined, configure in Xano settings (see configuration-guide.md).

**Check 3: Implement token refresh**
The `piste_orchestrer_sync` function should refresh tokens every 45 minutes (tokens expire after 1 hour):

```xanoscript
var $token = piste_auth_token()
var $token_issued_at = Date.now()

// Refresh token before expiry during long syncs
if (Date.now() - $token_issued_at > 45 * 60 * 1000) {
  $token = piste_auth_token()  // Refresh
  $token_issued_at = Date.now()
}
```

---

### Issue: PISTE API Rate Limiting (429 errors)

**Symptoms**:
- HTTP 429 "Too Many Requests" responses
- Sync slows down or fails midway

**Cause**: Exceeding PISTE API rate limits (10 req/s recommended)

**Solution**: Implement rate limiting in `piste_sync_code`:

```xanoscript
// Rate limiter: max 10 requests/second
var $requests_per_second = 10
var $delay_ms = 1000 / $requests_per_second

for (var $article_id of $article_ids) {
  var $start = Date.now()

  // Make API call
  var $article = piste_get_article($article_id, $token)

  // Enforce rate limit
  var $elapsed = Date.now() - $start
  if ($elapsed < $delay_ms) {
    // Sleep for remaining time
    sleep($delay_ms - $elapsed)
  }
}
```

---

### Issue: PISTE API 5xx Server Errors

**Symptoms**:
- Intermittent 500, 502, 503 errors from PISTE API
- Sync fails with "Server error" message

**Solution**: Implement retry logic with exponential backoff:

```xanoscript
function piste_get_article_with_retry($article_id, $token, $max_retries = 3) {
  var $retries = 0
  var $backoff = 1000  // 1 second initial backoff

  while ($retries < $max_retries) {
    try {
      var $response = external.request({
        url: "https://api.piste.gouv.fr/dila/legifrance/lf-engine-app/consult/getArticle",
        method: "POST",
        headers: {
          "Authorization": "Bearer " + $token,
          "Content-Type": "application/json"
        },
        body: {id: $article_id}
      })

      if ($response.status >= 200 && $response.status < 300) {
        return $response.body
      }

      if ($response.status >= 500) {
        // Server error - retry
        $retries++
        sleep($backoff)
        $backoff *= 2  // Exponential backoff
        continue
      }

      // Client error (4xx) - don't retry
      throw "Client error: " + $response.status
    } catch ($error) {
      $retries++
      if ($retries >= $max_retries) {
        throw $error
      }
      sleep($backoff)
      $backoff *= 2
    }
  }

  throw "Max retries exceeded for article " + $article_id
}
```

---

## Mistral AI Embedding Issues

### Issue: NULL Embeddings in Database

**Symptoms**:
- `embeddings` field is NULL for many articles
- Embedding coverage < 99.5% (violates CS-003)

**Causes**:
1. Mistral API key invalid/expired
2. Rate limiting exceeded (5 req/s)
3. Text truncation issues (>8000 tokens)
4. Network timeouts

**Solutions**:

**Check 1: Verify API key**
```bash
curl -X POST https://api.mistral.ai/v1/embeddings \
  -H "Authorization: Bearer QMT34dF9pKDubwKTVQepNNsowm5CJ778" \
  -H "Content-Type: application/json" \
  -d '{"model":"mistral-embed","input":["test"]}'
```

Expected: HTTP 200 with `data[0].embedding` array (1024 dimensions)

**Check 2: Implement robust error handling**
```xanoscript
function mistral_generer_embedding($text) {
  if (!$text || $text.length == 0) {
    return null
  }

  // Truncate to 8000 tokens (approx 32000 chars)
  if ($text.length > 32000) {
    $text = $text.substring(0, 32000)
  }

  try {
    var $response = external.request({
      url: "https://api.mistral.ai/v1/embeddings",
      method: "POST",
      headers: {
        "Authorization": "Bearer " + env.MISTRAL_API_KEY,
        "Content-Type": "application/json"
      },
      body: {
        model: "mistral-embed",
        input: [$text]
      },
      timeout: 30000  // 30 second timeout
    })

    if ($response.status == 200) {
      return $response.body.data[0].embedding
    }

    // Log error and return null (sync continues)
    console.log("Mistral API error: " + $response.status)
    return null
  } catch ($error) {
    console.log("Mistral embedding failed: " + $error)
    return null
  }
}
```

**Check 3: Rate limiting**
Similar to PISTE API, enforce 5 req/s limit:

```xanoscript
var $mistral_delay_ms = 200  // 1000ms / 5 req/s
```

---

### Issue: Embedding Dimension Mismatch

**Symptoms**:
- Vector search fails with "dimension mismatch" error
- Some embeddings have != 1024 dimensions

**Cause**: Mistral API returned unexpected embedding size

**Solution**: Validate embedding dimensions before storage:

```xanoscript
var $embedding = mistral_generer_embedding($text)

if ($embedding && $embedding.length == 1024) {
  // Store valid embedding
  $article.embeddings = $embedding
} else {
  // Log invalid embedding
  console.log("Invalid embedding dimensions: " + ($embedding?.length || 0))
  $article.embeddings = null
}
```

---

## Database & Schema Issues

### Issue: Missing Columns After Schema Extension

**Symptoms**:
- Error: "Column 'idEli' does not exist"
- T004 (table extension) not applied correctly

**Solution**: Verify table schema in Xano admin:

1. Navigate to **Database** → **Tables** → **REF_codes_legifrance**
2. Check all 38 new columns exist (see data-model.md)
3. If missing, re-run table schema update
4. Push changes to Xano backend

---

### Issue: Index Not Created on embeddings Field

**Symptoms**:
- Vector similarity search is very slow (>10s)
- Query plan doesn't use vector index

**Solution**: Create vector index manually:

```sql
CREATE INDEX idx_embeddings_vector
ON REF_codes_legifrance
USING ivfflat (embeddings vector_ip_ops)
WITH (lists = 100);
```

Or in Xano table definition:
```xanoscript
{
  type: "vector",
  field: [{name: "embeddings", op: "vector_ip_ops"}]
}
```

---

## Sync Performance Issues

### Issue: Incremental Sync Takes >30 Minutes

**Symptoms**:
- Violates CS-002 requirement (< 30 min)
- LOG_sync_legifrance shows long `duree_secondes`

**Causes**:
1. Hash comparison not working (re-processing unchanged articles)
2. Missing database indexes
3. Too many API calls (not batching)

**Solutions**:

**Check 1: Verify hash comparison**
```xanoscript
// In piste_sync_code function
var $existing_article = db.query("REF_codes_legifrance")
  .filter({id_legifrance: $article.id})
  .findOne()

if ($existing_article) {
  var $new_hash = hash_contenu_article($article)
  if ($new_hash == $existing_article.content_hash) {
    // Skip unchanged article (CRITICAL OPTIMIZATION)
    continue
  }
}
```

**Check 2: Verify indexes**
Run T028 verification (see testing-validation-guide.md)

**Check 3: Batch processing**
```xanoscript
// Process articles in batches of 50
var $batch_size = 50
for (var $i = 0; $i < $article_ids.length; $i += $batch_size) {
  var $batch = $article_ids.slice($i, $i + $batch_size)
  // Process batch
}
```

---

### Issue: Initial Sync Takes >24 Hours

**Symptoms**:
- Violates CS-001 requirement (5 codes in < 24h)
- Sync timeout errors

**Causes**:
1. Too many API calls (not parallelizing)
2. Rate limiting too aggressive
3. Network latency

**Solutions**:

**Check 1: Parallelize code syncs**
Process multiple codes concurrently (if Xano supports async):

```xanoscript
// Process codes in parallel (if supported)
var $codes = db.query("LEX_codes_piste")
  .filter({actif: true})
  .orderBy("priorite", "asc")
  .findMany()

// For each code, trigger async sync
for (var $code of $codes) {
  // Async call to piste_sync_code
  async_call("piste_sync_code", {textId: $code.textId})
}
```

**Check 2: Optimize rate limits**
Balance between speed and API limits:
- PISTE: 10 req/s (100ms delay)
- Mistral: 5 req/s (200ms delay)

---

## Data Quality Issues

### Issue: Missing Article Metadata (38 fields)

**Symptoms**:
- Fields like `idEli`, `fullSectionsTitre` are NULL
- Violates EF-002 requirement

**Cause**: PISTE API response doesn't include all fields for every article

**Solution**: Handle missing fields gracefully:

```xanoscript
function map_piste_article($piste_response) {
  return {
    id_legifrance: $piste_response.id || null,
    cid: $piste_response.cid || null,
    num: $piste_response.num || null,
    idEli: $piste_response.idEli || null,  // May be null for older articles
    texte: $piste_response.texte || null,
    // ... map all 38 fields with || null fallback
  }
}
```

Store NULL for missing fields (per EF-012).

---

### Issue: Hierarchical Structure Parsing Fails

**Symptoms**:
- `partie`, `livre`, `titre` fields are NULL
- `parser_fullSectionsTitre` returns empty object

**Cause**: `fullSectionsTitre` format is unexpected

**Solution**: Implement robust parsing with fallbacks:

```xanoscript
function parser_fullSectionsTitre($fullSectionsTitre) {
  if (!$fullSectionsTitre) {
    return {partie: null, livre: null, titre: null, chapitre: null, section: null}
  }

  // Example: "PARTIE 1 > LIVRE II > TITRE III > CHAPITRE 4 > SECTION 2"
  var $parts = $fullSectionsTitre.split(" > ")
  var $result = {}

  for (var $part of $parts) {
    if ($part.startsWith("PARTIE")) {
      $result.partie = $part.replace("PARTIE ", "").trim()
    } else if ($part.startsWith("LIVRE")) {
      $result.livre = $part.replace("LIVRE ", "").trim()
    } else if ($part.startsWith("TITRE")) {
      $result.titre = $part.replace("TITRE ", "").trim()
    } else if ($part.startsWith("CHAPITRE")) {
      $result.chapitre = $part.replace("CHAPITRE ", "").trim()
    } else if ($part.startsWith("SECTION")) {
      $result.section = $part.replace("SECTION ", "").trim()
    }
  }

  return $result
}
```

---

## Vector Search Issues

### Issue: Search Returns Irrelevant Results

**Symptoms**:
- Similarity scores < 0.8 for relevant queries
- Violates CS-004 requirement (95% relevance)

**Causes**:
1. Embeddings generated from wrong text (missing context)
2. Vector distance metric incorrect
3. Articles not filtered by `etat = "VIGUEUR"`

**Solutions**:

**Check 1: Verify embedding context**
Per EF-003, embeddings should include:
- `fullSectionsTitre` (hierarchical context)
- `surtitre` (subtitle)
- `texte` (main content)

```xanoscript
var $embedding_text = (
  ($article.fullSectionsTitre || "") + " " +
  ($article.surtitre || "") + " " +
  ($article.texte || "")
).trim()

var $embedding = mistral_generer_embedding($embedding_text)
```

**Check 2: Verify distance metric**
Use **inner product** (`<#>`) for Mistral embeddings (not cosine or L2):

```xanoscript
var $results = db.query("REF_codes_legifrance")
  .filter({etat: "VIGUEUR"})
  .orderBy("embeddings <#> $query_embedding", "asc")  // CORRECT
  .limit(5)
  .findMany()
```

**Check 3: Filter inactive articles**
Always filter by `etat = "VIGUEUR"` to exclude abrogated articles.

---

### Issue: Vector Index Not Used (Slow Queries)

**Symptoms**:
- Similarity search takes >10 seconds
- Database CPU high during search

**Cause**: Missing or misconfigured vector index

**Solution**: See "Index Not Created on embeddings Field" above.

**Verify index usage**:
```sql
EXPLAIN ANALYZE
SELECT * FROM REF_codes_legifrance
ORDER BY embeddings <#> '[0.1, 0.2, ...]'::vector
LIMIT 5;
```

Should show: "Index Scan using idx_embeddings_vector"

---

## Getting Help

### Log Analysis

Check the LOG_sync_legifrance table for error details:

```sql
SELECT
  id,
  code_textId,
  statut,
  erreur_message,
  erreur_details,
  debut_sync
FROM LOG_sync_legifrance
WHERE statut = 'ERREUR'
ORDER BY debut_sync DESC;
```

### Debug Mode

Add verbose logging to sync functions:

```xanoscript
// Enable debug logging
var $debug = true

if ($debug) {
  console.log("Processing article: " + $article.id)
  console.log("Hash: " + $hash)
  console.log("Existing hash: " + ($existing?.content_hash || "none"))
}
```

### Contact Support

If issues persist:
1. Export LOG_sync_legifrance error entries
2. Provide Xano workspace ID: `x8ki-letl-twmt`
3. Include feature branch: `001-legalkit-vector-sync`
4. Reference this troubleshooting guide

---

## Known Issues & Limitations

### Current Limitations

1. **Chunking for long articles**: Articles >8000 tokens are truncated (Option B implementation). Option A (multi-fragment) deferred to post-MVP.

2. **PISTE API availability**: Dependent on French government API uptime. No SLA guarantees.

3. **Rate limiting**: Conservative limits (10 req/s PISTE, 5 req/s Mistral) may slow initial sync. Adjustable based on actual API limits.

4. **Abrogated articles**: Currently stored but excluded from search. Future: implement soft-delete or archival.

### Future Enhancements

1. **Smart chunking**: Implement hierarchical chunking based on code subdivisions (see plan.md chunking strategy)
2. **Incremental TOC updates**: Currently re-fetches full TOC. Future: detect TOC changes to optimize.
3. **Webhook notifications**: Real-time alerts on sync failures (currently logged only)
4. **Multi-workspace support**: Currently single workspace. Future: tenant isolation.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-29
**Maintained By**: marIAnne development team
