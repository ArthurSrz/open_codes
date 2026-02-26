// Fonction: template_extraire_placeholders_docx
// Description: Parse le XML d'un DOCX pour extraire la liste des {{placeholders}}
// Input: url_docx (text)
// Output: { placeholders: [{id, occurrences}], total: int }
//
// Utilisée lors de l'upload d'un nouveau template pour auto-détecter
// les variables nécessaires et pré-remplir le champ placeholders JSON.

function "templates/template_extraire_placeholders_docx" {
  description = "Extrait la liste des placeholders {{...}} depuis un fichier DOCX"

  input {
    text url_docx {
      description = "URL du fichier DOCX à analyser"
    }
  }

  stack {
    // Extraire le XML du DOCX
    function.run "docx/docx_extraire_xml" {
      input = { url_docx: $input.url_docx }
    } as $extraction

    // Extraire les placeholders via regex
    var $pattern {
      value = "\\{\\{(\\w+)\\}\\}"
    }

    var $matches {
      value = ($extraction.document_xml|regex_match_all:$pattern)
    }

    // Compter les occurrences de chaque placeholder
    var $compteur {
      value = {}
      description = "Map placeholder_id → nombre d'occurrences"
    }

    foreach ($matches) {
      each as $match {
        var $pid {
          value = $match.1
        }
        conditional {
          if ($compteur|has_key:$pid) {
            var.update $compteur {
              value = $compteur|set:$pid:(($compteur|get:$pid) + 1)
            }
          }
          else {
            var.update $compteur {
              value = $compteur|set:$pid:1
            }
          }
        }
      }
    }

    // Construire la liste de résultats
    var $placeholders_list {
      value = []
    }

    foreach ($compteur|entries) {
      each as $entry {
        var.update $placeholders_list {
          value = $placeholders_list|push:{
            id: $entry.key,
            label: ($entry.key|replace:"_":" "|capitalize),
            type: "text",
            required: true,
            occurrences: $entry.value
          }
        }
      }
    }

    var $result {
      value = {
        placeholders: $placeholders_list,
        total: ($placeholders_list|count)
      }
    }
  }

  response = $result
}
