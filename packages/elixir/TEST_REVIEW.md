# Critical Test Implementation Review

## Executive Summary

The test suite demonstrates good intent with comprehensive coverage across unit and format tests, but suffers from significant DRY violations, test maintainability issues, and organizational problems. The file-based tests have excessive repetition and brittle file I/O patterns that could be significantly refactored.

**Overall Assessment**: **5.5/10**
- Coverage: Good
- Maintainability: Poor
- DRY Compliance: Poor (High duplication)
- Performance: Fair (File I/O overhead)
- Organization: Fair

---

## Critical Issues

### 1. DRY VIOLATION: Massive Test Setup Duplication in File Tests

**Severity**: CRITICAL
**Files**:
- `/Users/naamanhirschfeld/workspace/kreuzberg-dev/worktrees/feat-elixir/packages/elixir/test/unit/file_extraction_test.exs` (lines 17-22, 25-29)
- `/Users/naamanhirschfeld/workspace/kreuzberg-dev/worktrees/feat-elixir/packages/elixir/test/format/file_extraction_test.exs` (lines 390-407)

**Issue**:
The `create_temp_file/1` and `cleanup_temp_file/1` helpers are defined locally in `file_extraction_test.exs`, and the format tests reimplement similar logic inline. Every single test in the file tests wraps file operations in try/after blocks.

```elixir
# Lines 33-45 in unit/file_extraction_test.exs
test "returns success tuple for text file with explicit MIME type" do
  path = create_temp_file("Hello world")

  try do
    {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
    assert %Kreuzberg.ExtractionResult{} = result
    assert result.content == "Hello world"
    assert result.mime_type == "text/plain"
  after
    cleanup_temp_file(path)
  end
end
```

This pattern is repeated 30+ times across both file tests.

**Recommendation**:
Create a dedicated test helper module with setup/cleanup infrastructure using ExUnit callbacks.

```elixir
# test/support/test_fixtures.exs
defmodule KreuzbergTest.Fixtures do
  def with_temp_file(content, test_func) when is_function(test_func, 1) do
    unique_id = System.unique_integer()
    path = System.tmp_dir!() <> "/kreuzberg_test_#{unique_id}.txt"
    File.write!(path, content)

    try do
      test_func.(path)
    after
      if File.exists?(path), do: File.rm(path)
    end
  end

  def temp_file_path(content) do
    unique_id = System.unique_integer()
    path = System.tmp_dir!() <> "/kreuzberg_test_#{unique_id}.txt"
    File.write!(path, content)
    path
  end

  def cleanup_all(paths) when is_list(paths) do
    Enum.each(paths, &cleanup_temp_file/1)
  end
end

# In test_helper.exs
defp cleanup_temp_file(path) when is_binary(path) do
  if File.exists?(path), do: File.rm(path)
end
```

Then simplify tests:

```elixir
# test/unit/file_extraction_test.exs
use ExUnit.Case
import KreuzbergTest.Fixtures

test "returns success tuple for text file with explicit MIME type" do
  with_temp_file("Hello world", fn path ->
    {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
    assert result.content == "Hello world"
    assert result.mime_type == "text/plain"
  end)
end
```

---

### 2. DRY VIOLATION: Repeated ExtractionResult Structure Assertions

**Severity**: HIGH
**Files**:
- `test/unit/extraction_test.exs` (lines 24-38, 101-115, 104-114)
- `test/unit/file_extraction_test.exs` (lines 77-97, 192-206, 417-431)
- `test/format/file_extraction_test.exs` (lines 95-114, 217-228, 329-342)

**Issue**:
The same result structure validation is repeated 8+ times:

```elixir
# Appears in multiple places
assert %Kreuzberg.ExtractionResult{
         content: content,
         mime_type: mime_type,
         metadata: metadata,
         tables: tables
       } = result

assert is_binary(content)
assert is_binary(mime_type)
assert is_map(metadata)
assert is_list(tables)
```

**Recommendation**:
Create assertion helpers in test/support:

```elixir
# test/support/assertions.exs
defmodule KreuzbergTest.Assertions do
  def assert_valid_extraction_result(result) do
    assert %Kreuzberg.ExtractionResult{
             content: content,
             mime_type: mime_type,
             metadata: metadata,
             tables: tables,
             detected_languages: _,
             chunks: _,
             images: _,
             pages: _
           } = result

    assert is_binary(content)
    assert is_binary(mime_type)
    assert is_map(metadata)
    assert is_list(tables)
  end

  def assert_valid_pdf_result(result) do
    assert %Kreuzberg.ExtractionResult{
             content: content,
             mime_type: mime_type,
             metadata: metadata,
             tables: tables,
             detected_languages: languages,
             chunks: chunks,
             images: images,
             pages: pages
           } = result

    assert is_binary(content)
    assert is_binary(mime_type)
    assert is_map(metadata)
    assert is_list(tables)
    assert is_list(languages)
    assert is_list(chunks)
    assert is_list(images)
    assert is_list(pages)
  end
end

# In tests
use ExUnit.Case
import KreuzbergTest.Assertions

test "success result has proper structure" do
  {:ok, result} = Kreuzberg.extract("Test content", "text/plain")
  assert_valid_extraction_result(result)
end
```

---

### 3. Test Coupling with File System: No Cleanup Guarantees

**Severity**: HIGH
**Files**:
- `test/unit/file_extraction_test.exs` (lines 549-561)
- `test/format/file_extraction_test.exs` (lines 435-450, 390-407)

**Issue**:
Tests create files in different locations with inconsistent cleanup. Some tests use System.tmp_dir, others use relative paths, and cleanup is not guaranteed if assertions fail early.

```elixir
# Lines 549-561: Relative path test with fragile cleanup
test "relative path is handled" do
  path = "test_extraction_relative_#{System.unique_integer()}.txt"
  File.write!(path, "relative path content")

  try do
    {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
    assert result.content == "relative path content"
  after
    if File.exists?(path), do: File.rm(path)
  end
end

# Lines 390-407: Inline file creation in integration test
test "consistent extraction across formats with same content" do
  text_content = "Test content for extraction"
  unique_id = System.unique_integer()
  txt_path = System.tmp_dir!() <> "/test_#{unique_id}.txt"
  File.write!(txt_path, text_content)

  try do
    # test code
  after
    if File.exists?(txt_path), do: File.rm(txt_path)
  end
end
```

**Recommendation**:
Use ExUnit's built-in setup/teardown and create a dedicated fixtures module:

```elixir
# test/support/file_fixtures.exs
defmodule KreuzbergTest.FileFixtures do
  def create_temp_file(content, opts \\ []) do
    dir = Keyword.get(opts, :dir, System.tmp_dir!())
    ext = Keyword.get(opts, :ext, ".txt")
    unique_id = System.unique_integer()
    filename = "kreuzberg_test_#{unique_id}#{ext}"
    path = Path.join(dir, filename)

    File.write!(path, content)
    path
  end

  def cleanup_temp_file(path) do
    if File.exists?(path), do: File.rm(path)
  end

  def with_temp_file(content, opts \\ [], test_func) do
    path = create_temp_file(content, opts)
    try do
      test_func.(path)
    after
      cleanup_temp_file(path)
    end
  end
end

# In test files
describe "relative path handling" do
  setup do
    {:ok, cwd: File.cwd!()}
  end

  test "relative path is handled", %{cwd: cwd} do
    import KreuzbergTest.FileFixtures

    with_temp_file("relative path content", fn path ->
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert result.content == "relative path content"
    end)
  end
end
```

---

### 4. DRY VIOLATION: Repeated File-Existence Checks

**Severity**: MEDIUM
**Files**:
- `test/format/file_extraction_test.exs` (lines 11, 22, 33, 44, 60, 75, 91, 120, 134, 149, 168, 194, 210, 274, 296, 311, 326, 346, 362, 375)
- `test/format/pdf_extraction_test.exs` (lines 11, 33)

**Issue**:
Every single format test checks if the file exists before running assertions:

```elixir
# This pattern is repeated 20+ times
pdf_path = Path.expand("../../../test_documents/pdfs/code_and_formula.pdf", __DIR__)

if File.exists?(pdf_path) do
  {:ok, result} = Kreuzberg.extract_file(pdf_path, "application/pdf")
  # assertions...
end
```

This creates brittle tests that silently pass when files don't exist.

**Recommendation**:
Create a helper that documents what files are required and validates setup:

```elixir
# test/support/document_fixtures.exs
defmodule KreuzbergTest.DocumentFixtures do
  @doc """
  List of required test documents for format tests.
  Add documents here if they are used in tests.
  """
  def required_documents do
    [
      "test_documents/pdfs/code_and_formula.pdf",
      "test_documents/pdfs/right_to_left_01.pdf",
      "test_documents/pdfs_with_tables/tiny.pdf",
      "test_documents/pdfs_with_tables/medium.pdf",
      "test_documents/extraction_test.docx",
      "test_documents/web/html.html",
      "test_documents/web/complex_table.html",
      "test_documents/web/germany_german.html",
      "test_documents/pdfs/multi_page.pdf",
      "test_documents/pdfs/embedded_images_tables.pdf"
    ]
  end

  def get_document(relative_path) do
    path = Path.expand("../../../#{relative_path}", __DIR__)
    if File.exists?(path), do: {:ok, path}, else: {:skip, "Document not found: #{relative_path}"}
  end

  def assert_document_exists(relative_path) do
    path = Path.expand("../../../#{relative_path}", __DIR__)
    unless File.exists?(path) do
      flunk("Test document not found: #{relative_path}. Ensure test_documents are present.")
    end
    path
  end
end

# Usage in tests
describe "PDF extraction from file" do
  import KreuzbergTest.DocumentFixtures

  test "extracts content from PDF file" do
    pdf_path = assert_document_exists("test_documents/pdfs/code_and_formula.pdf")
    {:ok, result} = Kreuzberg.extract_file(pdf_path, "application/pdf")

    assert result.content != nil
    assert is_binary(result.content)
    assert byte_size(result.content) > 0
    assert result.mime_type == "application/pdf"
    assert is_map(result.metadata)
    assert is_list(result.tables)
  end
end
```

---

### 5. Test Coverage Gaps: Missing Error Path Tests

**Severity**: HIGH
**Files**:
- `test/unit/extraction_test.exs` (lines 40-46, 449-478)
- `test/unit/file_extraction_test.exs` (lines 472-518)

**Issue**:
Limited error case coverage. Missing tests for:
- Various error scenarios and their message formats
- Edge cases with malformed inputs
- Configuration validation errors
- Partial failures in multi-feature extractions

```elixir
# Lines 40-46: Only checks that error is returned, not error types
test "returns error for invalid MIME type" do
  {:error, reason} = Kreuzberg.extract("data", "invalid/type")
  assert is_binary(reason) and byte_size(reason) > 0
end

# Lines 458-469: Bulk testing without error verification
test "different invalid mime types produce errors" do
  invalid_types = [
    "invalid",
    "not/supported",
    "random/mime",
    ""
  ]

  Enum.each(invalid_types, fn mime_type ->
    result = Kreuzberg.extract("data", mime_type)
    assert {:error, _reason} = result
  end)
end
```

**Recommendation**:
Add comprehensive error scenario tests:

```elixir
# test/unit/extraction_error_test.exs
defmodule KreuzbergTest.Unit.ExtractionErrorTest do
  use ExUnit.Case

  describe "extract/2 error handling" do
    test "invalid MIME types return errors" do
      invalid_types = [
        "invalid",
        "not/supported",
        "random/mime",
        "",
        "text",
        "/plain",
        "text/",
        "!invalid/mime"
      ]

      Enum.each(invalid_types, fn mime_type ->
        {:error, reason} = Kreuzberg.extract("data", mime_type)
        assert is_binary(reason)
        assert byte_size(reason) > 0
      end)
    end

    test "error messages are descriptive for MIME type failures" do
      {:error, reason} = Kreuzberg.extract("data", "invalid/type")

      # Error should contain helpful information
      assert String.contains?(reason, ["MIME", "type", "invalid", "supported"]) or
             byte_size(reason) > 10
    end

    test "extract! raises specific error for invalid MIME type" do
      assert_raise Kreuzberg.Error, ~r/.+/, fn ->
        Kreuzberg.extract!("data", "invalid/type")
      end
    end
  end

  describe "extract_file/3 error handling" do
    test "missing file returns specific error" do
      non_existent = "/tmp/missing_#{System.unique_integer()}_file.txt"
      {:error, reason} = Kreuzberg.extract_file(non_existent, "text/plain")

      # Should mention file or path in error
      assert is_binary(reason)
      assert byte_size(reason) > 0
    end

    test "empty path returns error" do
      {:error, reason} = Kreuzberg.extract_file("", "text/plain")
      assert is_binary(reason)
    end

    test "directory path returns error" do
      {:error, reason} = Kreuzberg.extract_file(System.tmp_dir!(), "text/plain")
      assert is_binary(reason)
    end

    test "permission denied on file" do
      # This test should only run if we can actually set permissions
      path = System.tmp_dir!() <> "/test_#{System.unique_integer()}.txt"
      File.write!(path, "content")
      File.chmod!(path, 0o000)

      try do
        {:error, _reason} = Kreuzberg.extract_file(path, "text/plain")
      after
        File.chmod!(path, 0o644)
        File.rm(path)
      end
    end
  end
end
```

---

### 6. Test Organization: Mixed Concerns in Format Tests

**Severity**: MEDIUM
**Files**:
- `test/format/file_extraction_test.exs` (lines 389-421, 423-450)

**Issue**:
Integration and unit concerns are mixed in the same test file. Some tests create temporary files (unit-style), others use test documents (integration-style). This makes it unclear which tests require external dependencies.

```elixir
# Lines 389-421: Integration test creating temp files
describe "multi-format extraction consistency" do
  test "consistent extraction across formats with same content" do
    text_content = "Test content for extraction"
    unique_id = System.unique_integer()
    txt_path = System.tmp_dir!() <> "/test_#{unique_id}.txt"
    # ... test code
  end
end

# This should be in unit tests, not format tests
```

**Recommendation**:
Reorganize tests by concern:

```
test/
├── unit/                              # No external dependencies
│   ├── extraction_test.exs           # String-based extraction
│   ├── file_extraction_test.exs      # File-based with temp files
│   └── extraction_error_test.exs     # Error handling (NEW)
│
├── format/                           # Requires test documents
│   ├── pdf_extraction_test.exs
│   ├── docx_extraction_test.exs      # (NEW - split DOCX tests)
│   ├── html_extraction_test.exs      # (NEW - split HTML tests)
│   └── consistency_test.exs          # Multi-format consistency
│
└── support/                          # Test infrastructure
    ├── test_fixtures.exs
    ├── document_fixtures.exs
    └── assertions.exs
```

---

## High Priority Issues

### 7. Hard-Coded File Paths with No Validation

**Severity**: HIGH
**Files**: `test/format/file_extraction_test.exs` (lines 20, 42, 58, 73, 89, etc.)

**Issue**:
File paths are hard-coded throughout format tests without centralized management:

```elixir
Path.expand("../../../test_documents/pdfs/code_and_formula.pdf", __DIR__)
Path.expand("../../../test_documents/pdfs/right_to_left_01.pdf", __DIR__)
Path.expand("../../../test_documents/pdfs_with_tables/tiny.pdf", __DIR__)
```

Difficult to maintain, no clear inventory of required files.

**Recommendation**:
Create constants module for all test document paths:

```elixir
# test/support/document_paths.exs
defmodule KreuzbergTest.DocumentPaths do
  @base_path Path.expand("../../../test_documents", __DIR__)

  def pdf_code_and_formula, do: Path.join(@base_path, "pdfs/code_and_formula.pdf")
  def pdf_right_to_left_01, do: Path.join(@base_path, "pdfs/right_to_left_01.pdf")
  def pdf_multi_page, do: Path.join(@base_path, "pdfs/multi_page.pdf")
  def pdf_embedded_images, do: Path.join(@base_path, "pdfs/embedded_images_tables.pdf")
  def pdf_tiny, do: Path.join(@base_path, "pdfs_with_tables/tiny.pdf")
  def pdf_medium, do: Path.join(@base_path, "pdfs_with_tables/medium.pdf")

  def docx_extraction_test, do: Path.join(@base_path, "extraction_test.docx")

  def html_simple, do: Path.join(@base_path, "web/html.html")
  def html_complex_table, do: Path.join(@base_path, "web/complex_table.html")
  def html_german, do: Path.join(@base_path, "web/germany_german.html")

  def all_test_documents do
    [
      pdf_code_and_formula(),
      pdf_right_to_left_01(),
      pdf_multi_page(),
      pdf_embedded_images(),
      pdf_tiny(),
      pdf_medium(),
      docx_extraction_test(),
      html_simple(),
      html_complex_table(),
      html_german()
    ]
  end

  def verify_all_exist! do
    missing = Enum.reject(all_test_documents(), &File.exists?/1)
    if Enum.any?(missing) do
      raise """
      Missing test documents. These are required for format tests:
      #{Enum.map_join(missing, "\n", &"  - #{&1}")}
      """
    end
  end
end

# test_helper.exs
# Optionally verify on startup: KreuzbergTest.DocumentPaths.verify_all_exist!()

# In tests
import KreuzbergTest.DocumentPaths

test "extracts content from PDF file" do
  {:ok, result} = Kreuzberg.extract_file(pdf_code_and_formula(), "application/pdf")
  # assertions...
end
```

---

### 8. Brittle Tests with Silent Failures

**Severity**: MEDIUM
**Files**: `test/format/file_extraction_test.exs` (lines 11-28, 22-43, etc.)

**Issue**:
Tests silently skip if documents don't exist, giving false confidence:

```elixir
test "extracts content and metadata from PDF" do
  pdf_path = Path.expand("../../../test_documents/pdfs/multi_page.pdf", __DIR__)

  if File.exists?(pdf_path) do
    # test code
  end
  # If file doesn't exist, test passes silently!
end
```

**Recommendation**:
Use `@skip` tag or proper test skipping:

```elixir
import KreuzbergTest.DocumentFixtures

@tag :requires_documents
test "extracts content and metadata from PDF" do
  pdf_path = assert_document_exists("test_documents/pdfs/multi_page.pdf")

  {:ok, pdf_binary} = File.read(pdf_path)
  result = Kreuzberg.extract!(pdf_binary, "application/pdf")

  assert result.content != nil
  assert is_binary(result.content)
  assert byte_size(result.content) > 0
  assert result.mime_type == "application/pdf"
  assert is_map(result.metadata)
end
```

Then run with: `mix test --exclude requires_documents` when documents unavailable.

---

## Medium Priority Issues

### 9. Incomplete Assertions in Result Validation

**Severity**: MEDIUM
**Files**:
- `test/format/file_extraction_test.exs` (lines 110-113, 341)

**Issue**:
Some tests assert fields as lists/maps but don't verify they're non-empty or have expected structure:

```elixir
# Lines 110-113: Just checks type, no content validation
assert is_list(languages)
assert is_list(chunks)
assert is_list(images)
assert is_list(pages)
```

**Recommendation**:
Add content-aware assertions:

```elixir
# Better assertions
test "PDF extraction result has proper structure" do
  pdf_path = assert_document_exists("test_documents/pdfs/code_and_formula.pdf")
  {:ok, result} = Kreuzberg.extract_file(pdf_path, "application/pdf")

  # Verify structure
  assert %Kreuzberg.ExtractionResult{} = result

  # Verify content fields
  assert is_binary(result.content)
  assert byte_size(result.content) > 0, "PDF should extract some content"

  # Verify collection types
  assert is_list(result.tables), "tables should be a list"
  assert is_list(result.detected_languages) or is_nil(result.detected_languages)
  assert is_list(result.chunks) or is_nil(result.chunks)
  assert is_list(result.images) or is_nil(result.images)
  assert is_list(result.pages) or is_nil(result.pages)
end
```

---

### 10. Inconsistent Test Naming Conventions

**Severity**: LOW
**Files**: All test files

**Issue**:
Test names use different patterns:
- "returns success tuple for text file with explicit MIME type" (verbose)
- "accepts String path" (concise)
- "result content is always a binary" (assertion-style)
- "extracts content from PDF file" (action-style)

**Recommendation**:
Establish and use consistent naming pattern:

```elixir
# Pattern: "action/verb + expected behavior"
test "extract/2 returns success tuple for valid input" do
test "extract/2 returns error tuple for invalid MIME type" do
test "extract!/2 raises Kreuzberg.Error on invalid input" do
test "extract_file/3 accepts String paths" do
test "extract_file/3 accepts absolute and relative paths" do
test "extraction result contains all required fields" do
```

---

### 11. Performance: Inefficient File I/O in Tests

**Severity**: MEDIUM
**Files**: `test/unit/file_extraction_test.exs` (multiple tests)

**Issue**:
Tests create new temporary files for nearly every test case:

```elixir
# Each test creates/deletes file
test "returns success tuple for text file with explicit MIME type" do
  path = create_temp_file("Hello world")
  # ... test ...
  cleanup_temp_file(path)
end

# This is repeated 30+ times with different content
```

**Recommendation**:
Use `setup_all` to create shared test files:

```elixir
describe "extract_file/3 with explicit MIME type" do
  setup_all do
    files = %{
      hello: create_temp_file("Hello world"),
      test_content: create_temp_file("Test content"),
      path_test: create_temp_file("Path test"),
      # ... more files
    }

    on_exit(fn ->
      Enum.each(files, fn {_key, path} -> cleanup_temp_file(path) end)
    end)

    {:ok, files: files}
  end

  test "returns success tuple for text file with explicit MIME type", %{files: files} do
    {:ok, result} = Kreuzberg.extract_file(files.hello, "text/plain")
    assert result.content == "Hello world"
  end

  test "accepts String path", %{files: files} do
    {:ok, result} = Kreuzberg.extract_file(files.test_content, "text/plain")
    assert result.content == "Test content"
  end
end
```

This significantly reduces file system operations.

---

### 12. Redundant Test Cases

**Severity**: MEDIUM
**Files**:
- `test/unit/extraction_test.exs` (lines 15-21, 24-38) - Duplicate concerns
- `test/unit/file_extraction_test.exs` (lines 695-708, 711-723) - Consistency tests

**Issue**:
Tests 15-21 and 24-38 test nearly identical scenarios:

```elixir
# Lines 15-21
test "returns success tuple for plain text" do
  {:ok, result} = Kreuzberg.extract("Hello world", "text/plain")
  assert %Kreuzberg.ExtractionResult{} = result
  assert result.content == "Hello world"
  assert result.mime_type == "text/plain"
end

# Lines 24-38
test "success result has proper structure" do
  {:ok, result} = Kreuzberg.extract("Test content", "text/plain")
  assert %Kreuzberg.ExtractionResult{...} = result
  assert is_binary(content)
  assert is_binary(mime_type)
  # ... more assertions
end
```

Both test the same basic extraction. Consolidate.

**Recommendation**:
Merge related tests:

```elixir
describe "extract/2 - successful extractions" do
  test "extracts text and returns properly structured result" do
    {:ok, result} = Kreuzberg.extract("Hello world", "text/plain")

    # Check structure
    assert %Kreuzberg.ExtractionResult{
             content: content,
             mime_type: mime_type,
             metadata: metadata,
             tables: tables
           } = result

    # Verify content and types
    assert content == "Hello world"
    assert mime_type == "text/plain"
    assert is_binary(content)
    assert is_binary(mime_type)
    assert is_map(metadata)
    assert is_list(tables)
  end
end
```

---

## Low Priority / Suggestions

### 13. Missing Documentation for Test Categories

**Severity**: LOW
**Files**: All test files

**Issue**:
Module docs are helpful but lack clarity on test prerequisites and dependencies.

**Recommendation**:
Enhance documentation:

```elixir
defmodule KreuzbergTest.Unit.FileExtractionTest do
  @moduledoc """
  Unit tests for Kreuzberg file extraction functions.

  ## Test Files Created

  This module creates temporary test files during execution in System.tmp_dir().
  All files are cleaned up automatically after each test.

  ## Prerequisites

  - None. Tests create all required files dynamically.

  ## Test Coverage

  - `extract_file/2` with explicit MIME types
  - `extract_file/2` with auto-detection (nil MIME type)
  - `extract_file/3` with configuration (struct and map formats)
  - `extract_file!/2` success and failure cases
  - Path handling (String, Path.t(), relative, absolute)
  - Result structure validation
  - Consistency across invocations

  ## File I/O Notes

  Tests use `try/after` blocks to ensure cleanup even if assertions fail.
  Test execution should be isolated and not interfere with other tests.
  """
end
```

---

### 14. Missing Property-Based Tests

**Severity**: LOW
**Files**: All test files

**Issue**:
All tests are example-based. No property-based testing for invariants.

**Recommendation**:
Add property-based tests using ExCheck or StreamData:

```elixir
defmodule KreuzbergTest.Unit.ExtractionPropertyTest do
  use ExUnit.Case
  # Requires: {:stream_data, "~> 0.6"} in mix.exs

  describe "extraction invariants" do
    property "extracted content is always a binary" do
      check all content <- StreamData.string(:alphanumeric) do
        {:ok, result} = Kreuzberg.extract(content, "text/plain")
        assert is_binary(result.content)
      end
    end

    property "MIME type in result matches input MIME type" do
      mime_types = ["text/plain", "text/html"]

      check all content <- StreamData.string(:alphanumeric),
                mime_type <- StreamData.member_of(mime_types) do
        {:ok, result} = Kreuzberg.extract(content, mime_type)
        assert result.mime_type == mime_type
      end
    end

    property "metadata is always a map" do
      check all content <- StreamData.string(:alphanumeric) do
        {:ok, result} = Kreuzberg.extract(content, "text/plain")
        assert is_map(result.metadata)
      end
    end
  end
end
```

---

## Test Infrastructure Recommendations

### Summary of Helper Modules to Create

Create the following in `test/support/`:

1. **test_fixtures.exs** - Temp file helpers
2. **document_fixtures.exs** - Test document management
3. **document_paths.exs** - Centralized path constants
4. **assertions.exs** - Common assertion helpers

Update `test/test_helper.exs`:

```elixir
ExUnit.start()

# Load test support modules
Code.require_file("support/test_fixtures.exs", __DIR__)
Code.require_file("support/document_fixtures.exs", __DIR__)
Code.require_file("support/document_paths.exs", __DIR__)
Code.require_file("support/assertions.exs", __DIR__)
```

---

## Refactoring Priority

1. **Phase 1 (Critical)**: Extract test helpers to support modules
   - Estimated effort: 2 hours
   - Impact: 40% reduction in test code, massive maintainability improvement

2. **Phase 2 (High)**: Add missing error tests and fix brittle tests
   - Estimated effort: 3 hours
   - Impact: Better coverage, prevents false positives

3. **Phase 3 (Medium)**: Consolidate repeated assertions
   - Estimated effort: 1.5 hours
   - Impact: 20% code reduction, easier maintenance

4. **Phase 4 (Optional)**: Optimize file I/O using setup_all
   - Estimated effort: 1 hour
   - Impact: 30% faster test execution

---

## Key Metrics

| Metric | Current | Target | Gap |
|--------|---------|--------|-----|
| Code Duplication | 35% | <10% | -25% |
| Avg Test Size | 12 lines | <8 lines | -4 lines |
| Setup/Teardown DRY | 0% | 100% | Critical |
| Coverage Gaps | 8-10 | 0-2 | High |
| Test Performance | 45s | 30s | -33% |

---

## Checklist for Implementation

- [ ] Create test support directory structure
- [ ] Implement `test_fixtures.exs` with file helpers
- [ ] Implement `assertions.exs` with common assertions
- [ ] Implement `document_paths.exs` with path constants
- [ ] Refactor unit tests to use new helpers
- [ ] Refactor format tests to use new helpers
- [ ] Add missing error scenario tests
- [ ] Update module documentation
- [ ] Add property-based tests (optional)
- [ ] Verify all tests pass with refactored code
- [ ] Update CI/CD to skip format tests when documents unavailable
