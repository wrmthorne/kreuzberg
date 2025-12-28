# Kreuzberg Elixir Binding - API Reference

Quick reference guide for the Elixir binding implementation.

## Module Organization

```
Kreuzberg
├── Kreuzberg              - Main facade (delegates to specialized APIs)
├── Kreuzberg.BatchAPI     - Batch operations
├── Kreuzberg.AsyncAPI     - Async Task-based operations
├── Kreuzberg.UtilityAPI   - MIME detection, error classification
├── Kreuzberg.CacheAPI     - Cache management
├── Kreuzberg.Validators   - Configuration validators
├── Kreuzberg.Plugin       - Plugin registration/management
├── Kreuzberg.Plugin.Registry      - GenServer registry
├── Kreuzberg.Plugin.Supervisor    - OTP supervisor
├── Kreuzberg.Plugin.PostProcessor - Behaviour
├── Kreuzberg.Plugin.Validator     - Behaviour
├── Kreuzberg.Plugin.OcrBackend    - Behaviour
├── Kreuzberg.Native       - Rustler NIF bindings
├── Kreuzberg.Error        - Custom error exception
├── Kreuzberg.ExtractionConfig - Configuration struct
├── Kreuzberg.ExtractionResult  - Result struct
└── Kreuzberg.Application  - OTP Application
```

## API Functions Quick Reference

### Core Extraction (Kreuzberg)
```elixir
# Binary extraction
{:ok, result} = Kreuzberg.extract(binary, mime_type)
result = Kreuzberg.extract!(binary, mime_type)

# File extraction
{:ok, result} = Kreuzberg.extract_file(path)
{:ok, result} = Kreuzberg.extract_file(path, mime_type)
{:ok, result} = Kreuzberg.extract_file(path, mime_type, config)
result = Kreuzberg.extract_file!(path, mime_type, config)

# With plugins
{:ok, result} = Kreuzberg.extract_with_plugins(
  binary,
  mime_type,
  config,
  validators: [Module1],
  post_processors: %{early: [Module2]},
  final_validators: [Module3]
)
```

### Batch API (Kreuzberg.BatchAPI or Kreuzberg)
```elixir
# Batch file extraction
{:ok, results} = Kreuzberg.batch_extract_files(paths)
{:ok, results} = Kreuzberg.batch_extract_files(paths, mime_type)
{:ok, results} = Kreuzberg.batch_extract_files(paths, mime_type, config)
results = Kreuzberg.batch_extract_files!(paths, mime_type, config)

# Batch binary extraction
{:ok, results} = Kreuzberg.batch_extract_bytes(
  [binary1, binary2, binary3],
  "application/pdf"
)
{:ok, results} = Kreuzberg.batch_extract_bytes(
  [binary1, binary2, binary3],
  ["application/pdf", "text/plain", "image/jpeg"]
)
results = Kreuzberg.batch_extract_bytes!(data_list, mime_types, config)
```

### Async API (Kreuzberg.AsyncAPI or Kreuzberg)
```elixir
# Async extraction
task = Kreuzberg.extract_async(binary, mime_type)
{:ok, result} = Task.await(task)

# Async file extraction
task = Kreuzberg.extract_file_async(path)
task = Kreuzberg.extract_file_async(path, mime_type, config)
{:ok, result} = Task.await(task)

# Batch async operations
task = Kreuzberg.batch_extract_files_async(paths, mime_type)
task = Kreuzberg.batch_extract_bytes_async(data_list, mime_types, config)
{:ok, results} = Task.await(task)

# Multiple concurrent operations
tasks = Enum.map(paths, &Kreuzberg.extract_file_async/1)
results = Task.await_many(tasks)
```

### Utility API (Kreuzberg.UtilityAPI or Kreuzberg)
```elixir
# MIME type detection
{:ok, mime} = Kreuzberg.detect_mime_type(binary_data)
{:ok, mime} = Kreuzberg.detect_mime_type_from_path(path)
{:ok, mime} = Kreuzberg.validate_mime_type("application/pdf")
{:ok, exts} = Kreuzberg.get_extensions_for_mime("application/pdf")

# Embedding presets
{:ok, presets} = Kreuzberg.list_embedding_presets()
{:ok, preset} = Kreuzberg.get_embedding_preset("balanced")

# Error handling
error_atom = Kreuzberg.classify_error("File not found")
{:ok, details} = Kreuzberg.get_error_details()
```

### Cache API (Kreuzberg.CacheAPI or Kreuzberg)
```elixir
# Cache management
{:ok, stats} = Kreuzberg.cache_stats()
stats = Kreuzberg.cache_stats!()

:ok = Kreuzberg.clear_cache()
:ok = Kreuzberg.clear_cache!()
```

### Validators (Kreuzberg.Validators or Kreuzberg)
```elixir
# Configuration validators
:ok = Kreuzberg.validate_chunking_params(%{"max_chars" => 1000, "max_overlap" => 200})
:ok = Kreuzberg.validate_language_code("en")
:ok = Kreuzberg.validate_dpi(300)
:ok = Kreuzberg.validate_confidence(0.8)
:ok = Kreuzberg.validate_ocr_backend("tesseract")
:ok = Kreuzberg.validate_binarization_method("otsu")
:ok = Kreuzberg.validate_tesseract_psm(6)
:ok = Kreuzberg.validate_tesseract_oem(1)
```

### Plugin System (Kreuzberg.Plugin or Kreuzberg.Plugin.*)

#### Post-Processors
```elixir
# Register/unregister
:ok = Kreuzberg.Plugin.register_post_processor(:name, Module)
:ok = Kreuzberg.Plugin.unregister_post_processor(:name)
:ok = Kreuzberg.Plugin.clear_post_processors()
{:ok, list} = Kreuzberg.Plugin.list_post_processors()

# Module interface
defmodule MyApp.CustomProcessor do
  def process(data) do
    {:ok, modified_data}
  end
end
```

#### Validators
```elixir
# Register/unregister
:ok = Kreuzberg.Plugin.register_validator(MyModule)
:ok = Kreuzberg.Plugin.unregister_validator(MyModule)
:ok = Kreuzberg.Plugin.clear_validators()
{:ok, list} = Kreuzberg.Plugin.list_validators()

# Module interface
defmodule MyApp.CustomValidator do
  def validate(data) do
    if valid?(data), do: :ok, else: {:error, "Invalid"}
  end
end
```

#### OCR Backends
```elixir
# Register/unregister
:ok = Kreuzberg.Plugin.register_ocr_backend(MyModule)
:ok = Kreuzberg.Plugin.unregister_ocr_backend(MyModule)
:ok = Kreuzberg.Plugin.clear_ocr_backends()
{:ok, list} = Kreuzberg.Plugin.list_ocr_backends()

# Module interface
defmodule MyApp.CustomOCR do
  def recognize(image_data, language) do
    {:ok, "recognized text"}
  end

  def supported_languages do
    ["en", "de", "fr"]
  end
end
```

## Configuration

### ExtractionConfig Struct
```elixir
config = %Kreuzberg.ExtractionConfig{
  extract_images: true,
  extract_tables: true,
  ocr: %{"enabled" => true, "languages" => ["en"]},
  use_cache: true,
  chunking: %{"max_chars" => 1000, "max_overlap" => 200}
}

# Or use keyword list
config = [
  extract_images: true,
  ocr: %{"enabled" => true}
]

# Or plain map
config = %{
  "extract_images" => true,
  "ocr" => %{"enabled" => true}
}
```

## Return Types

### ExtractionResult Structure
```elixir
%Kreuzberg.ExtractionResult{
  content: "Extracted text...",
  mime_type: "application/pdf",
  metadata: %{...},
  tables: [...],
  detected_languages: ["en"],
  chunks: [...],
  images: [...],
  pages: [...]
}
```

### Error Handling

**Result-based (safe API):**
```elixir
case Kreuzberg.extract(data, mime_type) do
  {:ok, result} -> IO.inspect(result)
  {:error, reason} -> IO.puts("Error: #{reason}")
end
```

**Exception-based (bang API):**
```elixir
try do
  result = Kreuzberg.extract!(data, mime_type)
  IO.inspect(result)
rescue
  e in Kreuzberg.Error ->
    IO.puts("Error: #{e.message}")
    IO.puts("Reason: #{e.reason}")
end
```

**Error Classification:**
```elixir
error_atom = Kreuzberg.classify_error("File not found")
# => :io_error

error_categories = %{
  io_error: "File I/O errors",
  invalid_format: "Format errors",
  invalid_config: "Configuration errors",
  ocr_error: "OCR processing errors",
  extraction_error: "General extraction failures",
  unknown_error: "Unclassified errors"
}
```

## Test Files Structure

```
test/
├── unit/
│   ├── extraction_test.exs          (Core extraction tests)
│   ├── file_extraction_test.exs     (File-specific tests)
│   ├── batch_api_test.exs           (Batch operation tests)
│   ├── async_api_test.exs           (Async operation tests)
│   ├── cache_api_test.exs           (Cache management tests)
│   ├── utility_api_test.exs         (Utility function tests)
│   ├── validators_test.exs          (Validation tests)
│   └── plugin_system_test.exs       (Plugin system tests)
├── format/
│   ├── pdf_extraction_test.exs      (PDF-specific tests)
│   └── file_extraction_test.exs     (File format tests)
├── support/
│   ├── test_fixtures.exs            (Test data)
│   ├── document_fixtures.exs        (Document samples)
│   ├── document_paths.exs           (Path constants)
│   ├── assertions.exs               (Test helpers)
│   ├── example_post_processor.ex    (Mock processor)
│   ├── example_validator.ex         (Mock validator)
│   └── example_ocr_backend.ex       (Mock OCR)
├── test_helper.exs                  (Setup)
└── kreuzberg_test.exs               (Integration tests)
```

## Common Patterns

### Single Document Extraction
```elixir
def extract_document(path) do
  case Kreuzberg.extract_file(path, "application/pdf") do
    {:ok, result} -> {:ok, result.content}
    {:error, reason} -> {:error, reason}
  end
end
```

### Batch Processing with Error Handling
```elixir
def process_many_files(paths) do
  case Kreuzberg.batch_extract_files(paths, "application/pdf") do
    {:ok, results} ->
      Enum.map(results, &extract_pages/1)
    {:error, reason} ->
      {:error, "Batch extraction failed: #{reason}"}
  end
end
```

### Concurrent Processing
```elixir
def extract_concurrently(paths) do
  paths
  |> Enum.map(&Kreuzberg.extract_file_async/1)
  |> Task.await_many(timeout: 30_000)
  |> Enum.zip(paths)
end
```

### With Configuration
```elixir
def extract_with_ocr(path) do
  config = %Kreuzberg.ExtractionConfig{
    ocr: %{"enabled" => true, "languages" => ["en", "de"]},
    extract_images: true
  }
  Kreuzberg.extract_file(path, nil, config)
end
```

### Plugin-based Processing
```elixir
def extract_with_plugins(data, mime_type) do
  Kreuzberg.extract_with_plugins(
    data,
    mime_type,
    nil,
    validators: [MyApp.InputValidator],
    post_processors: %{
      early: [MyApp.TextNormalizer],
      late: [MyApp.LanguageDetector]
    },
    final_validators: [MyApp.OutputValidator]
  )
end
```

### Cache Management
```elixir
def get_cache_info do
  with {:ok, stats} <- Kreuzberg.cache_stats(),
       {:ok, details} <- Kreuzberg.UtilityAPI.get_error_details() do
    {:ok, %{stats: stats, error_categories: details}}
  end
end
```

## File Paths Reference

### Source Implementation
- Main module: `/lib/kreuzberg.ex`
- Batch API: `/lib/kreuzberg/batch_api.ex`
- Async API: `/lib/kreuzberg/async_api.ex`
- Utility API: `/lib/kreuzberg/utility_api.ex`
- Cache API: `/lib/kreuzberg/cache_api.ex`
- Validators: `/lib/kreuzberg/validators.ex`
- Plugin System: `/lib/kreuzberg/plugin.ex` and `/lib/kreuzberg/plugin/`

### Test Files
- Unit tests: `/test/unit/`
- Format tests: `/test/format/`
- Support modules: `/test/support/`

### Rust NIF
- Main interface: `/native/kreuzberg_rustler/src/lib.rs`
- Type definitions: `/native/kreuzberg_rustler/src/types.rs`
- Utilities: `/native/kreuzberg_rustler/src/utils.rs`

### Configuration
- Project config: `/mix.exs`
- Rust config: `/Cargo.toml`
- Formatter config: `/.formatter.exs`

## Statistics

- **Total Public Functions**: 65+
- **Total Files**: 39
- **Lines of Code**: ~12,000
- **Test Count**: 615
- **Test Pass Rate**: 99.8%
- **Execution Time**: ~0.3 seconds

## Version Info

- **Elixir**: 1.13+
- **OTP**: 24+
- **Rust**: 1.70+
