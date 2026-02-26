// Function: mistral_generer_embedding
// Purpose: Generate 1024-dim embedding vector via Mistral AI API (EF-003)
// Input: Text content to embed (max ~8000 tokens)
// Output: Array of 1024 floats for vector similarity search
// Used by: piste_sync_code to generate embeddings for REF_codes_legifrance

function mistral_generer_embedding {
  input: {
    texte: text                 // Text content to embed
    truncate_at: int = 8000     // Max characters before truncation (Mistral limit ~8k tokens)
  }

  // Truncate if needed (EF-009: respect API limits)
  var content = texte
  if text.length(content) > truncate_at {
    content = text.substring(content, 0, truncate_at)
    log.warn(text.concat("Text truncated from ", text.length(texte), " to ", truncate_at, " chars"))
  }

  // Call Mistral embeddings API
  var retry_count = 0
  var max_retries = 3
  var response = null

  while retry_count < max_retries {
    try_catch {
      try {
        response = external.request({
          method: "POST",
          url: "https://api.mistral.ai/v1/embeddings",
          headers: {
            "Authorization": text.concat("Bearer ", env.MISTRAL_API_KEY),
            "Content-Type": "application/json"
          },
          body: {
            model: "mistral-embed",
            input: [content]
          }
        })

        // Success - break out of retry loop
        if response.status == 200 {
          break
        }

        // Rate limit - wait and retry
        if response.status == 429 {
          retry_count = retry_count + 1
          var delay_ms = math.pow(2, retry_count) * 1000
          log.warn(text.concat("Mistral rate limited, waiting ", delay_ms, "ms (attempt ", retry_count, "/", max_retries, ")"))
          util.sleep(delay_ms)
        } else {
          // Other error - don't retry
          throw { message: text.concat("Mistral API error: ", response.status) }
        }
      }
      catch (error) {
        retry_count = retry_count + 1
        if retry_count >= max_retries {
          log.error(text.concat("Mistral embedding failed after ", max_retries, " retries: ", error.message))
          throw error
        }
        var delay_ms = math.pow(2, retry_count) * 1000
        util.sleep(delay_ms)
      }
    }
  }

  // Extract embedding vector from response
  // Response structure: { data: [{ embedding: [float, float, ...] }] }
  if response == null || response.result == null || response.result.data == null {
    throw { message: "Invalid Mistral API response" }
  }

  var embedding = response.result.data[0].embedding

  // Validate embedding dimension (should be 1024)
  if list.length(embedding) != 1024 {
    log.warn(text.concat("Unexpected embedding dimension: ", list.length(embedding), " (expected 1024)"))
  }

  return embedding
}
