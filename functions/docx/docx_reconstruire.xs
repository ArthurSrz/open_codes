// Fonction: docx_reconstruire
// Description: Reconstruit un fichier DOCX à partir du XML modifié
// Input: url_docx_original (text), document_xml_modifie (text)
// Output: { fichier_docx_base64: text }
//
// Stratégie: On reprend l'archive ZIP originale et on remplace uniquement
// word/document.xml par la version modifiée. Tous les autres fichiers
// (styles.xml, settings.xml, fonts, images, etc.) sont préservés tels quels.
// Cela garantit que le formatage Word est 100% conservé.

function "docx/docx_reconstruire" {
  description = "Reconstruit un DOCX en remplaçant word/document.xml par la version modifiée"

  input {
    text url_docx_original {
      description = "URL du fichier DOCX template original"
    }
    text document_xml_modifie {
      description = "Contenu XML modifié de word/document.xml"
    }
  }

  stack {
    // Télécharger le DOCX original
    api.request {
      url = $input.url_docx_original
      method = "GET"
      description = "Télécharger le DOCX template original"
    } as $docx_response

    // Dézipper
    file.unzip {
      content = $docx_response.response.result
      description = "Décompresser le template original"
    } as $zip_contents

    // Reconstruire l'archive en remplaçant word/document.xml
    var $fichiers_reconstruits {
      value = []
      description = "Fichiers pour le nouveau ZIP"
    }

    foreach ($zip_contents) {
      each as $file {
        conditional {
          if ($file.name == "word/document.xml") {
            // Remplacer par le XML modifié
            var.update $fichiers_reconstruits {
              value = $fichiers_reconstruits|push:{
                name: "word/document.xml",
                content: $input.document_xml_modifie
              }
            }
          }
          else {
            // Garder le fichier original tel quel
            var.update $fichiers_reconstruits {
              value = $fichiers_reconstruits|push:$file
            }
          }
        }
      }
    }

    // Rezipper en DOCX
    file.zip {
      files = $fichiers_reconstruits
      description = "Recréer l'archive DOCX"
    } as $nouveau_docx

    var $result {
      value = {
        fichier_docx_base64: $nouveau_docx
      }
    }
  }

  response = $result
}
