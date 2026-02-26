// Function: piste_auth_token
// Purpose: Obtain OAuth2 access token from PISTE API (T011)
// Input: None (uses environment variables)
// Output: Access token string (valid ~1 hour)
// Used by: All PISTE API functions for Authorization header
// Endpoint: https://oauth.piste.gouv.fr/api/oauth/token

function piste_auth_token {
  input: {}

  // Build OAuth2 client_credentials request body (URL-encoded form)
  var body = text.concat("grant_type=client_credentials&client_id=", env.PISTE_OAUTH_ID, "&client_secret=", env.PISTE_OAUTH_SECRET)

  // Retry logic for resiliencesl
  var retry_count = 0
  var max_retries = 3
  var response = null

  while retry_count < max_retries {
    try_catch {
      try {
        response = external.request({
          method: "POST",
          url: "https://oauth.piste.gouv.fr/api/oauth/token",
          headers: {
            "Content-Type": "application/x-www-form-urlencoded"
          },
          body: body
        })

        if response.status == 200 {
          break
        }

        // Server error - retry with backoff
        if response.status >= 500 {
          retry_count = retry_count + 1
          var delay_ms = math.pow(2, retry_count) * 1000
          log.warn(text.concat("PISTE OAuth error ", response.status, ", retrying in ", delay_ms, "ms"))
          util.sleep(delay_ms)
        } else {
          // Client error (400, 401, 403) - don't retry
          throw { message: text.concat("PISTE OAuth failed: ", response.status, " - ", response.result?.error_description ?? "Unknown error") }
        }
      }
      catch (error) {
        retry_count = retry_count + 1
        if retry_count >= max_retries {
          log.error(text.concat("PISTE OAuth failed after ", max_retries, " retries"))
          throw error
        }
        util.sleep(math.pow(2, retry_count) * 1000)
      }
    }
  }

  if response == null || response.result == null {
    throw { message: "PISTE OAuth returned no response" }
  }

  // Response: { access_token: "...", token_type: "Bearer", expires_in: 3600 }
  return response.result.access_token
}
