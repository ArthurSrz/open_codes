// Function: parser_fullSectionsTitre
// Purpose: Parse PISTE hierarchy path into structured columns (T008)
// Input: fullSectionsTitre string like "Partie législative > Livre I > Titre II > Chapitre III"
// Output: Object with partie, livre, titre, chapitre, section, sous_section, paragraphe
// Used by: piste_sync_code to populate hierarchy columns in REF_codes_legifrance

function parser_fullSectionsTitre {
  input: {
    fullSectionsTitre: text?    // e.g., "Partie législative > Livre I > Titre II > Chapitre III > Section 1"
  }

  // Return empty object if no input
  if fullSectionsTitre == null {
    return {
      partie: null,
      livre: null,
      titre: null,
      chapitre: null,
      section: null,
      sous_section: null,
      paragraphe: null
    }
  }

  // Extract each hierarchy level using regex
  // Pattern "(Level [^>]+)" captures "Level" followed by any chars until ">"
  var partie_match = text.regex_match(fullSectionsTitre, "(Partie [^>]+)")
  var partie = list.length(partie_match) > 0 ? text.trim(partie_match[0]) : null

  // Extract remaining levels (same pattern)
  var livre_match = text.regex_match(fullSectionsTitre, "(Livre [^>]+)")
  var livre = list.length(livre_match) > 0 ? text.trim(livre_match[0]) : null

  var titre_match = text.regex_match(fullSectionsTitre, "(Titre [^>]+)")
  var titre = list.length(titre_match) > 0 ? text.trim(titre_match[0]) : null

  var chapitre_match = text.regex_match(fullSectionsTitre, "(Chapitre [^>]+)")
  var chapitre = list.length(chapitre_match) > 0 ? text.trim(chapitre_match[0]) : null

  var section_match = text.regex_match(fullSectionsTitre, "(Section [^>]+)")
  var section = list.length(section_match) > 0 ? text.trim(section_match[0]) : null

  var sous_section_match = text.regex_match(fullSectionsTitre, "(Sous-section [^>]+)")
  var sous_section = list.length(sous_section_match) > 0 ? text.trim(sous_section_match[0]) : null

  var paragraphe_match = text.regex_match(fullSectionsTitre, "(Paragraphe [^>]+)")
  var paragraphe = list.length(paragraphe_match) > 0 ? text.trim(paragraphe_match[0]) : null

  return {
    partie: partie,
    livre: livre,
    titre: titre,
    chapitre: chapitre,
    section: section,
    sous_section: sous_section,
    paragraphe: paragraphe
  }
}
