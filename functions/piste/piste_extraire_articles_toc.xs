// Function: piste_extraire_articles_toc
// Purpose: Recursively extract all article IDs from TOC structure (T014)
// Input: TOC sections array from piste_get_toc
// Output: Flat list of { id, num, section_path } for each article
// Used by: piste_sync_code to enumerate all articles to sync

function piste_extraire_articles_toc {
  input: {
    sections: json            // Array of TOC sections from piste_get_toc
    parent_path: text = ""    // Accumulated section path for hierarchy
  }

  var articles = []

  foreach section in sections {
    // Build current section path
    var current_path = parent_path
    if text.length(parent_path) > 0 {
      current_path = text.concat(parent_path, " > ", section.title ?? "")
    } else {
      current_path = section.title ?? ""
    }

    // Check if this section contains articles
    if section.articles != null {
      foreach article in section.articles {
        list.push(articles, {
          id: article.id,
          num: article.num ?? "",
          section_path: current_path
        })
      }
    }

    // Recursively process child sections
    if section.sections != null && list.length(section.sections) > 0 {
      var child_articles = call piste_extraire_articles_toc(
        sections: section.sections,
        parent_path: current_path
      )
      foreach child in child_articles {
        list.push(articles, child)
      }
    }
  }

  return articles
}
