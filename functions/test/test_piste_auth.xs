// Test: test_piste_auth
// Purpose: Verify PISTE OAuth2 authentication works
// Run this after configuring env variables in Xano

function test_piste_auth {
  input: {}

  log.info("Testing PISTE OAuth2 authentication...")

  // Call the auth function
  var token = call piste_auth_token()

  // Validate token
  if token == null || text.length(token) < 10 {
    throw { message: "Invalid token received" }
  }

  log.info(text.concat("✅ OAuth success! Token length: ", text.length(token)))
  log.info(text.concat("Token preview: ", text.substring(token, 0, 20), "..."))

  return {
    success: true,
    token_length: text.length(token),
    token_preview: text.concat(text.substring(token, 0, 20), "...")
  }
}
