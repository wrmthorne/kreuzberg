# Kreuzberg Elixir - Architecture Recommendations with Code Examples

This document provides concrete implementation examples for the architectural improvements recommended in ARCHITECTURE_REVIEW_ROUND_2.md.

---

## 1. Critical: Structured Error Codes (Tier 1)

### Problem

Current string-based error classification is brittle:

```elixir
# Current approach - FRAGILE
defp classify_error(reason) when is_binary(reason) do
  cond do
    String.contains?(reason, ["io", "file", "not found"]) -> :io_error
    String.contains?(reason, ["invalid", "unsupported"]) -> :invalid_format
    true -> :extraction_error
  end
end
```

### Solution: Structured Error Codes from Rust

#### Phase 1: Update NIF Contract

**Rust side changes needed:**

```rust
// Before
NifError::to_string() -> String

// After
enum ErrorCode {
    IoError,
    InvalidFormat,
    InvalidConfig,
    OcrError,
    ExtractionError,
    NifError,
    Unknown,
}

// Returns: (error_code: i32, error_message: String)
fn error_code_value(code: ErrorCode) -> i32 { ... }
```

#### Phase 2: Update Elixir NIF Binding

**File:** `/Users/naamanhirschfeld/workspace/kreuzberg-dev/worktrees/feat-elixir/packages/elixir/lib/kreuzberg/native.ex`

```elixir
defmodule Kreuzberg.Native do
  @moduledoc """
  Native Interface to Kreuzberg Rust implementation.

  NIF functions return structured results with error codes for reliable
  error classification.

  ## Error Codes

  All NIF functions return:
    {:ok, result_map}
    {:error, {error_code, error_message}}

  where error_code is one of:
    0 - IO_ERROR
    1 - INVALID_FORMAT
    2 - INVALID_CONFIG
    3 - OCR_ERROR
    4 - EXTRACTION_ERROR
    5 - NIF_ERROR
    -1 - UNKNOWN
  """

  use Rustler,
    otp_app: :kreuzberg,
    crate: "kreuzberg_rustler",
    mode: if(Mix.env() == :prod, do: :release, else: :debug)

  @error_code_io 0
  @error_code_invalid_format 1
  @error_code_invalid_config 2
  @error_code_ocr 3
  @error_code_extraction 4
  @error_code_nif 5
  @error_code_unknown -1

  def extract(_input, _input_type), do: :erlang.nif_error(:nif_not_loaded)
  def extract_with_options(_input, _input_type, _options), do: :erlang.nif_error(:nif_not_loaded)
  def extract_file(_path, _mime_type), do: :erlang.nif_error(:nif_not_loaded)
  def extract_file_with_options(_path, _mime_type, _options), do: :erlang.nif_error(:nif_not_loaded)
end
```

#### Phase 3: Update Kreuzberg Module

**File:** `/Users/naamanhirschfeld/workspace/kreuzberg-dev/worktrees/feat-elixir/packages/elixir/lib/kreuzberg.ex`

```elixir
def extract(input, mime_type, config \\ nil) when is_binary(input) and is_binary(mime_type) do
  case call_native(input, mime_type, config) do
    {:ok, result_map} ->
      {:ok, into_result(result_map)}

    {:error, {error_code, reason}} ->
      # Structured error from Rust - reliable classification
      {:error, build_error(reason, error_code, %{
        "input_size" => byte_size(input),
        "mime_type" => mime_type
      })}

    {:error, reason} when is_binary(reason) ->
      # Fallback for legacy Rust versions
      {:error, build_error(reason, classify_error_legacy(reason), %{
        "input_size" => byte_size(input),
        "mime_type" => mime_type
      })}
  end
end

defp build_error(message, error_code, context) do
  reason = code_to_reason(error_code)
  raise Error, message: message, reason: reason, context: context
end

defp code_to_reason(code) do
  case code do
    0 -> :io_error
    1 -> :invalid_format
    2 -> :invalid_config
    3 -> :ocr_error
    4 -> :extraction_error
    5 -> :nif_error
    -1 -> :unknown_error
    _ -> :unknown_error
  end
end

# Legacy fallback for old Rust versions
defp classify_error_legacy(reason) do
  cond do
    String.contains?(reason, ["io", "file", "not found"]) -> 0
    String.contains?(reason, ["invalid", "unsupported"]) -> 1
    String.contains?(reason, ["config"]) -> 2
    String.contains?(reason, ["ocr"]) -> 3
    true -> -1
  end
end
```

---

## 2. Critical: NIF Result Validation (Tier 1)

### Problem

Current `into_result/1` silently creates nil values if Rust returns unexpected structure:

```elixir
# Current - UNSAFE
defp into_result(map) when is_map(map) do
  normalized = normalize_map_keys(map)
  %ExtractionResult{
    content: normalized["content"],  # nil if missing!
    # ...
  }
end
```

### Solution: Validate Result Structure

**File:** `/Users/naamanhirschfeld/workspace/kreuzberg-dev/worktrees/feat-elixir/packages/elixir/lib/kreuzberg.ex`

```elixir
defp into_result(map) when is_map(map) do
  normalized = normalize_map_keys(map)

  with :ok <- validate_result_structure(normalized) do
    %ExtractionResult{
      content: normalized["content"],
      mime_type: normalized["mime_type"],
      metadata: normalized["metadata"] || %{},
      tables: normalized["tables"] || [],
      detected_languages: normalized["detected_languages"],
      chunks: normalized["chunks"],
      images: normalized["images"],
      pages: normalized["pages"]
    }
  end
end

@doc false
defp validate_result_structure(map) do
  required_fields = ["content", "mime_type", "metadata", "tables"]

  case Enum.find(required_fields, fn field ->
    !Map.has_key?(map, field) or is_nil(map[field])
  end) do
    nil ->
      :ok

    missing_field ->
      {:error, :invalid_nif_result,
        "NIF returned incomplete result, missing field: #{missing_field}"}
  end
end

# Use in extract/2 like this:
def extract(input, mime_type, config \\ nil) when is_binary(input) and is_binary(mime_type) do
  case call_native(input, mime_type, config) do
    {:ok, result_map} ->
      case into_result(result_map) do
        %ExtractionResult{} = result ->
          {:ok, result}

        {:error, _reason, _message} = error ->
          error
      end

    {:error, _reason} = err ->
      err
  end
end
```

---

## 3. Critical: Integrated Config Validation (Tier 1)

### Problem

`ExtractionConfig.validate/1` exists but isn't used by public API:

```elixir
# Current - validation not used
def extract(input, mime_type, config \\ nil) do
  case call_native(input, mime_type, config) do
    # No validation before calling native!
  end
end
```

### Solution: Integrate Validation into Call Path

**File:** `/Users/naamanhirschfeld/workspace/kreuzberg-dev/worktrees/feat-elixir/packages/elixir/lib/kreuzberg.ex`

```elixir
def extract(input, mime_type, config \\ nil) when is_binary(input) and is_binary(mime_type) do
  with :ok <- validate_input(input),
       {:ok, validated_config} <- validate_config(config),
       {:ok, result_map} <- call_native(input, mime_type, validated_config) do
    {:ok, into_result(result_map)}
  else
    {:error, _reason} = err -> err
  end
end

def extract!(input, mime_type, config \\ nil) do
  case extract(input, mime_type, config) do
    {:ok, result} ->
      result

    {:error, reason} ->
      error = build_error_from_validation(reason)
      raise error
  end
end

@doc false
defp validate_input(input) when byte_size(input) > 0, do: :ok
defp validate_input(_input), do: {:error, "Input cannot be empty"}

@doc false
defp validate_config(nil), do: {:ok, nil}

defp validate_config(config) when is_struct(config, ExtractionConfig) do
  ExtractionConfig.validate(config)
end

defp validate_config(config) when is_map(config) do
  # Convert to struct for validation
  case Map.to_list(config) |> Map.new() |> as_extraction_config() do
    {:ok, struct} -> ExtractionConfig.validate(struct)
    {:error, reason} -> {:error, reason}
  end
end

defp validate_config(config) when is_list(config) do
  validate_config(Map.new(config))
end

defp validate_config(_invalid) do
  {:error, "Config must be a struct, map, or keyword list"}
end

defp as_extraction_config(map) do
  try do
    {:ok, struct(ExtractionConfig, map)}
  rescue
    ArgumentError -> {:error, "Invalid configuration structure"}
  end
end

@doc false
defp build_error_from_validation(reason) when is_binary(reason) do
  Error.new(reason, :invalid_config)
end
```

Also update `ExtractionConfig.validate/1` to be more helpful:

**File:** `/Users/naamanhirschfeld/workspace/kreuzberg-dev/worktrees/feat-elixir/packages/elixir/lib/kreuzberg/config.ex`

```elixir
def validate(%__MODULE__{} = config) do
  with :ok <- validate_boolean_field(config.use_cache, "use_cache"),
       :ok <- validate_boolean_field(config.enable_quality_processing, "enable_quality_processing"),
       :ok <- validate_boolean_field(config.force_ocr, "force_ocr"),
       :ok <- validate_nested_field(config.chunking, "chunking"),
       :ok <- validate_nested_field(config.ocr, "ocr"),
       :ok <- validate_nested_field(config.language_detection, "language_detection"),
       :ok <- validate_nested_field(config.postprocessor, "postprocessor"),
       :ok <- validate_nested_field(config.images, "images"),
       :ok <- validate_nested_field(config.pages, "pages"),
       :ok <- validate_nested_field(config.token_reduction, "token_reduction"),
       :ok <- validate_nested_field(config.keywords, "keywords"),
       :ok <- validate_nested_field(config.pdf_options, "pdf_options"),
       :ok <- validate_semantic_rules(config) do
    {:ok, config}
  end
end

# NEW: Semantic validation
defp validate_semantic_rules(config) do
  # Can add business logic validation here
  # e.g., conflicting options, mutually exclusive settings
  :ok
end
```

---

## 4. High-Priority: Configuration Presets (Tier 2)

### Problem

Users must manually construct common configurations:

```elixir
# Every user writes this pattern
config = %Kreuzberg.ExtractionConfig{
  ocr: %{"enabled" => true},
  use_cache: true
}
```

### Solution: Built-in Presets

**File:** `/Users/naamanhirschfeld/workspace/kreuzberg-dev/worktrees/feat-elixir/packages/elixir/lib/kreuzberg/config.ex`

```elixir
defmodule Kreuzberg.ConfigPreset do
  @moduledoc """
  Pre-built configuration presets for common extraction scenarios.

  ## Examples

      # Standard extraction with caching
      config = Kreuzberg.ConfigPreset.standard()
      {:ok, result} = Kreuzberg.extract(pdf_binary, "application/pdf", config)

      # High-quality with OCR
      config = Kreuzberg.ConfigPreset.high_quality()
      {:ok, result} = Kreuzberg.extract(scanned_pdf, "application/pdf", config)

      # Fast extraction with minimal processing
      config = Kreuzberg.ConfigPreset.fast()
      {:ok, result} = Kreuzberg.extract(pdf_binary, "application/pdf", config)
  """

  @type t :: Kreuzberg.ExtractionConfig.t()

  @doc """
  Standard extraction with sensible defaults.

  - Uses caching for performance
  - Enables quality processing
  - No forced OCR (only for non-searchable PDFs)
  """
  @spec standard() :: t()
  def standard do
    %Kreuzberg.ExtractionConfig{
      use_cache: true,
      enable_quality_processing: true,
      force_ocr: false
    }
  end

  @doc """
  High-quality extraction optimized for accuracy.

  - Forces OCR for maximum text accuracy
  - Enables quality processing
  - Disables caching for freshness
  """
  @spec high_quality() :: t()
  def high_quality do
    %Kreuzberg.ExtractionConfig{
      force_ocr: true,
      enable_quality_processing: true,
      use_cache: false,
      ocr: %{
        "enabled" => true,
        "language" => "auto",
        "psm_mode" => 1  # Assume single column text
      }
    }
  end

  @doc """
  Fast extraction with minimal processing.

  - Uses aggressive caching
  - Disables quality processing
  - No OCR unless necessary
  """
  @spec fast() :: t()
  def fast do
    %Kreuzberg.ExtractionConfig{
      use_cache: true,
      enable_quality_processing: false,
      force_ocr: false
    }
  end

  @doc """
  OCR-optimized extraction for scanned documents.

  - Forces OCR
  - Enables language detection
  - Enables quality processing
  """
  @spec ocr_optimized() :: t()
  def ocr_optimized do
    %Kreuzberg.ExtractionConfig{
      force_ocr: true,
      enable_quality_processing: true,
      use_cache: false,
      ocr: %{"enabled" => true, "language" => "auto"},
      language_detection: %{"enabled" => true}
    }
  end

  @doc """
  Content chunking for embedding/AI processing.

  - Enables text chunking
  - Standard chunk size of 512 tokens
  - 10% overlap between chunks
  """
  @spec chunking() :: t()
  def chunking do
    %Kreuzberg.ExtractionConfig{
      use_cache: true,
      enable_quality_processing: true,
      chunking: %{
        "enabled" => true,
        "chunk_size" => 512,
        "overlap" => 51  # ~10% overlap
      }
    }
  end

  @doc """
  Image and table extraction.

  - Extracts all images
  - Extracts tables with structure
  """
  @spec rich_content() :: t()
  def rich_content do
    %Kreuzberg.ExtractionConfig{
      use_cache: true,
      enable_quality_processing: true,
      images: %{"enabled" => true, "extract_ocr" => true},
      pages: %{"enabled" => true}  # Per-page content
    }
  end

  @doc """
  Metadata extraction only.

  - Minimal text processing
  - Focus on metadata, tables, images
  """
  @spec metadata_only() :: t()
  def metadata_only do
    %Kreuzberg.ExtractionConfig{
      use_cache: true,
      enable_quality_processing: false,
      images: %{"enabled" => true},
      pages: %{"enabled" => true}
    }
  end

  @doc """
  Merge a preset with custom overrides.

  ## Examples

      config = Kreuzberg.ConfigPreset.high_quality()
        |> Kreuzberg.ConfigPreset.override(%{"language" => "es"})
  """
  @spec override(t(), map()) :: t()
  def override(%Kreuzberg.ExtractionConfig{} = preset, overrides) when is_map(overrides) do
    struct(preset, Enum.into(overrides, %{}))
  end
end
```

**Usage:**

```elixir
# In public API documentation
defmodule Kreuzberg do
  @doc """
  Extract content from binary data with a preset configuration.

  ## Examples

      # Using a preset
      {:ok, result} = Kreuzberg.extract(
        pdf_binary,
        "application/pdf",
        Kreuzberg.ConfigPreset.high_quality()
      )

      # With custom overrides
      config = Kreuzberg.ConfigPreset.standard()
        |> Kreuzberg.ConfigPreset.override(%{force_ocr: true})
      {:ok, result} = Kreuzberg.extract(pdf_binary, "application/pdf", config)
  """
end
```

---

## 5. High-Priority: Error Context (Tier 2)

### Problem

Errors lack metadata for debugging:

```elixir
# Current - no context
{:error, "Invalid format"} = Kreuzberg.extract(data, "invalid/type")
# User doesn't know: what input size? what version? when did it fail?
```

### Solution: Rich Error Context

**File:** `/Users/naamanhirschfeld/workspace/kreuzberg-dev/worktrees/feat-elixir/packages/elixir/lib/kreuzberg.ex`

```elixir
def extract(input, mime_type, config \\ nil) when is_binary(input) and is_binary(mime_type) do
  start_time = System.monotonic_time(:millisecond)

  with :ok <- validate_input(input),
       {:ok, validated_config} <- validate_config(config),
       {:ok, result_map} <- call_native(input, mime_type, validated_config) do
    {:ok, into_result(result_map)}
  else
    {:error, reason} ->
      elapsed = System.monotonic_time(:millisecond) - start_time

      error = Error.new(
        reason,
        classify_error(reason),
        %{
          "input_size" => byte_size(input),
          "mime_type" => mime_type,
          "elapsed_ms" => elapsed,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "version" => Application.spec(:kreuzberg, :vsn) |> List.to_string(),
          "otp_version" => System.otp_release()
        }
      )

      {:error, error}
  end
end

def extract_file(path, mime_type \\ nil, config \\ nil) do
  start_time = System.monotonic_time(:millisecond)
  path_string = to_string(path)

  with {:ok, file_info} <- File.stat(path_string),
       :ok <- validate_input_file(file_info),
       {:ok, validated_config} <- validate_config(config),
       {:ok, result_map} <- call_native_file(path_string, mime_type, validated_config) do
    {:ok, into_result(result_map)}
  else
    {:error, reason} ->
      elapsed = System.monotonic_time(:millisecond) - start_time

      context = %{
        "path" => path_string,
        "file_size" => (File.stat(path_string) |> elem(1)).size,
        "mime_type" => mime_type,
        "elapsed_ms" => elapsed,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "version" => Application.spec(:kreuzberg, :vsn) |> List.to_string(),
        "otp_version" => System.otp_release()
      }

      error = Error.new(reason, classify_error(reason), context)
      {:error, error}
  end
end

defp validate_input_file(file_info) do
  if file_info.size > 0 do
    :ok
  else
    {:error, "File is empty"}
  end
end
```

**Use context in error handling:**

```elixir
case Kreuzberg.extract(binary, "application/pdf") do
  {:ok, result} ->
    IO.inspect(result)

  {:error, error} ->
    Logger.error("Extraction failed",
      message: error.message,
      reason: error.reason,
      context: error.context
    )

    # Users can now see full context in logs
    {:error, error.message}
end
```

---

## 6. High-Priority: NIF Contract Documentation (Tier 2)

### Solution: Comprehensive NIF Module Documentation

**File:** `/Users/naamanhirschfeld/workspace/kreuzberg-dev/worktrees/feat-elixir/packages/elixir/lib/kreuzberg/native.ex`

```elixir
defmodule Kreuzberg.Native do
  @moduledoc """
  Native Interface to Kreuzberg Rust implementation via Rustler.

  This module defines the NIF function stubs that are implemented in Rust.
  All functions are blocking and should not be called directly - use the
  public API in `Kreuzberg` module instead.

  ## NIF Loading

  NIFs are loaded from the compiled Rust crate at runtime. If the NIF
  library fails to load, all functions will return `:erlang.nif_error(:nif_not_loaded)`.

  ## Call Contracts

  ### extract/2

  Extract content from binary data without configuration options.

  **Parameters:**
    - `input` - Binary document data (PDF, DOCX, HTML, etc.)
      - Must be valid document format
      - No size limits enforced by Elixir (Rust may have limits)
    - `input_type` - MIME type string (e.g., "application/pdf")
      - Must be a valid MIME type
      - Case-sensitive
      - Supported types: application/pdf, application/vnd.openxmlformats-officedocument.wordprocessingml.document, text/html, text/markdown, text/plain

  **Returns:**
    - `{:ok, result_map}` - Successful extraction
      - result_map contains: %{
          "content" => String.t(),              # Extracted text
          "mime_type" => String.t(),             # Input MIME type
          "metadata" => map(),                   # Document metadata
          "tables" => list(map()),               # Extracted tables
          "detected_languages" => list(String.t()) | nil,  # Language codes
          "chunks" => list(map()) | nil,         # Text chunks
          "images" => list(map()) | nil,         # Extracted images
          "pages" => list(map()) | nil           # Per-page data
        }
    - `{:error, reason}` or `{:error, {error_code, reason}}`
      - `reason` - Error message string
      - `error_code` - Integer error classification (0-5)

  **Side Effects:**
    - May create temporary files for processing
    - Uses CPU for text extraction and OCR
    - May allocate significant memory for large documents

  **Performance Characteristics:**
    - Blocking operation
    - Time depends on document size and complexity
    - No progress callbacks

  **Exceptions:**
    - Raises only if NIF not loaded (rare)

  ### extract_with_options/3

  Extract content from binary data with configuration options.

  **Parameters:**
    - `input` - Binary document data (same as extract/2)
    - `input_type` - MIME type string (same as extract/2)
    - `options` - Configuration map with string keys
      - %{
          "chunking" => map() | nil,
          "ocr" => map() | nil,
          "language_detection" => map() | nil,
          "postprocessor" => map() | nil,
          "images" => map() | nil,
          "pages" => map() | nil,
          "token_reduction" => map() | nil,
          "keywords" => map() | nil,
          "pdf_options" => map() | nil,
          "use_cache" => boolean(),
          "enable_quality_processing" => boolean(),
          "force_ocr" => boolean()
        }

  **Returns:**
    - Same as extract/2 but with processing applied per options

  **Configuration Details:**

  - `use_cache` (boolean, default: true)
    - Enables caching of extraction results
    - Keyed by input hash

  - `enable_quality_processing` (boolean, default: true)
    - Applies post-processing for improved output
    - Slower but more accurate

  - `force_ocr` (boolean, default: false)
    - Forces OCR even for searchable PDFs
    - Significantly slower

  - `ocr` (map, optional)
    - `enabled` (boolean) - Enable OCR processing
    - `language` (string) - ISO 639-1 language code or "auto"
    - `psm_mode` (integer) - Tesseract PSM mode (0-13)

  - `chunking` (map, optional)
    - `enabled` (boolean) - Enable text chunking
    - `chunk_size` (integer) - Size of chunks in tokens
    - `overlap` (integer) - Overlap between chunks

  - Other options documented in Rust implementation

  ### extract_file/2

  Extract content from a file at the given path.

  **Parameters:**
    - `path` - File path string
      - Must be readable by the process
      - Absolute or relative paths supported
      - Symlinks followed
    - `mime_type` - MIME type string or nil
      - If nil, MIME type is auto-detected from file extension
      - If provided, overrides auto-detection

  **Returns:**
    - Same as extract/2

  **Side Effects:**
    - Reads file from disk
    - May create temporary files
    - Uses CPU and memory like extract/2

  **Differences from extract/2:**
    - Rust handles file reading (better memory management for large files)
    - May support streaming in future versions
    - Path errors caught at Rust level

  ### extract_file_with_options/3

  Extract from file with configuration options.

  **Parameters:**
    - Same as extract_file/2 plus options (same as extract_with_options/3)

  **Returns:**
    - Same as extract/2

  ## Error Codes

  Structured error returns follow this format:
  `{:error, {error_code, error_message}}`

  - `0` - IO_ERROR: File not found, permission denied, etc.
  - `1` - INVALID_FORMAT: Unsupported format or corrupted file
  - `2` - INVALID_CONFIG: Configuration error
  - `3` - OCR_ERROR: OCR processing failed
  - `4` - EXTRACTION_ERROR: Text extraction failed
  - `5` - NIF_ERROR: Native interface error
  - `-1` - UNKNOWN: Uncategorized error

  ## Compatibility

  - Requires Rust implementation compiled and linked
  - Only called from `Kreuzberg` module (public API)
  - Should not be called directly by users

  ## Example NIF Function Call Flow

  ```
  Kreuzberg.extract(pdf_binary, "application/pdf")
    ↓ validates input
    ↓ calls Kreuzberg.Native.extract/2
    ↓ Rust processes PDF
    ↓ returns {:ok, result_map}
    ↓ wraps in ExtractionResult struct
    ↓ returns {:ok, ExtractionResult{}}
  ```

  See `Kreuzberg` module for public API.
  """

  use Rustler,
    otp_app: :kreuzberg,
    crate: "kreuzberg_rustler",
    mode: if(Mix.env() == :prod, do: :release, else: :debug)

  @doc """
  Extract content from binary data.

  This is a direct NIF binding. Use `Kreuzberg.extract/3` instead.

  See module documentation for details.
  """
  def extract(_input, _input_type), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Extract content with configuration options.

  This is a direct NIF binding. Use `Kreuzberg.extract/3` instead.

  See module documentation for details.
  """
  def extract_with_options(_input, _input_type, _options), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Extract content from a file.

  This is a direct NIF binding. Use `Kreuzberg.extract_file/3` instead.

  See module documentation for details.
  """
  def extract_file(_path, _mime_type), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Extract content from a file with configuration options.

  This is a direct NIF binding. Use `Kreuzberg.extract_file/3` instead.

  See module documentation for details.
  """
  def extract_file_with_options(_path, _mime_type, _options), do: :erlang.nif_error(:nif_not_loaded)
end
```

---

## 7. Medium-Priority: Result Processing Utilities (Tier 2)

### Solution: Add Result Processing Module

**New file:** `/Users/naamanhirschfeld/workspace/kreuzberg-dev/worktrees/feat-elixir/packages/elixir/lib/kreuzberg/result_processing.ex`

```elixir
defmodule Kreuzberg.ResultProcessing do
  @moduledoc """
  Utilities for processing and transforming extraction results.

  Provides common operations on `ExtractionResult` structs that users
  frequently need.

  ## Examples

      {:ok, result} = Kreuzberg.extract(pdf_binary, "application/pdf")

      # Get document summary
      summary = Kreuzberg.ResultProcessing.summarize(result)
      IO.inspect(summary)
      # %{
      #   "word_count" => 1234,
      #   "language" => "en",
      #   "table_count" => 2,
      #   "image_count" => 3
      # }

      # Filter chunks by confidence
      high_confidence = Kreuzberg.ResultProcessing.filter_chunks(result, 0.9)

      # Extract metadata
      metadata = Kreuzberg.ResultProcessing.get_metadata(result)
  """

  alias Kreuzberg.ExtractionResult

  @type t :: ExtractionResult.t()

  @doc """
  Get a summary of the extraction result.

  Returns key metrics about the extracted content.

  ## Returns

  A map containing:
    - `word_count` - Number of words in content
    - `character_count` - Total characters
    - `language` - Primary detected language (or nil)
    - `table_count` - Number of tables extracted
    - `image_count` - Number of images extracted
    - `chunk_count` - Number of text chunks (if chunking enabled)
    - `page_count` - Number of pages (if page extraction enabled)
  """
  @spec summarize(t()) :: map()
  def summarize(%ExtractionResult{} = result) do
    %{
      "word_count" => count_words(result.content),
      "character_count" => String.length(result.content),
      "language" => List.first(result.detected_languages),
      "table_count" => length(result.tables || []),
      "image_count" => length(result.images || []),
      "chunk_count" => length(result.chunks || []),
      "page_count" => length(result.pages || [])
    }
  end

  @doc """
  Filter chunks by minimum confidence threshold.

  Only works if chunking was enabled during extraction.

  ## Parameters

    - `result` - The extraction result
    - `min_confidence` - Minimum confidence score (0.0 to 1.0)

  ## Returns

  A new result with filtered chunks, or the original if no chunks.
  """
  @spec filter_chunks(t(), float()) :: t()
  def filter_chunks(%ExtractionResult{} = result, min_confidence) do
    case result.chunks do
      nil ->
        result

      chunks ->
        filtered = Enum.filter(chunks, fn chunk ->
          confidence = chunk["confidence"] || 1.0
          confidence >= min_confidence
        end)

        %{result | chunks: filtered}
    end
  end

  @doc """
  Get all extracted metadata.

  ## Returns

  The metadata map from the result.
  """
  @spec get_metadata(t()) :: map()
  def get_metadata(%ExtractionResult{} = result) do
    result.metadata || %{}
  end

  @doc """
  Get all extracted tables.

  ## Returns

  List of table maps, or empty list if none.
  """
  @spec get_tables(t()) :: list(map())
  def get_tables(%ExtractionResult{} = result) do
    result.tables || []
  end

  @doc """
  Get all extracted images.

  ## Returns

  List of image maps, or empty list if none.
  """
  @spec get_images(t()) :: list(map())
  def get_images(%ExtractionResult{} = result) do
    result.images || []
  end

  @doc """
  Get all detected languages.

  ## Returns

  List of ISO 639-1 language codes.
  """
  @spec get_languages(t()) :: list(String.t())
  def get_languages(%ExtractionResult{} = result) do
    result.detected_languages || []
  end

  @doc """
  Check if result has tables.

  ## Returns

  true if tables were extracted, false otherwise.
  """
  @spec has_tables?(t()) :: boolean()
  def has_tables?(%ExtractionResult{} = result) do
    is_list(result.tables) and length(result.tables) > 0
  end

  @doc """
  Check if result has images.

  ## Returns

  true if images were extracted, false otherwise.
  """
  @spec has_images?(t()) :: boolean()
  def has_images?(%ExtractionResult{} = result) do
    is_list(result.images) and length(result.images) > 0
  end

  @doc """
  Check if result has chunks.

  ## Returns

  true if chunks were extracted, false otherwise.
  """
  @spec has_chunks?(t()) :: boolean()
  def has_chunks?(%ExtractionResult{} = result) do
    is_list(result.chunks) and length(result.chunks) > 0
  end

  @doc """
  Get first page content if available.

  ## Returns

  First page map or nil if pages not extracted.
  """
  @spec first_page(t()) :: map() | nil
  def first_page(%ExtractionResult{} = result) do
    case result.pages do
      [first | _] -> first
      _ -> nil
    end
  end

  @doc """
  Get all pages.

  ## Returns

  List of page maps, or empty list if not extracted.
  """
  @spec get_pages(t()) :: list(map())
  def get_pages(%ExtractionResult{} = result) do
    result.pages || []
  end

  @doc """
  Truncate content to maximum word count.

  Useful for limiting result size for display or processing.

  ## Returns

  New result with truncated content.
  """
  @spec truncate_content(t(), integer()) :: t()
  def truncate_content(%ExtractionResult{} = result, max_words) do
    truncated = result.content
      |> String.split()
      |> Enum.take(max_words)
      |> Enum.join(" ")

    %{result | content: truncated}
  end

  # Private helpers

  defp count_words(content) do
    content
    |> String.split()
    |> length()
  end
end
```

**Usage:**

```elixir
{:ok, result} = Kreuzberg.extract(pdf_binary, "application/pdf")

# Get summary
summary = Kreuzberg.ResultProcessing.summarize(result)
IO.puts("Word count: #{summary["word_count"]}")
IO.puts("Language: #{summary["language"]}")

# Filter chunks
high_confidence = Kreuzberg.ResultProcessing.filter_chunks(result, 0.85)

# Check what was extracted
if Kreuzberg.ResultProcessing.has_tables?(result) do
  IO.inspect(Kreuzberg.ResultProcessing.get_tables(result))
end
```

---

## Implementation Priority

### Week 1
- [ ] Implement NIF result validation (Critical)
- [ ] Integrate config validation (Critical)
- [ ] Update error handling with context (High)

### Week 2
- [ ] Add configuration presets (High)
- [ ] Document NIF contracts (High)
- [ ] Add result processing utilities (Medium)

### Week 3+
- [ ] Coordinate with Rust team on structured error codes (Critical, depends on Rust)
- [ ] Implement configuration builder pattern (Future)
- [ ] Add extraction strategies (Future)

---

## Testing the Improvements

Each improvement should include tests:

```elixir
# Test config validation integration
test "extract validates config before calling native" do
  invalid_config = %Kreuzberg.ExtractionConfig{use_cache: "not a boolean"}
  assert {:error, reason} = Kreuzberg.extract("data", "text/plain", invalid_config)
  assert String.contains?(reason, "boolean")
end

# Test result processing
test "result summarization works" do
  {:ok, result} = Kreuzberg.extract("Hello world test", "text/plain")
  summary = Kreuzberg.ResultProcessing.summarize(result)
  assert summary["word_count"] == 3
end

# Test error context
test "errors include context" do
  {:error, error} = Kreuzberg.extract(<<>>, "invalid/type")
  assert error.context["input_size"] == 0
  assert error.context["mime_type"] == "invalid/type"
end
```

---

## Summary

These six improvements address the critical and high-priority architectural issues identified in ARCHITECTURE_REVIEW_ROUND_2.md:

1. **Structured Error Codes** - Fixes brittleness (requires Rust coordination)
2. **Result Validation** - Prevents silent failures
3. **Config Validation** - Provides better error messages
4. **Configuration Presets** - Improves UX
5. **Error Context** - Enables better debugging
6. **NIF Documentation** - Improves maintainability

All can be implemented incrementally without breaking changes to the public API.
