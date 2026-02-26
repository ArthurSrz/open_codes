// Fonction: docx_generer_document
// Description: Pipeline complet de génération de document DOCX depuis un template
// Input: template_id (int), donnees (json), utilisateur_id (int), session_id (int)
// Output: { document_id: int, titre: text, statut: text }
//
// Orchestre le pipeline: extraire XML → remplir placeholders → reconstruire DOCX → stocker
// Flat architecture (pas de nested function.run pour éviter le hanging XanoScript)

function "documents/docx_generer_document" {
  description = "Génère un document DOCX complet depuis un template avec les données fournies"

  input {
    int template_id {
      description = "ID du template dans templates_documents_administratifs"
    }
    json donnees {
      description = "Données {placeholder_id: valeur} pour le remplacement"
    }
    int utilisateur_id {
      description = "ID de l'utilisateur qui génère le document"
    }
    int session_id {
      description = "ID de la session de génération"
    }
  }

  stack {
    var $debut_ms {
      value = ("now"|to_ms)
      description = "Timestamp de début pour mesure de durée"
    }

    // 1. Récupérer le template
    db.get "templates_documents_administratifs" {
      field_name = "id"
      field_value = $input.template_id
      description = "Charger le template"
    } as $template

    precondition ($template != null) {
      error_type = "notfound"
      error = "Template non trouvé (ID: " ~ $input.template_id ~ ")"
    }

    precondition ($template.actif == true) {
      error_type = "badrequest"
      error = "Ce template est archivé et ne peut pas être utilisé"
    }

    // 2. Extraire le XML du DOCX template
    // IMPORTANT: Inline les opérations plutôt que function.run nested
    api.request {
      url = $template.fichier_docx.url
      method = "GET"
      description = "Télécharger le fichier DOCX template"
    } as $docx_response

    file.unzip {
      content = $docx_response.response.result
      description = "Décompresser l'archive DOCX/ZIP"
    } as $zip_contents

    // Extraire word/document.xml
    var $document_xml {
      value = ""
    }

    foreach ($zip_contents) {
      each as $file {
        conditional {
          if ($file.name == "word/document.xml") {
            var.update $document_xml {
              value = $file.content
            }
          }
          else {
            // Préserver les autres fichiers
          }
        }
      }
    }

    precondition ($document_xml != "") {
      error_type = "internal"
      error = "Le template DOCX ne contient pas de word/document.xml valide"
    }

    // 3. Remplacer les {{placeholders}}
    var $xml_modifie {
      value = $document_xml
    }

    var $nb_remplaces {
      value = 0
    }

    // Itérer sur chaque donnée et remplacer
    foreach ($input.donnees|entries) {
      each as $entry {
        var $placeholder {
          value = "{{" ~ $entry.key ~ "}}"
        }

        // Échapper les caractères spéciaux XML
        var $valeur_safe {
          value = ($entry.value ~ "")|replace:"&":"&amp;"|replace:"<":"&lt;"|replace:">":"&gt;"
        }

        // Remplacer dans le XML
        var.update $xml_modifie {
          value = $xml_modifie|replace:$placeholder:$valeur_safe
        }

        var.update $nb_remplaces {
          value = $nb_remplaces + 1
        }
      }
    }

    // 4. Reconstruire le DOCX
    var $fichiers_reconstruits {
      value = []
    }

    foreach ($zip_contents) {
      each as $file {
        conditional {
          if ($file.name == "word/document.xml") {
            var.update $fichiers_reconstruits {
              value = $fichiers_reconstruits|push:{
                name: "word/document.xml",
                content: $xml_modifie
              }
            }
          }
          else {
            var.update $fichiers_reconstruits {
              value = $fichiers_reconstruits|push:$file
            }
          }
        }
      }
    }

    file.zip {
      files = $fichiers_reconstruits
      description = "Recréer l'archive DOCX"
    } as $nouveau_docx

    // 5. Générer le titre du document
    var $titre_document {
      value = $template.nom ~ " - " ~ ($input.donnees.commune_nom ?? "Commune") ~ " - " ~ ($input.donnees.date_signature ?? "")
      description = "Titre auto-généré pour le document"
    }

    // 6. Stocker le document dans documents_generes
    db.add documents_generes {
      data = {
        template_id: $input.template_id,
        utilisateur_id: $input.utilisateur_id,
        session_id: $input.session_id,
        titre: $titre_document,
        donnees_substituees: $input.donnees,
        statut: "brouillon",
        fichier_docx: $nouveau_docx,
        created_at: "now"
      }
      description = "Enregistrer le document généré"
    } as $document

    // 7. Créer l'entrée de log
    var $duree_ms {
      value = ((("now"|to_ms) - $debut_ms))|round
    }

    db.add LOG_generation_documents {
      data = {
        document_id: $document.id,
        template_id: $input.template_id,
        utilisateur_id: $input.utilisateur_id,
        session_id: $input.session_id,
        action: "generation",
        statut: "succes",
        placeholders_remplaces: $nb_remplaces,
        duree_ms: $duree_ms,
        created_at: "now"
      }
      description = "Audit log de la génération"
    } as $log

    var $result {
      value = {
        document_id: $document.id,
        titre: $titre_document,
        statut: "brouillon",
        placeholders_remplaces: $nb_remplaces,
        duree_ms: $duree_ms
      }
    }
  }

  response = $result
}
