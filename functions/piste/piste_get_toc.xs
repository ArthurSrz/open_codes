// Function: piste_get_toc
// Purpose: Fetch table of contents for a legal code from PISTE API (T012)
// Input: textId (LEGITEXT...) and optional date
// Output: TOC structure with nested sections
// Endpoint: POST /consult/legi/tableMatieres

function piste_get_toc {
  input: {
    textId: text              // e.g., "LEGITEXT000006070633"
    date: text?               // Optional date filter (YYYY-MM-DD), defaults to today
  }

  // Get fresh OAuth token
  var token = call piste_auth_token()

  // Default date to today
  var query_date = date ?? date.format(date.now(), "YYYY-MM-DD")

  // Call PISTE API
  var response = external.request({
    method: "POST",
    url: "https://api.piste.gouv.fr/dila/legifrance/lf-engine-app/consult/legi/tableMatieres",
    headers: {
      "Authorization": text.concat("Bearer ", token),
      "Content-Type": "application/json"
    },
    body: {
      textId: textId,
      date: query_date
    }
  })

  if response.status != 200 {
    throw {
      message: text.concat("PISTE tableMatieres failed: ", response.status),
      textId: textId,
      status: response.status
    }
  }

  // Response contains: { title, sections: [...] }
  return response.result
}
