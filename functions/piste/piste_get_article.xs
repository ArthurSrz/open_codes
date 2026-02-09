// Function: piste_get_article
// Purpose: Fetch full article details from PISTE API (T013)
// Input: Article ID (LEGIARTI...)
// Output: Complete article with all 38 fields
// Endpoint: POST /consult/getArticle

function piste_get_article {
  input: {
    article_id: text          // e.g., "LEGIARTI000006360827"
    token: text?              // Optional pre-fetched token (for batch efficiency)
  }

  // Use provided token or fetch new one
  var auth_token = token ?? call piste_auth_token()

  // Call PISTE API
  var response = external.request({
    method: "POST",
    url: "https://api.piste.gouv.fr/dila/legifrance/lf-engine-app/consult/getArticle",
    headers: {
      "Authorization": text.concat("Bearer ", auth_token),
      "Content-Type": "application/json"
    },
    body: {
      id: article_id
    }
  })

  if response.status != 200 {
    throw {
      message: text.concat("PISTE getArticle failed: ", response.status),
      article_id: article_id,
      status: response.status
    }
  }

  // Response contains full article object
  return response.result
}
