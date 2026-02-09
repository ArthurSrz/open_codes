// API: Générer le document final
// Endpoint: POST /api/doc_generator/generer_document_final
// Auth: JWT utilisateurs
// Description: Fusionne les données auto-fill + collectées, génère le DOCX final
//   via le pipeline inline two-copy pattern
//   DOCX = ZIP: .docx for reading, .zip for writing
//   object.entries returns {key, value} objects (NOT arrays)
//   storage.create_attachment needed to persist file for DB

query "doc_generator/generer_document_final" verb=POST {
  api_group = "Doc Generator"
  auth = "utilisateurs"

  input {
    int session_id
  }

  stack {
    var $debut_ms {
      value = "now"|to_ms
    }

    db.get sessions_generation_documents {
      field_name = "id"
      field_value = $input.session_id
    } as $session

    precondition ($session != null) {
      error_type = "notfound"
      error = "Session non trouvée"
    }

    precondition ($session.utilisateur_id == $auth.id) {
      error_type = "accessdenied"
      error = "Cette session ne vous appartient pas"
    }

    db.get templates_documents_administratifs {
      field_name = "id"
      field_value = $session.template_id
    } as $template

    db.get utilisateurs {
      field_name = "id"
      field_value = $auth.id
    } as $user

    db.get communes {
      field_name = "id"
      field_value = $user.commune_id
    } as $commune

    // Fusionner données collectées + auto-fill
    var $donnees_completes {
      value = $session.donnees_collectees
        |set:"commune_nom":$commune.denomination ?? ""
        |set:"departement_nom":$commune.nom_dep ?? ""
        |set:"maire_nom":$commune.maire_nom ?? ""
        |set:"tribunal_administratif":$commune.tribunal_administratif ?? ""
    }

    var $date_sig {
      value = now|format_timestamp:"d/m/Y"
    }

    var.update $donnees_completes {
      value = $donnees_completes|set:"date_signature":$date_sig
    }

    // === DOCX PIPELINE (two-copy pattern) ===
    // 1. Download template
    api.request {
      url = $template.fichier_docx.url
      method = "GET"
    } as $docx_dl

    // 2. Create two copies: .docx for reading, .zip for writing
    storage.create_file_resource {
      filename = "read_copy.docx"
      filedata = $docx_dl.response.result
    } as $read_copy

    storage.create_file_resource {
      filename = "output.zip"
      filedata = $docx_dl.response.result
    } as $output_copy

    // 3. Extract and read document.xml
    zip.extract {
      zip = $read_copy
      password = ""
    } as $extracted_files

    var $document_xml {
      value = ""
    }

    foreach ($extracted_files) {
      each as $f {
        conditional {
          if ($f.name == "word/document.xml") {
            storage.read_file_resource {
              value = $f.resource
            } as $read_result

            var.update $document_xml {
              value = $read_result.data
            }
          }

          else {
            // skip
          }
        }
      }
    }

    // 4. Replace placeholders (object.entries returns {key, value} objects)
    var $xml_modifie {
      value = $document_xml
    }

    var $nb_remplaces {
      value = 0
    }

    object.entries {
      value = $donnees_completes
    } as $donnees_entries

    foreach ($donnees_entries) {
      each as $e {
        var $ph_tag {
          value = "{{" ~ $e.key ~ "}}"
        }

        var $val_safe {
          value = ($e.value ~ "")|replace:"&":"&amp;"|replace:"<":"&lt;"|replace:">":"&gt;"
        }

        var $xml_avant {
          value = $xml_modifie
        }

        var.update $xml_modifie {
          value = $xml_modifie|replace:$ph_tag:$val_safe
        }

        conditional {
          if ($xml_avant != $xml_modifie) {
            var.update $nb_remplaces {
              value = $nb_remplaces + 1
            }
          }

          else {
            // no match
          }
        }
      }
    }

    // 5. Rebuild DOCX: delete old XML, add modified XML
    zip.delete_from_archive {
      filename = "word/document.xml"
      zip = $output_copy
      password = ""
    }

    storage.create_file_resource {
      filename = "document.xml"
      filedata = $xml_modifie
    } as $xml_file

    zip.add_to_archive {
      file = $xml_file
      filename = "word/document.xml"
      zip = $output_copy
      password = ""
      password_encryption = ""
    }

    // 6. Convert file resource to persistent attachment
    storage.create_attachment {
      value = $output_copy
      access = "public"
      filename = "document_genere.docx"
    } as $docx_attachment

    // 7. Save document
    var $titre {
      value = $template.nom ~ " - " ~ ($commune.denomination ?? "") ~ " - " ~ $date_sig
    }

    db.add documents_generes {
      data = {
        template_id        : $session.template_id
        utilisateur_id     : $auth.id
        session_id         : $session.id
        communes_id        : $user.commune_id
        titre              : $titre
        donnees_substituees: $donnees_completes
        statut             : "brouillon"
        fichier_docx       : $docx_attachment
        created_at         : "now"
      }
    } as $document

    db.edit sessions_generation_documents {
      field_name = "id"
      field_value = $session.id
      data = {statut: "termine", document_id: $document.id}
    } as $session_maj

    var $duree_ms {
      value = ((("now"|to_ms) - $debut_ms))|round
    }

    db.add LOG_generation_documents {
      data = {
        document_id           : $document.id
        template_id           : $session.template_id
        utilisateur_id        : $auth.id
        session_id            : $session.id
        action_type           : "generation"
        statut                : "succes"
        placeholders_remplaces: $nb_remplaces
        duree_ms              : $duree_ms
        created_at            : "now"
      }
    } as $log

    var $result {
      value = {
        document_id           : $document.id
        titre                 : $titre
        statut                : "brouillon"
        placeholders_remplaces: $nb_remplaces
        duree_ms              : $duree_ms
      }
    }
  }

  response = $result
}
