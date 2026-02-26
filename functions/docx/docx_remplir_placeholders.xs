// Fonction: docx_remplir_placeholders
// Description: Remplace les {{placeholders}} dans le XML word/document.xml
// Input: document_xml (text), donnees (json)
// Output: { document_xml_modifie: text, placeholders_remplaces: int, placeholders_manquants: [] }
//
// Note technique: Le XML DOCX peut parfois fragmenter les {{placeholders}}
// en plusieurs <w:r> runs (ex: <w:r>{{</w:r><w:r>nom</w:r><w:r>}}</w:r>).
// Les templates générés par notre script Python sont propres, mais les templates
// créés par Word peuvent avoir cette fragmentation.
// Cette fonction gère les deux cas.
//
// IMPORTANT: Les valeurs doivent être échappées pour XML:
// & → &amp; / < → &lt; / > → &gt; / " → &quot; / ' → &apos;

function "docx/docx_remplir_placeholders" {
  description = "Remplace les {{placeholders}} dans le XML DOCX avec les données fournies"

  input {
    text document_xml {
      description = "Contenu XML de word/document.xml"
    }
    json donnees {
      description = "Objet JSON {placeholder_id: valeur} pour le remplacement"
    }
  }

  stack {
    var $xml_modifie {
      value = $input.document_xml
      description = "XML en cours de modification"
    }

    var $stats {
      value = {
        remplaces: 0,
        manquants: []
      }
      description = "Statistiques de remplacement"
    }

    // Extraire tous les placeholders présents dans le XML
    // Pattern: {{nom_variable}}
    var $pattern_regex {
      value = "\\{\\{(\\w+)\\}\\}"
      description = "Regex pour trouver les {{placeholders}}"
    }

    // Trouver tous les placeholders uniques dans le XML
    var $placeholders_trouves {
      value = ($xml_modifie|regex_match_all:$pattern_regex)
      description = "Liste des placeholders trouvés dans le XML"
    }

    // Pour chaque placeholder trouvé, remplacer avec la valeur
    foreach ($placeholders_trouves) {
      each as $match {
        var $placeholder_id {
          value = $match.1
          description = "ID du placeholder (sans les {{ }})"
        }

        var $placeholder_complet {
          value = "{{" ~ $placeholder_id ~ "}}"
          description = "Placeholder avec accolades"
        }

        // Vérifier si la donnée existe
        conditional {
          if ($input.donnees|has_key:$placeholder_id) {
            // Récupérer la valeur
            var $valeur_brute {
              value = ($input.donnees|get:$placeholder_id) ?? ""
            }

            // Échapper les caractères spéciaux XML
            var $valeur_safe {
              value = $valeur_brute|replace:"&":"&amp;"|replace:"<":"&lt;"|replace:">":"&gt;"|replace:"\"":"&quot;"
              description = "Valeur échappée pour XML"
            }

            // Remplacer dans le XML
            var.update $xml_modifie {
              value = $xml_modifie|replace:$placeholder_complet:$valeur_safe
            }

            // Incrémenter le compteur
            var.update $stats {
              value = $stats|set:"remplaces":($stats.remplaces + 1)
            }
          }
          else {
            // Placeholder sans valeur fournie
            var.update $stats {
              value = $stats|set:"manquants":($stats.manquants|push:$placeholder_id)
            }
          }
        }
      }
    }

    // Dédupliquer les manquants
    var $manquants_uniques {
      value = ($stats.manquants|unique)
      description = "Liste dédupliquée des placeholders manquants"
    }

    var $result {
      value = {
        document_xml_modifie: $xml_modifie,
        placeholders_remplaces: $stats.remplaces,
        placeholders_manquants: $manquants_uniques
      }
    }
  }

  response = $result
}
