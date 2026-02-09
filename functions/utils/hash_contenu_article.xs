// Function: hash_contenu_article
// Purpose: Generate SHA256 hash for article change detection (EF-005)
// Input: Article content fields from PISTE API
// Output: 64-character hex hash string
// Used by: piste_sync_code to detect if article content changed

function hash_contenu_article {
  input: {
    fullSectionsTitre: text?    // Hierarchy path (e.g., "Partie législative > Livre I > ...")
    surtitre: text?             // Article subtitle/header
    texte: text?                // Main article text content
  }

  // Concatenate fields with separators, normalizing NULLs to empty strings
  var concatenated = text.concat(fullSectionsTitre ?? "", " | ", surtitre ?? "", " | ", texte ?? "")
  var hash = crypto.hash("sha256", concatenated)

  return hash
}
