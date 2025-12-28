# Kreuzberg Elixir Architecture Diagram

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     User Application                         │
│                                                              │
│  MyApp.process_pdf(pdf_binary)                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  Public API (Kreuzberg)                      │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ extract(binary, mime_type, config?) ──┐             │  │
│  │ extract!(binary, mime_type, config?) ─┤─► Result   │  │
│  │ extract_file(path, mime_type?, config?)│            │  │
│  │ extract_file!(path, mime_type?, config?)│           │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────┬───────────────────────────────────────────┘
                  │
        ┌─────────┴──────────┬──────────────┬──────────────┐
        │                    │              │              │
        ▼                    ▼              ▼              ▼
┌──────────────┐  ┌────────────────┐  ┌─────────┐  ┌─────────┐
│  Validation  │  │ Configuration  │  │ Result  │  │ Error   │
│   Layer      │  │   Handling     │  │ Building│  │Handling │
│              │  │                │  │         │  │         │
│ • Input      │  │ • Struct conv  │  │ • Struct│  │ • Classify
│ • Config     │  │ • Map handling │  │ • Map   │  │ • Context
│ • Guard      │  │ • Validation   │  │ • Norm  │  │ • Format
│   clauses    │  │                │  │         │  │
└──────────────┘  └────────────────┘  └─────────┘  └─────────┘
        │                    │              │              │
        └────────────────────┴──────────────┴──────────────┘
                             │
                    ┌────────▼────────┐
                    │ NIF Layer       │
                    │ (Kreuzberg.     │
                    │  Native)        │
                    │                 │
                    │ • extract/2     │
                    │ • extract_with  │
                    │   _options/3    │
                    │ • extract_file/ │
                    │   2,3           │
                    └────────┬────────┘
                             │
                    ┌────────▼──────────┐
                    │   Rust NIF        │
                    │  (kreuzberg_      │
                    │   rustler)        │
                    │                   │
                    │ • PDF parsing     │
                    │ • Text extraction │
                    │ • OCR processing  │
                    │ • Table detection │
                    │ • Image extract   │
                    └───────────────────┘
```

## Module Dependency Graph

```
User Code
   │
   ▼
┌─────────────────────────────────────┐
│  Kreuzberg (Main Module)            │  ◄─── Public API Entry Point
│  ─────────────────────────────────  │
│  extract/2, extract!/2              │
│  extract_file/2-3, extract_file!/2-3│
└──────┬──────────────┬───────────────┘
       │              │
       │              │
       ▼              ▼
    ┌──────────────────────────────────┐
    │  Kreuzberg.ExtractionConfig      │◄─── Configuration Domain
    │  ──────────────────────────────  │
    │  to_map/1, validate/1            │
    │  (No external dependencies)      │
    └──────────────────────────────────┘
       │
       ▼
    ┌──────────────────────────────────┐
    │  Kreuzberg.Native                │◄─── NIF Boundary
    │  ──────────────────────────────  │
    │  extract/2                       │
    │  extract_with_options/3          │
    │  extract_file/2-3                │
    └──────────────────────────────────┘
       │
       ▼
    ┌──────────────────────────────────┐
    │  Rust NIF Implementation         │
    │  ──────────────────────────────  │
    │  (kreuzberg_rustler crate)       │
    └──────────────────────────────────┘

Also used by Kreuzberg:
    ┌──────────────────────────────────┐
    │  Kreuzberg.ExtractionResult      │◄─── Result Domain
    │  ──────────────────────────────  │
    │  new/2-5                         │
    │  (No external dependencies)      │
    └──────────────────────────────────┘

    ┌──────────────────────────────────┐
    │  Kreuzberg.Error                 │◄─── Error Domain
    │  ──────────────────────────────  │
    │  new/2-3, to_string/1            │
    │  (No external dependencies)      │
    └──────────────────────────────────┘

Recommended additions:

    ┌──────────────────────────────────┐
    │  Kreuzberg.ConfigPreset          │◄─── Presets
    │  ──────────────────────────────  │
    │  standard/0, high_quality/0      │
    │  fast/0, ocr_optimized/0, etc    │
    │  Depends on: ExtractionConfig    │
    └──────────────────────────────────┘

    ┌──────────────────────────────────┐
    │  Kreuzberg.ResultProcessing      │◄─── Result Utilities
    │  ──────────────────────────────  │
    │  summarize/1, filter_chunks/2    │
    │  get_metadata/1, etc             │
    │  Depends on: ExtractionResult    │
    └──────────────────────────────────┘
```

## Data Flow Diagram

### Happy Path: Binary Extraction

```
Input: binary data + mime_type + optional_config
│
▼
┌─────────────────────────────────────┐
│  Kreuzberg.extract/3                │
│  ├─ Validate input (not empty)     │
│  ├─ Validate config (if provided)   │
│  └─ Start timer for context         │
└─────────────────────────────────────┘
│
▼
┌─────────────────────────────────────┐
│  call_native/3                      │
│  ├─ If config is nil:               │
│  │  └─ Native.extract/2             │
│  └─ Else:                           │
│     ├─ Convert config to map        │
│     └─ Native.extract_with_options/3│
└─────────────────────────────────────┘
│
▼
┌─────────────────────────────────────┐
│  Rust/NIF Processing                │
│  ├─ Parse document                  │
│  ├─ Extract text                    │
│  ├─ Optional: OCR processing        │
│  ├─ Optional: Language detection    │
│  ├─ Extract metadata/tables/images  │
│  └─ Return result map               │
└─────────────────────────────────────┘
│
▼
┌─────────────────────────────────────┐
│  Result Processing                  │
│  ├─ Validate result structure       │
│  ├─ Normalize map keys              │
│  └─ Build ExtractionResult struct   │
└─────────────────────────────────────┘
│
▼
┌─────────────────────────────────────┐
│  Return {:ok, ExtractionResult}     │
└─────────────────────────────────────┘

User code:
{:ok, result} = Kreuzberg.extract(pdf_binary, "application/pdf")
result.content  # The extracted text
```

### Error Path: Validation Failure

```
Input: invalid_binary or invalid_config
│
▼
┌─────────────────────────────────────┐
│  Kreuzberg.extract/3                │
│  ├─ Validate input                  │
│  │  └─ ❌ Input is empty            │
│  └─ Return error immediately        │
└─────────────────────────────────────┘
│
▼
┌─────────────────────────────────────┐
│  build_error/3                      │
│  ├─ Classify error reason           │
│  ├─ Collect context:                │
│  │  ├─ input_size                   │
│  │  ├─ mime_type                    │
│  │  ├─ timestamp                    │
│  │  └─ elapsed_ms                   │
│  └─ Create Error struct             │
└─────────────────────────────────────┘
│
▼
┌─────────────────────────────────────┐
│  Return {:error, reason}            │
│  or                                 │
│  Raise Error (for extract!/2)       │
└─────────────────────────────────────┘

User code:
case Kreuzberg.extract("", "text/plain") do
  {:ok, result} -> ...
  {:error, reason} ->
    Logger.error("Extraction failed", reason: reason)
end
```

## Configuration Processing Pipeline

```
User Input (one of these):
│
├─ %ExtractionConfig{...} (struct)
├─ %{"use_cache" => true, ...} (map)
├─ [use_cache: true, ...] (keyword list)
└─ nil (use defaults)
│
▼
┌─────────────────────────────────────┐
│  ExtractionConfig.to_map/1          │
│  (handles all input types)          │
└─────────────────────────────────────┘
│
▼
┌─────────────────────────────────────┐
│  Configuration map                  │
│  %{                                 │
│    "use_cache" => boolean,          │
│    "enable_quality_processing" =>   │
│    boolean,                         │
│    "force_ocr" => boolean,          │
│    "ocr" => map | nil,              │
│    "chunking" => map | nil,         │
│    ... other options ...            │
│  }                                  │
└─────────────────────────────────────┘
│
▼
┌─────────────────────────────────────┐
│  Native.extract_with_options/3      │
│  (passes to Rust)                   │
└─────────────────────────────────────┘
│
▼
Rust Implementation
```

## Result Construction Flow

```
NIF Result: %{
  "content" => "extracted text",
  "mime_type" => "application/pdf",
  "metadata" => %{...},
  "tables" => [...],
  "detected_languages" => ["en"],
  "chunks" => nil,
  "images" => nil,
  "pages" => nil,
  # May have atom keys too!
}
│
▼
┌─────────────────────────────────────┐
│  normalize_map_keys/1               │
│  Convert atom keys to strings:      │
│  :content → "content"               │
│  :mime_type → "mime_type"           │
└─────────────────────────────────────┘
│
▼
┌─────────────────────────────────────┐
│  validate_result_structure/1        │
│  ✓ Check required fields present    │
│  ✓ Check required fields not nil    │
│  Return :ok or error                │
└─────────────────────────────────────┘
│
▼
┌─────────────────────────────────────┐
│  ExtractionResult struct            │
│  %ExtractionResult{                 │
│    content: "text",                 │
│    mime_type: "application/pdf",    │
│    metadata: %{...},                │
│    tables: [...],                   │
│    detected_languages: ["en"],      │
│    chunks: nil,                     │
│    images: nil,                     │
│    pages: nil                       │
│  }                                  │
└─────────────────────────────────────┘
│
▼
Return to User
```

## Error Classification Pipeline

### Current Approach (String-based)

```
Error from Rust: "File not found at /tmp/doc.pdf"
│
▼
┌─────────────────────────────────────┐
│  classify_error/1                   │
│  (String pattern matching)          │
│                                     │
│  if contains "file":                │
│    → :io_error                      │
│  if contains "format":              │
│    → :invalid_format                │
│  ...                                │
│  else:                              │
│    → :extraction_error              │
└─────────────────────────────────────┘
│
▼
Error reason: :io_error
│
Problems:
  ✗ Fragile - depends on error message text
  ✗ False positives - "formatting error" matches "format"
  ✗ False negatives - message change = miscategorization
  ✗ Doesn't scale - more reasons = more patterns
```

### Recommended Approach (Structured Codes)

```
Error from Rust: {error_code: 0, message: "File not found at /tmp/doc.pdf"}
│
▼
┌─────────────────────────────────────┐
│  code_to_reason/1                   │
│  (Direct integer mapping)           │
│                                     │
│  case error_code do                 │
│    0 → :io_error                    │
│    1 → :invalid_format              │
│    2 → :invalid_config              │
│    ...                              │
│    -1 → :unknown_error              │
│  end                                │
└─────────────────────────────────────┘
│
▼
Error reason: :io_error
│
Benefits:
  ✓ Reliable - fixed mapping
  ✓ No false positives/negatives
  ✓ Message-independent
  ✓ Scales easily - just add codes
  ✓ Version-aware - can be updated
```

## Integration Points & Boundaries

### Elixir ↔ Rust Boundary

```
┌─────────────────────────────────┐
│     Elixir World                │
│  • Variables are immutable      │
│  • Errors are values            │
│  • Strings are UTF-8 binaries   │
│  • Pattern matching everywhere  │
│  • Type spec documentation      │
└───────────────┬─────────────────┘
                │
     ┌──────────▼──────────┐
     │  Rustler NIF        │
     │  ─────────────────  │
     │  Binary encoding    │
     │  Type marshalling   │
     │  Error translation  │
     └──────────┬──────────┘
                │
┌───────────────▼──────────────┐
│     Rust World               │
│  • Heap-allocated strings    │
│  • Result types              │
│  • Pattern matching          │
│  • No garbage collection     │
│  • System-level operations   │
└──────────────────────────────┘
```

### Data Type Mappings

```
Elixir → Rust
─────────────────────────────────
binary() → Vec<u8>
String.t() → String
map() → HashMap
list() → Vec
true/false → bool
nil → Option::None
{:ok, x} → Result::Ok(x)
{:error, x} → Result::Err(x)
```

## Proposed Architecture Enhancements

### Add: Configuration Builder

```
                    ┌────────────────┐
                    │ User Code      │
                    └────────┬───────┘
                             │
                    ┌────────▼────────┐
                    │ConfigBuilder    │
                    │.with_ocr()      │
                    │.with_chunking() │
                    │.build()         │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ExtractionConfig │
                    │struct           │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │Kreuzberg.extract│
                    └─────────────────┘
```

### Add: Result Processing Pipeline

```
ExtractionResult
    │
    ├─ summarize() ──────────► Document summary
    │
    ├─ filter_chunks() ──────► Filtered chunks
    │
    ├─ get_metadata() ───────► Metadata map
    │
    ├─ get_tables() ─────────► Tables list
    │
    └─ get_images() ─────────► Images list
```

### Add: Extraction Strategies

```
ExtractionStrategy (protocol)
    │
    ├─ Standard
    │
    ├─ OCROptimized
    │
    ├─ HighThroughput
    │
    └─ Custom
```

## File Size & Complexity

```
Kreuzberg.ex                  195 lines    ████░ Medium complexity
├─ Public API functions
├─ Validation logic
├─ NIF call routing
└─ Result transformation

ExtractionConfig.ex           328 lines    ████░ Medium
├─ Configuration struct
├─ Conversion functions
└─ Validation

Error.ex                      150 lines    ███░░ Low
├─ Exception struct
├─ Helper functions
└─ Formatting

ExtractionResult.ex           120 lines    ███░░ Low
├─ Result struct
└─ Constructor

Native.ex                      21 lines    ░░░░░ Very Low
└─ NIF stubs
```

## Testing Coverage Map

```
Kreuzberg (Public API)
├─ extract/2 ───┬─ Success paths ───── 8 tests
│               ├─ Error paths ──────── 6 tests
│               └─ Config variations – 12 tests
│
├─ extract!/2 ──┬─ Success paths ───── 5 tests
│               └─ Exception handling ─ 3 tests
│
├─ extract_file/3 ┬─ File operations ─ 12 tests
│                 ├─ Path handling ─── 6 tests
│                 └─ MIME detection ── 4 tests
│
└─ extract_file!/3 ┬─ Exceptions ──── 5 tests
                   └─ File errors ──── 4 tests

ExtractionConfig
├─ to_map() ────── 5 tests
└─ validate() ──── 8 tests

Total: 78 unit tests + integration tests
```

---

This diagram set provides:
- High-level architecture overview
- Detailed data flow diagrams
- Module dependency relationships
- Error handling paths
- Configuration pipeline
- Proposed enhancements
- File metrics
- Testing coverage map

Use these diagrams to understand the system architecture and communication with the team about design changes.
