// Fonction: docx_extraire_xml
// Description: Extrait le contenu XML word/document.xml d'un fichier DOCX (qui est un ZIP)
// Input: url_docx (text) - URL du fichier DOCX stocké dans Xano
// Output: { document_xml: text, content_types_xml: text }
//
// Note technique: Un DOCX est une archive ZIP contenant:
//   - word/document.xml (contenu principal avec les {{placeholders}})
//   - word/styles.xml (formatage - à préserver)
//   - [Content_Types].xml
//   - _rels/.rels
//
// Cette fonction extrait word/document.xml pour permettre le remplacement
// des {{placeholders}} puis la reconstruction du DOCX.

function "docx/docx_extraire_xml" {
  description = "Extrait le XML du contenu principal d'un fichier DOCX (archive ZIP)"

  input {
    text url_docx {
      description = "URL du fichier DOCX stocké dans Xano (attachment field)"
    }
  }

  stack {
    // Télécharger le fichier DOCX depuis l'URL Xano
    api.request {
      url = $input.url_docx
      method = "GET"
      description = "Télécharger le fichier DOCX"
    } as $docx_response

    // Décoder le contenu base64 du fichier
    var $docx_base64 {
      value = $docx_response.response.result
      description = "Contenu base64 du fichier DOCX"
    }

    // Dézipper le DOCX (c'est un ZIP)
    file.unzip {
      content = $docx_base64
      description = "Décompresser l'archive DOCX/ZIP"
    } as $zip_contents

    // Extraire word/document.xml (contenu principal)
    var $document_xml {
      value = ""
      description = "Contenu XML du document principal"
    }

    var $all_files {
      value = []
      description = "Liste de tous les fichiers dans le ZIP"
    }

    foreach ($zip_contents) {
      each as $file {
        // Stocker la liste des fichiers
        var.update $all_files {
          value = $all_files|push:$file.name
        }

        // Extraire word/document.xml
        conditional {
          if ($file.name == "word/document.xml") {
            var.update $document_xml {
              value = $file.content
            }
          }
          else {
            // Ignorer les autres fichiers pour l'instant
          }
        }
      }
    }

    // Vérifier que le XML a été trouvé
    precondition ($document_xml != "") {
      error_type = "badrequest"
      error = "Le fichier DOCX ne contient pas de word/document.xml valide"
    }

    // Construire la réponse
    var $result {
      value = {
        document_xml: $document_xml,
        fichiers_zip: $all_files
      }
      description = "Résultat de l'extraction"
    }
  }

  response = $result
}
