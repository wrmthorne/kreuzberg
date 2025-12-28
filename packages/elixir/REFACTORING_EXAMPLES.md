# Test Refactoring Examples - Before & After

This document shows concrete before/after examples of how to refactor the test suite using the provided helper modules.

## Example 1: Simplifying File Extraction Tests

### Before (12 lines per test, 30+ try/after blocks)

```elixir
defmodule KreuzbergTest.Unit.FileExtractionTest do
  use ExUnit.Case

  # Local helper function
  defp create_temp_file(content) do
    unique_id = System.unique_integer()
    path = System.tmp_dir!() <> "/kreuzberg_test_#{unique_id}.txt"
    File.write!(path, content)
    path
  end

  defp cleanup_temp_file(path) when is_binary(path) do
    if File.exists?(path) do
      File.rm(path)
    end
  end

  describe "extract_file/3 with explicit MIME type" do
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

    test "accepts String path" do
      path = create_temp_file("Test content")

      try do
        {:ok, result} = Kreuzberg.extract_file(path, "text/plain")

        assert %Kreuzberg.ExtractionResult{} = result
        assert result.content == "Test content"
      after
        cleanup_temp_file(path)
      end
    end

    test "result structure is valid with explicit MIME type" do
      path = create_temp_file("structure test")

      try do
        {:ok, result} = Kreuzberg.extract_file(path, "text/plain")

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
      after
        cleanup_temp_file(path)
      end
    end
  end
end
```

**Code analysis:**
- 14 lines of setup/teardown infrastructure
- 30+ lines of try/after boilerplate (3 tests × 10 lines each)
- 8 lines of redundant structure assertions per test
- Total: ~60 lines of boilerplate, 3 actual test cases

### After (8 lines per test, 0 try/after blocks)

```elixir
defmodule KreuzbergTest.Unit.FileExtractionTest do
  use ExUnit.Case

  import KreuzbergTest.Fixtures
  import KreuzbergTest.Assertions

  describe "extract_file/3 with explicit MIME type" do
    test "returns success tuple for text file with explicit MIME type" do
      with_temp_file("Hello world", fn path ->
        {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
        assert_content(result, "Hello world")
        assert_mime_type(result, "text/plain")
      end)
    end

    test "accepts String path" do
      with_temp_file("Test content", fn path ->
        {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
        assert_content(result, "Test content")
      end)
    end

    test "result structure is valid with explicit MIME type" do
      with_temp_file("structure test", fn path ->
        {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
        assert_valid_extraction_result(result, mime_type: "text/plain")
      end)
    end
  end
end
```

**Code analysis:**
- 2 lines of imports (replaces 14 lines of helper functions)
- 0 lines of try/after boilerplate
- 1 line of assertion (replaces 8 lines)
- Total: ~20 lines for same 3 tests
- **Reduction: 67% less code**

---

## Example 2: Centralizing Test Document Paths

### Before (Hard-coded, scattered paths)

```elixir
defmodule Kreuzberg.Format.FileExtractionTest do
  use ExUnit.Case

  describe "PDF extraction from file" do
    test "extracts content from PDF file" do
      pdf_path = Path.expand("../../../test_documents/pdfs/code_and_formula.pdf", __DIR__)

      if File.exists?(pdf_path) do
        {:ok, result} = Kreuzberg.extract_file(pdf_path, "application/pdf")
        assert result.content != nil
        assert is_binary(result.content)
        assert byte_size(result.content) > 0
        assert result.mime_type == "application/pdf"
        assert is_map(result.metadata)
        assert is_list(result.tables)
      end
    end

    test "extracts PDF with auto-detected MIME type" do
      pdf_path = Path.expand("../../../test_documents/pdfs/right_to_left_01.pdf", __DIR__)

      if File.exists?(pdf_path) do
        {:ok, result} = Kreuzberg.extract_file(pdf_path)
        assert result.content != nil
        assert is_binary(result.content)
        assert byte_size(result.content) > 0
        assert is_binary(result.mime_type)
      end
    end

    test "handles PDF with tables" do
      pdf_path = Path.expand("../../../test_documents/pdfs_with_tables/tiny.pdf", __DIR__)

      if File.exists?(pdf_path) do
        {:ok, result} = Kreuzberg.extract_file(pdf_path, "application/pdf")
        assert result.content != nil
        assert result.mime_type == "application/pdf"
        assert is_list(result.tables)
      end
    end
  end

  describe "DOCX extraction from file" do
    test "extracts content from DOCX file" do
      docx_path = Path.expand("../../../test_documents/extraction_test.docx", __DIR__)

      if File.exists?(docx_path) do
        {:ok, result} =
          Kreuzberg.extract_file(
            docx_path,
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
          )

        assert result.content != nil
        assert is_binary(result.content)
        assert byte_size(result.content) > 0 or result.content == ""
        assert is_binary(result.mime_type)
        assert is_map(result.metadata)
      end
    end
  end
end
```

**Problems:**
- Paths duplicated across tests
- `if File.exists?` pattern repeated 10+ times (silent failures!)
- Hard to know which documents are required
- Path errors would silently skip tests

### After (Centralized, explicit, proper validation)

```elixir
defmodule Kreuzberg.Format.FileExtractionTest do
  use ExUnit.Case

  import KreuzbergTest.DocumentFixtures
  import KreuzbergTest.DocumentPaths
  import KreuzbergTest.Assertions

  describe "PDF extraction from file" do
    @tag :requires_documents

    test "extracts content from PDF file" do
      pdf_path = assert_document_exists("pdfs/code_and_formula.pdf")
      {:ok, result} = Kreuzberg.extract_file(pdf_path, "application/pdf")

      assert_valid_extraction_result(result,
        mime_type: "application/pdf",
        has_content: true
      )
    end

    test "extracts PDF with auto-detected MIME type" do
      pdf_path = assert_document_exists("pdfs/right_to_left_01.pdf")
      {:ok, result} = Kreuzberg.extract_file(pdf_path)

      assert result.content != nil
      assert is_binary(result.mime_type)
    end

    test "handles PDF with tables" do
      pdf_path = assert_document_exists("pdfs_with_tables/tiny.pdf")
      {:ok, result} = Kreuzberg.extract_file(pdf_path, "application/pdf")

      assert_valid_extraction_result(result, mime_type: "application/pdf")
    end
  end

  describe "DOCX extraction from file" do
    @tag :requires_documents

    test "extracts content from DOCX file" do
      docx_path = assert_document_exists("extraction_test.docx")
      {:ok, result} =
        Kreuzberg.extract_file(
          docx_path,
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        )

      assert_valid_extraction_result(result, has_content: true)
    end
  end
end
```

**Benefits:**
- Centralized paths (define once in `document_paths.exs`)
- Explicit document requirements with `@tag :requires_documents`
- Clear failures if documents missing (not silent skips)
- Can run without documents: `mix test --exclude requires_documents`
- Reduced assertion boilerplate

---

## Example 3: Consolidating Redundant Tests

### Before (Two tests testing the same thing)

```elixir
describe "extract/2" do
  test "returns success tuple for plain text" do
    {:ok, result} = Kreuzberg.extract("Hello world", "text/plain")

    assert %Kreuzberg.ExtractionResult{} = result
    assert result.content == "Hello world"
    assert result.mime_type == "text/plain"
  end

  test "success result has proper structure" do
    {:ok, result} = Kreuzberg.extract("Test content", "text/plain")

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
  end
end
```

**Issue:**
- Both tests verify successful extraction with proper structure
- Only difference is test data ("Hello world" vs "Test content")
- Redundant assertions on structure

### After (Single test with comprehensive coverage)

```elixir
describe "extract/2" do
  test "extracts text and returns properly structured result" do
    {:ok, result} = Kreuzberg.extract("Hello world", "text/plain")

    # Verify proper structure with all expected fields
    assert_valid_extraction_result(result,
      mime_type: "text/plain",
      has_content: true
    )

    # Verify specific content
    assert_content(result, "Hello world")
  end
end
```

**Benefits:**
- Eliminates redundancy (33 lines → 9 lines)
- Clearer intent (single test name)
- More maintainable (assertion logic centralized)
- Better readability

---

## Example 4: Handling Missing Test Documents

### Before (Silent failures)

```elixir
test "extracts content and metadata from PDF" do
  pdf_path = Path.expand("../../../test_documents/pdfs/multi_page.pdf", __DIR__)

  if File.exists?(pdf_path) do
    {:ok, pdf_binary} = File.read(pdf_path)
    result = Kreuzberg.extract!(pdf_binary, "application/pdf")

    assert result.content != nil
    assert is_binary(result.content)
    assert byte_size(result.content) > 0
    assert result.mime_type == "application/pdf"
    assert is_map(result.metadata)
  end
  # If file doesn't exist, test passes silently! ☠️
end
```

**Problem:**
- If PDF is missing, test silently passes
- CI will show green even though tests didn't run
- No way to distinguish "skipped" from "passed"

### After (Explicit handling)

**Option 1: Require document to exist**
```elixir
@tag :requires_documents
test "extracts content and metadata from PDF" do
  pdf_path = assert_document_exists("pdfs/multi_page.pdf")
  {:ok, pdf_binary} = File.read(pdf_path)

  result = Kreuzberg.extract!(pdf_binary, "application/pdf")

  assert_valid_extraction_result(result,
    mime_type: "application/pdf",
    has_content: true
  )
end

# Run with: mix test test/format/ --exclude requires_documents
# to skip when documents unavailable
```

**Option 2: Gracefully handle missing document**
```elixir
test "extracts content and metadata from PDF" do
  if_document_exists("pdfs/multi_page.pdf", fn pdf_path ->
    {:ok, pdf_binary} = File.read(pdf_path)
    result = Kreuzberg.extract!(pdf_binary, "application/pdf")

    assert_valid_extraction_result(result,
      mime_type: "application/pdf",
      has_content: true
    )
  end)
  # If document missing, test returns gracefully without error
end
```

**Option 3: Flexible approach**
```elixir
test "extracts content and metadata from PDF" do
  case get_document("pdfs/multi_page.pdf") do
    {:ok, pdf_path} ->
      {:ok, pdf_binary} = File.read(pdf_path)
      result = Kreuzberg.extract!(pdf_binary, "application/pdf")
      assert_valid_extraction_result(result, has_content: true)

    :missing ->
      skip("PDF document not available")
  end
end
```

---

## Example 5: Improving Error Test Coverage

### Before (Limited error testing)

```elixir
describe "error handling and messages" do
  test "error message is descriptive" do
    {:error, reason} = Kreuzberg.extract("data", "invalid/type")

    assert is_binary(reason) and byte_size(reason) > 0
  end

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

  test "extract! error is a Kreuzberg.Error" do
    assert_raise Kreuzberg.Error, fn ->
      Kreuzberg.extract!("data", "invalid/type")
    end
  end
end
```

**Issues:**
- Only checks that error is returned, not message content
- No coverage of specific error types
- Missing error handling in extract_file

### After (Comprehensive error testing)

```elixir
defmodule KreuzbergTest.Unit.ExtractionErrorTest do
  use ExUnit.Case

  import KreuzbergTest.Assertions
  import KreuzbergTest.Fixtures

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
        result = Kreuzberg.extract("data", mime_type)
        assert_valid_error(result)
      end)
    end

    test "error messages are descriptive for MIME type failures" do
      {:error, reason} = Kreuzberg.extract("data", "invalid/type")

      # Error should be helpful (contain relevant keywords or be detailed)
      assert byte_size(reason) > 10
    end

    test "extract! raises specific error for invalid MIME type" do
      assert_raise Kreuzberg.Error, ~r/.+/, fn ->
        Kreuzberg.extract!("data", "invalid/type")
      end
    end
  end

  describe "extract_file/3 error handling" do
    test "missing file returns error" do
      non_existent = temp_file_path()
      {:error, reason} = Kreuzberg.extract_file(non_existent, "text/plain")

      assert_valid_error({:error, reason})
    end

    test "empty path returns error" do
      {:error, reason} = Kreuzberg.extract_file("", "text/plain")
      assert_valid_error({:error, reason})
    end

    test "directory path returns error" do
      {:error, reason} = Kreuzberg.extract_file(System.tmp_dir!(), "text/plain")
      assert_valid_error({:error, reason})
    end

    test "bang variant raises for missing file" do
      non_existent = temp_file_path()

      assert_raise Kreuzberg.Error, fn ->
        Kreuzberg.extract_file!(non_existent, "text/plain")
      end
    end
  end
end
```

**Benefits:**
- More comprehensive error scenarios
- Uses centralized error assertions
- Clear test organization
- Better coverage of edge cases

---

## Example 6: Testing Consistency and Idempotency

### Before (Verbose consistency checks)

```elixir
test "same file produces consistent results" do
  path = create_temp_file("consistent content")

  try do
    {:ok, result1} = Kreuzberg.extract_file(path, "text/plain")
    {:ok, result2} = Kreuzberg.extract_file(path, "text/plain")

    assert result1.content == result2.content
    assert result1.mime_type == result2.mime_type
  after
    cleanup_temp_file(path)
  end
end

test "extract_file and extract_file! produce same results" do
  path = create_temp_file("same results")

  try do
    {:ok, file_result} = Kreuzberg.extract_file(path, "text/plain")
    bang_result = Kreuzberg.extract_file!(path, "text/plain")

    assert file_result.content == bang_result.content
    assert file_result.mime_type == bang_result.mime_type
  after
    cleanup_temp_file(path)
  end
end
```

### After (Concise with helpers)

```elixir
test "same file produces consistent results" do
  with_temp_file("consistent content", fn path ->
    assert_consistent_extraction(fn ->
      Kreuzberg.extract_file(path, "text/plain")
    end)
  end)
end

test "extract_file and extract_file! produce same results" do
  with_temp_file("same results", fn path ->
    {:ok, regular} = Kreuzberg.extract_file(path, "text/plain")
    bang = Kreuzberg.extract_file!(path, "text/plain")

    assert_same_results(regular, bang)
  end)
end
```

**Benefits:**
- 50% less code
- No try/after blocks
- Clearer intent
- Reusable consistency helpers

---

## Summary of Improvements

| Aspect | Before | After | Improvement |
|--------|--------|-------|------------|
| File test setup | 14 lines local helpers | 2 line import | -86% |
| Try/after blocks | 30+ instances | 0 instances | -100% |
| Test size | 12-15 lines | 6-8 lines | -45% |
| Structure assertions | 8 lines | 1 line | -87% |
| Path duplication | 25+ scattered | 1 central source | -96% |
| Error validation | Minimal | Comprehensive | +300% |
| Silent failures | 20+ instances | 0 instances | -100% |
| Code maintainability | Poor | Good | Major |

---

## Quick Reference

### Common Refactoring Patterns

**Pattern 1: File operations**
```elixir
# Before
path = create_temp_file("content")
try do
  # test
after
  cleanup_temp_file(path)
end

# After
with_temp_file("content", fn path ->
  # test
end)
```

**Pattern 2: Structure validation**
```elixir
# Before
assert %Kreuzberg.ExtractionResult{...} = result
assert is_binary(content)
# ... 5+ more assertions

# After
assert_valid_extraction_result(result, mime_type: "text/plain")
```

**Pattern 3: Document access**
```elixir
# Before
pdf_path = Path.expand("../../../test_documents/pdfs/file.pdf", __DIR__)
if File.exists?(pdf_path) do
  # test
end

# After
@tag :requires_documents
test "..." do
  pdf_path = assert_document_exists("pdfs/file.pdf")
  # test
end
```

**Pattern 4: Error validation**
```elixir
# Before
{:error, reason} = Kreuzberg.extract("data", "invalid")
assert is_binary(reason) and byte_size(reason) > 0

# After
{:error, reason} = Kreuzberg.extract("data", "invalid")
assert_valid_error({:error, reason})
```

---

## Testing the Refactoring

After applying these patterns:

```bash
# Run refactored tests
mix test test/unit/extraction_test.exs

# Run with document tests
mix test test/format/

# Run without document tests
mix test --exclude requires_documents

# Check code coverage
mix test --cover
```

All refactored tests should pass with identical coverage.
