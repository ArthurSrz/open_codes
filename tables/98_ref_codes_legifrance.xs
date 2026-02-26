// Table: REF_codes_legifrance
// Purpose: Store French legal code articles with Mistral AI embeddings for semantic search
// Extends existing table with 30 new columns per data-model.md specification
// Maps to ontology entity: ArticleLegifrance

table 98_ref_codes_legifrance {
  // ═══════════════════════════════════════════════════════════════════════════
  // PRIMARY KEY
  // ═══════════════════════════════════════════════════════════════════════════
  id { type: int, primary: true, auto: true }

  // ═══════════════════════════════════════════════════════════════════════════
  // IDENTIFICATION (7 fields)
  // Source: PISTE API /getArticle response
  // ═══════════════════════════════════════════════════════════════════════════
  id_legifrance { type: text, index: btree, nullable: true }   // LEGIARTI000...
  num { type: text, nullable: true }                            // Article number (e.g., "L.123-1")
  cid { type: text, index: btree, nullable: true }              // Consolidated ID
  idEli { type: text, index: btree, nullable: true }            // European Legislation Identifier
  idEliAlias { type: text, nullable: true }                     // Alternative ELI
  idTexte { type: text, nullable: true }                        // Parent text ID
  cidTexte { type: text, nullable: true }                       // Parent consolidated text ID
  code { type: text, index: btree }                             // Code textId (LEGITEXT...)

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTENT (6 fields)
  // Both plain text and HTML stored per EF-011 (dual format)
  // ═══════════════════════════════════════════════════════════════════════════
  texte { type: text, nullable: true }                          // Plain text content
  texteHtml { type: text, nullable: true }                      // HTML formatted content
  nota { type: text, nullable: true }                           // Notes (plain)
  notaHtml { type: text, nullable: true }                       // Notes (HTML)
  surtitre { type: text, nullable: true }                       // Subtitle/header
  historique { type: text, nullable: true }                     // Article history

  // ═══════════════════════════════════════════════════════════════════════════
  // TEMPORALITY (4 fields)
  // ═══════════════════════════════════════════════════════════════════════════
  dateDebut { type: timestamp, nullable: true }                 // Effective start date
  dateFin { type: timestamp, nullable: true }                   // Effective end date
  dateDebutExtension { type: timestamp, nullable: true }        // Extension start
  dateFinExtension { type: timestamp, nullable: true }          // Extension end

  // ═══════════════════════════════════════════════════════════════════════════
  // LEGAL STATUS (4 fields)
  // ═══════════════════════════════════════════════════════════════════════════
  etat { type: text, index: btree, nullable: true }             // VIGUEUR, ABROGE, etc.
  type_article { type: text, nullable: true }                   // Article type
  nature { type: text, nullable: true }                         // Legal nature
  origine { type: text, nullable: true }                        // Origin

  // ═══════════════════════════════════════════════════════════════════════════
  // VERSIONING (3 fields)
  // ═══════════════════════════════════════════════════════════════════════════
  version_article { type: text, nullable: true }                // Version identifier
  versionPrecedente { type: text, nullable: true }              // Previous version ID
  multipleVersions { type: boolean, default: false }            // Has multiple versions flag

  // ═══════════════════════════════════════════════════════════════════════════
  // HIERARCHY (5 fields)
  // Parsed from fullSectionsTitre for structured navigation
  // ═══════════════════════════════════════════════════════════════════════════
  sectionParentId { type: text, nullable: true }                // Parent section ID
  sectionParentCid { type: text, nullable: true }               // Parent section CID
  sectionParentTitre { type: text, nullable: true }             // Parent section title
  fullSectionsTitre { type: text, nullable: true }              // Full hierarchy path
  ordre { type: int, nullable: true }                           // Sort order within section

  // Derived hierarchy columns (parsed from fullSectionsTitre)
  partie { type: text, nullable: true }
  livre { type: text, nullable: true }
  titre { type: text, nullable: true }
  chapitre { type: text, nullable: true }
  section { type: text, nullable: true }
  sous_section { type: text, nullable: true }
  paragraphe { type: text, nullable: true }

  // ═══════════════════════════════════════════════════════════════════════════
  // TECHNICAL METADATA (4 fields)
  // ═══════════════════════════════════════════════════════════════════════════
  idTechInjection { type: text, nullable: true }
  refInjection { type: text, nullable: true }
  numeroBo { type: text, nullable: true }
  inap { type: text, nullable: true }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPLEMENTARY INFO (7 fields)
  // ═══════════════════════════════════════════════════════════════════════════
  infosComplementaires { type: text, nullable: true }
  infosComplementairesHtml { type: text, nullable: true }
  conditionDiffere { type: text, nullable: true }
  infosRestructurationBranche { type: text, nullable: true }
  infosRestructurationBrancheHtml { type: text, nullable: true }
  renvoi { type: text, nullable: true }
  comporteLiensSP { type: boolean, default: false }

  // ═══════════════════════════════════════════════════════════════════════════
  // VECTOR EMBEDDINGS
  // 1024-dim Mistral AI embeddings for semantic search (EF-003)
  // ═══════════════════════════════════════════════════════════════════════════
  embeddings { type: vector(1024), index: vector_ip_ops, nullable: true }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC METADATA
  // For incremental sync and change detection (EF-005)
  // ═══════════════════════════════════════════════════════════════════════════
  content_hash { type: text, nullable: true }        // SHA256 of content for change detection
  last_sync_at { type: timestamp, nullable: true }   // Last successful sync timestamp

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMESTAMPS
  // ═══════════════════════════════════════════════════════════════════════════
  created_at { type: timestamp, default: now() }
  updated_at { type: timestamp, default: now() }
}
