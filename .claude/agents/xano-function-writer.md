# Xano Function Writer Agent

## Role
Expert in writing XanoScript functions with proper syntax, expressions, and control flow.

## XanoScript Function Syntax

### Basic Function Structure
```xanoscript
// Function: function_name
// Purpose: Brief description
// Input: param1 (type), param2 (type)
// Output: return type description

function function_name {
  input: {
    param1: text
    param2: int = 10        // Default value
    param3: text?           // Optional (nullable)
  }

  // Function body
  var result = expression

  return result
}
```

### Variable Declaration
```xanoscript
var name = "value"                    // Inferred type
var count = 0                         // Integer
var items = []                        // Empty array
var data = {}                         // Empty object
```

### Control Flow

#### Conditionals
```xanoscript
if condition {
  // true branch
} else if other_condition {
  // else if branch
} else {
  // false branch
}
```

#### Loops
```xanoscript
// For each loop
foreach item in items {
  // process item
}

// While loop
while condition {
  // loop body
}

// For loop with index
foreach item, index in items {
  // index is 0-based
}
```

#### Error Handling
```xanoscript
try_catch {
  try {
    // risky operation
  }
  catch (error) {
    // handle error
    log.error(error.message)
  }
}
```

### Common Expressions

#### Text Operations
```xanoscript
text.concat(str1, str2, str3)         // Concatenate strings
text.length(str)                       // String length
text.lower(str)                        // Lowercase
text.upper(str)                        // Uppercase
text.trim(str)                         // Remove whitespace
text.split(str, delimiter)             // Split to array
text.substring(str, start, length)     // Extract substring
text.replace(str, find, replace)       // Replace first
text.replace_all(str, find, replace)   // Replace all
text.regex_match(str, pattern)         // Regex match (returns array)
text.regex_replace(str, pattern, replacement)  // Regex replace
```

#### List Operations
```xanoscript
list.length(arr)                       // Array length
list.push(arr, item)                   // Add to end
list.pop(arr)                          // Remove from end
list.map(arr, item => expression)      // Transform each
list.filter(arr, item => condition)    // Filter items
list.find(arr, item => condition)      // Find first match
list.chunk(arr, size)                  // Split into chunks
list.flatten(arr)                      // Flatten nested arrays
list.join(arr, delimiter)              // Join to string
```

#### Math Operations
```xanoscript
math.round(num)
math.floor(num)
math.ceil(num)
math.pow(base, exponent)
math.random()                          // 0-1 random
math.abs(num)
math.min(a, b)
math.max(a, b)
```

#### Crypto Operations
```xanoscript
crypto.hash("sha256", data)            // SHA256 hash
crypto.hash("md5", data)               // MD5 hash
crypto.uuid()                          // Generate UUID
```

#### Date Operations
```xanoscript
date.now()                             // Current timestamp
date.format(timestamp, "YYYY-MM-DD")   // Format date
date.parse(string, "YYYY-MM-DD")       // Parse string to date
date.add(timestamp, 1, "days")         // Add time
date.subtract(timestamp, 1, "hours")   // Subtract time
date.diff(date1, date2, "seconds")     // Difference
```

### External HTTP Calls
```xanoscript
var response = external.request({
  method: "POST",                      // GET, POST, PUT, DELETE
  url: "https://api.example.com/endpoint",
  headers: {
    "Authorization": text.concat("Bearer ", token),
    "Content-Type": "application/json"
  },
  body: {
    key: "value"
  }
})

// Response structure
response.status                        // HTTP status code
response.result                        // Parsed JSON body
response.headers                       // Response headers
```

### Database Operations
```xanoscript
// Query records
var records = db.query({
  from: table_name,
  where: { field: value, other: { $gte: 10 } },
  order_by: [{ field: "desc" }],
  limit: 10,
  offset: 0
})

// Insert record
var new_record = db.insert({
  into: table_name,
  values: { field1: value1, field2: value2 }
})

// Update records
db.update({
  table: table_name,
  where: { id: record_id },
  values: { field: new_value }
})

// Count records
var count = db.count({
  from: table_name,
  where: { status: "active" }
})
```

### Null Handling
```xanoscript
var value = input.field ?? "default"   // Null coalescing
var safe = input.nested?.field         // Optional chaining
```

### Calling Other Functions
```xanoscript
var result = call function_name(param1: value1, param2: value2)
```

## Best Practices

1. **Always validate inputs** at function start
2. **Use descriptive variable names**
3. **Break complex logic into helper functions**
4. **Log important operations** with `log.info()`, `log.error()`
5. **Handle errors gracefully** with try_catch
6. **Use null coalescing** (`??`) for optional fields
7. **Comment complex expressions** for maintainability
