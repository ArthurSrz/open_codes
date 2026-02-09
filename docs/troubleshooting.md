# Troubleshooting: Pipeline Sync Légifrance

## Overview

This document provides solutions to common issues encountered during the implementation and operation of the LegalKit vector sync pipeline.

**Last Updated**: 2026-01-29
**Feature**: 001-legalkit-vector-sync

---

## Table of Contents

1. [Authentication & Authorization Issues](#authentication--authorization-issues)
2. [PISTE API Issues](#piste-api-issues)
3. [Mistral AI Embedding Issues](#mistral-ai-embedding-issues)
4. [Database & Schema Issues](#database--schema-issues)
5. [Sync Performance Issues](#sync-performance-issues)
6. [Data Quality Issues](#data-quality-issues)
7. [Vector Search Issues](#vector-search-issues)

---

## Authentication & Authorization Issues

### Issue: Unable to Locate Auth Extras Field

**Symptoms**:
- Error: `Unable to locate auth: extras.gestionnaire`
- API endpoint returns 500 error when checking user permissions
- Precondition using `$auth.extras.gestionnaire` fails

**Cause**: In Xano, the `$auth` object from JWT authentication does NOT automatically include custom fields from the auth table (like `gestionnaire`). The `extras` field is not populated by default with custom table columns.

**Broken Code**:
```xanoscript
// ❌ This fails - extras.gestionnaire is not automatically populated
precondition ($auth.extras.gestionnaire || $auth.role == "admin") {
  error_type = "accessdenied"
  error = "Access denied"
}
```

**Solution**: Query the user directly from the database using the authenticated user's ID:

```xanoscript
// ✅ Correct approach - fetch user record to check custom fields
db.get "utilisateurs" {
  field_name = "id"
  field_value = $auth.id
  description = "Fetch authenticated user"
} as $user

precondition ($user.gestionnaire == true || $auth.role == "admin") {
  error_type = "accessdenied"
  error = "Accès réservé aux gestionnaires et administrateurs"
}
```

**Why This Works**:
- `$auth.id` is always available from the JWT token
- `db.get` fetches the full user record including custom fields like `gestionnaire`
- The precondition then checks the actual database value

**Alternative**: Configure auth extras in Xano settings (more complex, requires modifying auth configuration for the workspace).

**Fixed in**: API `sync_legifrance_lancer` (ID 924, workspace 5, branch `requete_textes`) - 2026-02-06

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

## Document Generation Issues (Feature 002)

### Issue: DOCX Placeholders Split Across XML Runs

**Symptoms**:
- `{{placeholder}}` not replaced in generated document
- Some placeholders work, others don't
- Generated DOCX has raw `{{placeholder_name}}` text visible

**Cause**: When a DOCX template is edited in Microsoft Word, Word may split `{{placeholder}}` across multiple XML `<w:r>` (run) elements:
```xml
<!-- Word may produce this fragmented XML: -->
<w:r><w:t>{{</w:t></w:r>
<w:r><w:t>placeholder</w:t></w:r>
<w:r><w:t>_name</w:t></w:r>
<w:r><w:t>}}</w:t></w:r>
```

**Solution**:
1. **Prevention**: Use `python-docx` to generate templates programmatically (our `create_templates.py` produces clean single-run placeholders)
2. **Detection**: Check generated DOCX for unreplaced `{{` patterns
3. **Fix in Word**: Select the placeholder text, delete it, and retype it in one go (without formatting changes in between)

**Template Creation Best Practice**:
- Type `{{placeholder_name}}` in one continuous action
- Do NOT apply different formatting to parts of the placeholder
- Do NOT copy-paste placeholder text from another source
- Verify with: unzip template.docx and grep for `\{\{` in `word/document.xml`

---

### Issue: XML Special Characters in Placeholder Values

**Symptoms**:
- Generated DOCX file is corrupted / won't open
- Error: "The file is damaged and cannot be opened"
- Values containing `&`, `<`, `>`, or `"` cause issues

**Cause**: Placeholder values with XML special characters break the XML structure of `word/document.xml`.

**Solution**: Always XML-escape values before substitution:
```xanoscript
// ✅ Correct - escape XML special chars
var $valeur_safe {
  value = $valeur_brute|replace:"&":"&amp;"|replace:"<":"&lt;"|replace:">":"&gt;"|replace:"\"":"&quot;"
}
```

**Already implemented** in `docx_remplir_placeholders.xs` and `917_generer_document_final_POST.xs`.

---

### Issue: file.unzip / file.zip Not Available in XanoScript

**Symptoms**:
- Error: "Unknown function: file.unzip"
- DOCX processing pipeline fails

**Cause**: XanoScript may not support `file.unzip` and `file.zip` natively. These are hypothetical functions based on the plan.

**Workaround**: If `file.unzip`/`file.zip` are not available:
1. Use an external service (e.g., a Node.js Cloud Function) for ZIP manipulation
2. Or use the `api.request` to a ZIP manipulation API
3. Or pre-process templates: store `word/document.xml` as a separate text field in the template table, and use client-side JavaScript to reconstruct the DOCX

**Investigation needed**: Test `file.unzip` availability in Xano workspace 5 before deployment.

---

### Issue: Chatbot Date Parsing Inconsistency

**Symptoms**:
- Dates entered as "15 mars 2026" not correctly parsed
- Mistral returns "INVALIDE" for valid French date formats

**Solution**: The `916_collecter_donnees_chatbot_POST.xs` endpoint uses Mistral to parse dates. Ensure the system prompt is explicit about accepted formats:
```
"Convertis le texte en date au format JJ/MM/AAAA. Accepte les formats:
'15/03/2026', '15 mars 2026', '15-03-2026', 'le 15 mars'.
Si l'année n'est pas précisée, utilise l'année en cours."
```

---

### Issue: `format_timestamp` vs `date` Filter in XanoScript

**Symptoms**:
- Error: "Invalid filter name: date" when using `"now"|date:"d/m/Y"`
- Error: "Invalid filter name: to_date" when using `"now"|to_date:"d/m/Y"`
- Only happens inside chained `|set:` expressions

**Cause**: The `date` and `to_date` filters do not exist in XanoScript. The correct filter is `format_timestamp`.

**Solution**:
```xanoscript
// ❌ BROKEN - these filters don't exist
var $date { value = "now"|date:"d/m/Y" }
var $date { value = "now"|to_date:"d/m/Y" }

// ✅ WORKING - use format_timestamp
var $date { value = now|format_timestamp:"d/m/Y" }

// ⚠️ If inside |set: chain, break into separate var.update:
var $data { value = {commune: "Test"} }
var $date_str { value = now|format_timestamp:"d/m/Y" }
var.update $data { value = $data|set:"date_signature":$date_str }
```

**Fixed in**: API `917_generer_document_final_POST.xs` (genere_template branch) - 2026-02-06

---

### Issue: `db.edit` Cannot Accept Variable Reference for `data`

**Symptoms**:
- Error: "Invalid kind for data - assign:var"
- Happens when passing `data = $my_variable` to `db.edit`

**Cause**: XanoScript `db.edit` requires an inline object literal for the `data` field, not a variable reference.

**Broken Code**:
```xanoscript
// ❌ BROKEN
var $updates { value = {nom: "New Name", version: 2} }
db.edit "table" {
  field_name = "id"
  field_value = 1
  data = $updates  // Error!
}
```

**Solution**: Use inline object with pre-computed variables:
```xanoscript
// ✅ WORKING - compute values in separate vars, use inline object
var $final_nom { value = $input.nom != "" ? $input.nom : $template.nom }
db.edit "table" {
  field_name = "id"
  field_value = 1
  data = {
    nom: $final_nom,
    version: $template.version + 1
  }
}
```

**Fixed in**: API `921_maj_template_PUT.xs` (genere_template branch) - 2026-02-06

---

### Issue: API Group Uses `docs` Not `description`

**Symptoms**:
- Error: "Invalid kind for description" when creating API group
- Error: "Invalid block: tag" when using tag field

**Cause**: API group blocks use `docs` (not `description`) and don't support `tag`.

**Solution**:
```xanoscript
// ❌ BROKEN
api_group "My Group" {
  description = "Some description"
  tag = ["tag1"]
}

// ✅ WORKING
api_group "My Group" {
  docs = "Some description"
}
```

**Fixed in**: API groups Doc Generator (56), Admin Templates (57) - 2026-02-06

---

### Issue: MCP Tool Key Names and Ternary Operators

**Symptoms**:
- Error: "Syntax error: unexpected 'action:'" in MCP tool result objects
- Ternary operators inside inline objects cause parse errors

**Cause**: Certain key names like `action` may conflict with XanoScript reserved words inside tool contexts. Ternary operators in complex inline objects can also cause parser failures.

**Solution**:
```xanoscript
// ❌ BROKEN - 'action' key and ternary in inline object
var.update $resultat {
  value = {
    action: "lister",
    message: $complete ? "Done" : "More"
  }
}

// ✅ WORKING - rename key, use separate conditional
var $msg { value = "" }
conditional {
  if ($complete) { var.update $msg { value = "Done" } }
  else { var.update $msg { value = "More" } }
}
var.update $resultat {
  value = { act: "lister", message: $msg }
}
```

**Fixed in**: MCP tool `genere_acte_admistratif` (ID: 24) - 2026-02-06

---

### Issue: DOCX Pipeline - Two-Copy Pattern Required

**Symptoms**:
- `zip.delete_from_archive` returns "Invalid zip" error
- `zip.create_archive` crashes with fatal 500 error
- Modified DOCX can't be opened

**Cause**: Xano ZIP operations have specific constraints:
1. `zip.create_archive` is broken (fatal error) — cannot create ZIP from scratch
2. `zip.delete_from_archive` and `zip.add_to_archive` require `.zip` extension on the file resource
3. `zip.extract` works with `.docx` extension but write operations don't

**Solution**: Use the **two-copy pattern**:
```xanoscript
// 1. Download template DOCX
api.request {
  url = $template.fichier_docx.url
  method = "GET"
} as $docx_dl

// 2. Create TWO copies with different extensions
storage.create_file_resource {
  filename = "read_copy.docx"      // .docx for reading/extracting
  filedata = $docx_dl.response.result
} as $read_copy

storage.create_file_resource {
  filename = "output.zip"           // .zip for write operations
  filedata = $docx_dl.response.result
} as $output_copy

// 3. Extract from .docx copy
zip.extract {
  zip = $read_copy
  password = ""                     // Required! Even if no password
} as $extracted_files

// 4. Read document.xml content
foreach ($extracted_files) {
  each as $f {
    conditional {
      if ($f.name == "word/document.xml") {
        storage.read_file_resource {
          value = $f.resource        // NOT $f.content (doesn't exist)
        } as $read_result
        // Content is in $read_result.data
      }
      else { }
    }
  }
}

// 5. Modify content, then rebuild using .zip copy
zip.delete_from_archive {
  filename = "word/document.xml"
  zip = $output_copy
  password = ""                     // Required!
}

storage.create_file_resource {
  filename = "document.xml"
  filedata = $xml_modifie
} as $xml_file

zip.add_to_archive {
  file = $xml_file
  filename = "word/document.xml"
  zip = $output_copy
  password = ""                     // Required!
  password_encryption = ""          // Required!
}

// 6. Persist for DB storage
storage.create_attachment {
  value = $output_copy
  access = "public"
  filename = "document_genere.docx"
} as $docx_attachment

// Use $docx_attachment (NOT $output_copy) in db.add
db.add documents_generes {
  data = { fichier_docx: $docx_attachment }
}
```

**Key Rules**:
- `.docx` extension for `zip.extract` (read operations)
- `.zip` extension for `zip.delete_from_archive` and `zip.add_to_archive` (write operations)
- All zip operations require `password = ""` even when no password is used
- `zip.add_to_archive` also requires `password_encryption = ""`
- Extracted files have `{name, size, last_modified, resource}` — use `storage.read_file_resource` to get content
- Use `storage.create_attachment` to persist file resources for database storage

**Fixed in**: API 1071 `generer_document_final`, MCP tool 24 `genere_acte_administratif` - 2026-02-07

---

### Issue: `object.entries` Returns Objects, Not Arrays

**Symptoms**:
- `$e[0]` and `$e[1]` return `null` when iterating `object.entries` results
- Placeholder replacement loop does nothing (0 replacements)

**Cause**: In XanoScript, `object.entries` returns `[{key: "...", value: "..."}]` objects, NOT JavaScript-style `[[key, value]]` arrays.

**Broken Code**:
```xanoscript
// ❌ BROKEN - array indexing returns null
object.entries { value = $my_obj } as $entries
foreach ($entries) {
  each as $e {
    var $key { value = $e[0] }    // null!
    var $val { value = $e[1] }    // null!
  }
}
```

**Solution**:
```xanoscript
// ✅ WORKING - use .key and .value properties
object.entries { value = $my_obj } as $entries
foreach ($entries) {
  each as $e {
    var $key { value = $e.key }    // correct!
    var $val { value = $e.value }  // correct!
  }
}
```

**Fixed in**: API 1071 `generer_document_final`, MCP tool 24 - 2026-02-07

---

### Issue: `||` (OR) Operator in db.query Where Clauses

**Symptoms**:
- Complex where clause `(A && (B || C))` fails at runtime
- Error varies: sometimes syntax error, sometimes unexpected results

**Cause**: Nested OR conditions in db.query where clauses are unreliable in XanoScript.

**Broken Code**:
```xanoscript
// ❌ BROKEN - nested OR in where clause
db.query templates {
  where = $db.templates.actif == true
    && ($db.templates.communes_id == $user.commune_id
    || $db.templates.is_global == true)
}
```

**Solution**: Split into two separate queries and merge:
```xanoscript
// ✅ WORKING - two queries + merge
db.query templates {
  where = $db.templates.actif == true && $db.templates.communes_id == $user.commune_id
} as $q1

db.query templates {
  where = $db.templates.actif == true && $db.templates.is_global == true
} as $q2

var $results { value = $q1|merge:$q2 }
```

For preconditions, use a conditional block with a flag variable:
```xanoscript
// ✅ WORKING - conditional flag instead of ||
var $has_access { value = false }
conditional {
  if ($template.communes_id == $user.commune_id) {
    var.update $has_access { value = true }
  }
  elseif ($template.is_global) {
    var.update $has_access { value = true }
  }
  else { }
}
precondition ($has_access) { error_type = "accessdenied" error = "Accès refusé" }
```

**Fixed in**: APIs 1064, 1067, MCP tool 24 - 2026-02-07

---

### Issue: Mistral Date Parser Rejects Already-Formatted Dates

**Symptoms**:
- Mistral returns "INVALIDE" for input like "15/02/2026" (already in JJ/MM/AAAA format)
- Only happens when the date is already correctly formatted

**Cause**: The Mistral date parsing prompt may reject already-formatted dates depending on model behavior.

**Workaround**: Users should provide dates in natural language ("le quinze février 2026") rather than formatted dates. A future fix could pre-check if the input already matches `JJ/MM/AAAA` regex and skip Mistral parsing.

**Status**: Known limitation, low priority (chatbot flow naturally uses natural language)

---

**Document Version**: 3.0
**Last Updated**: 2026-02-07
**Maintained By**: marIAnne development team
