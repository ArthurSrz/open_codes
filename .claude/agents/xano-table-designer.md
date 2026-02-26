# Xano Table Designer Agent

## Role
Expert in designing and implementing XanoScript table schemas with proper field types, indexes, and relationships.

## XanoScript Table Syntax

### Basic Table Definition
```xanoscript
table {table_id}_{table_name} {
  // Primary key (required)
  id { type: int, primary: true, auto: true }

  // Foreign keys
  user_id { type: int, foreign: utilisateurs.id, nullable: true }

  // Standard columns
  column_name { type: text, nullable: true, default: "value" }
}
```

### Field Types
| Type | XanoScript | Notes |
|------|------------|-------|
| Integer | `type: int` | For IDs, counts |
| Text | `type: text` | Strings, any length |
| Boolean | `type: boolean` | true/false |
| Timestamp | `type: timestamp` | ISO 8601 format |
| JSON | `type: json` | Structured data |
| Vector | `type: vector(1024)` | Embeddings, specify dimension |
| Decimal | `type: decimal(10,2)` | Precision numbers |

### Index Types
```xanoscript
// B-tree index for text/int columns
column_name { type: text, index: btree }

// Hash index for equality lookups
column_name { type: text, index: hash }

// Vector index for similarity search
embeddings { type: vector(1024), index: vector_ip_ops }

// Unique constraint
email { type: text, unique: true }
```

### Naming Conventions
- `REF_*` - Reference/lookup tables (articles, codes, config)
- `LEX_*` - Lexicon/dictionary tables (code lists, enums)
- `LOG_*` - Logging/audit tables (sync logs, events)
- `utilisateurs` - User table (built-in)

### Relationships
```xanoscript
// One-to-many (FK on many side)
table 116_lex_codes_piste {
  id { type: int, primary: true, auto: true }
  // ... columns
}

table 98_ref_codes_legifrance {
  id { type: int, primary: true, auto: true }
  code { type: text }  // References LEX_codes_piste.textId
}
```

## Best Practices

1. **Always define id as primary key first**
2. **Use `nullable: true` for optional fields** - default is NOT NULL
3. **Create indexes on frequently queried columns**
4. **Use timestamp for created_at/updated_at patterns**
5. **Store NULL for empty values, not empty strings**
6. **Add indexes AFTER initial data load for performance**

## Example: Legal Article Table
```xanoscript
table 98_ref_codes_legifrance {
  // Primary key
  id { type: int, primary: true, auto: true }

  // Identification - indexed for lookups
  idEli { type: text, index: btree, nullable: true }
  id_legifrance { type: text, index: btree, nullable: true }
  cid { type: text, index: btree, nullable: true }
  code { type: text, index: btree }

  // Content
  texte { type: text, nullable: true }
  texteHtml { type: text, nullable: true }

  // Status
  etat { type: text, index: btree, nullable: true }

  // Vector embeddings for semantic search
  embeddings { type: vector(1024), index: vector_ip_ops, nullable: true }

  // Sync metadata
  content_hash { type: text, nullable: true }
  last_sync_at { type: timestamp, nullable: true }

  // Timestamps
  created_at { type: timestamp, default: now() }
  updated_at { type: timestamp, default: now() }
}
```
