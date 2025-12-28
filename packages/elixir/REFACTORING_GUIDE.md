# Test Refactoring Implementation Guide

This guide provides step-by-step instructions for refactoring the Elixir Kreuzberg tests based on the critical review.

## Overview

The refactoring is divided into 4 phases with increasing complexity:

- **Phase 1 (2 hours)**: Extract helpers and refactor unit tests
- **Phase 2 (2 hours)**: Refactor format tests and add error tests
- **Phase 3 (1 hour)**: Consolidate redundant tests
- **Phase 4 (1.5 hours, optional)**: Optimize performance with setup_all

## Phase 1: Extract Helpers and Refactor Unit Tests

### Status
Support modules already created in Phase 0:
- ✓ `test/support/test_fixtures.exs`
- ✓ `test/support/assertions.exs`
- ✓ `test/support/document_paths.exs`
- ✓ `test/support/document_fixtures.exs`
- ✓ Updated `test/test_helper.exs`

### 1.1 Refactor `test/unit/extraction_test.exs`

Replace verbose structure assertions with the assertion helper.

**Before:**
```elixir
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
```

**After:**
```elixir
test "success result has proper structure" do
  {:ok, result} = Kreuzberg.extract("Test content", "text/plain")
  assert_valid_extraction_result(result, mime_type: "text/plain")
end
```

**Steps:**
1. Add import at the top of the test file:
   ```elixir
   import KreuzbergTest.Assertions
   ```

2. Replace all structure validation blocks with `assert_valid_extraction_result/1`

3. Replace error assertions:
   ```elixir
   # Before
   {:error, reason} = Kreuzberg.extract("data", "invalid/type")
   assert is_binary(reason) and byte_size(reason) > 0

   # After
   {:error, reason} = Kreuzberg.extract("data", "invalid/type")
   assert_valid_error({:error, reason})
   ```

4. Run tests:
   ```bash
   mix test test/unit/extraction_test.exs
   ```

### 1.2 Refactor `test/unit/file_extraction_test.exs`

Remove local helpers and use centralized fixture module.

**Before:**
```elixir
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

test "returns success tuple for text file with explicit MIME type" do
  path = create_temp_file("Hello world")

  try do
    {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
    assert result.content == "Hello world"
  after
    cleanup_temp_file(path)
  end
end
```

**After:**
```elixir
import KreuzbergTest.Fixtures
import KreuzbergTest.Assertions

test "returns success tuple for text file with explicit MIME type" do
  with_temp_file("Hello world", fn path ->
    {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
    assert_content(result, "Hello world")
    assert_mime_type(result, "text/plain")
  end)
end
```

**Steps:**

1. Remove local `create_temp_file/1` and `cleanup_temp_file/1` functions

2. Add imports at the top:
   ```elixir
   import KreuzbergTest.Fixtures
   import KreuzbergTest.Assertions
   ```

3. Replace every test block using the pattern:
   ```elixir
   # Pattern for single file test
   test "description" do
     with_temp_file("content", fn path ->
       # test code using path
     end)
   end

   # Pattern for multiple files
   with_temp_files(["content1", "content2"], fn [path1, path2] ->
     # test code
   end)

   # Pattern for relative path tests
   test "relative path is handled" do
     with_cwd(System.tmp_dir!(), fn ->
       with_temp_file("content", fn path ->
         # test code
       end)
     end)
   end
   ```

4. Update structure assertions:
   ```elixir
   # Before
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

   # After
   assert_valid_extraction_result(result)
   ```

5. Test consistency checks:
   ```elixir
   # Before
   {:ok, result1} = Kreuzberg.extract_file(path, "text/plain")
   {:ok, result2} = Kreuzberg.extract_file(path, "text/plain")
   assert result1.content == result2.content

   # After
   assert_consistent_extraction(fn ->
     Kreuzberg.extract_file(path, "text/plain")
   end)
   ```

6. Run tests:
   ```bash
   mix test test/unit/file_extraction_test.exs
   ```

**Expected Savings**: 250+ lines of code removed, 40+ try/after blocks eliminated

---

## Phase 2: Refactor Format Tests and Add Missing Tests

### 2.1 Refactor `test/format/pdf_extraction_test.exs`

Replace file existence checks with document fixture helpers.

**Before:**
```elixir
describe "PDF extraction" do
  test "extracts content and metadata from PDF" do
    pdf_path = Path.expand("../../../test_documents/pdfs/multi_page.pdf", __DIR__)

    if File.exists?(pdf_path) do
      {:ok, pdf_binary} = File.read(pdf_path)
      result = Kreuzberg.extract!(pdf_binary, "application/pdf")
      assert result.content != nil
      assert is_binary(result.content)
      assert byte_size(result.content) > 0
    end
  end
end
```

**After:**
```elixir
import KreuzbergTest.DocumentFixtures
import KreuzbergTest.DocumentPaths
import KreuzbergTest.Assertions

describe "PDF extraction" do
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

  test "handles missing PDF gracefully" do
    if_document_exists("pdfs/multi_page.pdf", fn _path ->
      # Only runs if document exists
    end)
  end
end
```

**Steps:**

1. Add imports at the top:
   ```elixir
   import KreuzbergTest.DocumentFixtures
   import KreuzbergTest.DocumentPaths
   import KreuzbergTest.Assertions
   ```

2. Replace all `if File.exists?(path)` checks with one of:
   - `assert_document_exists/1` for required documents
   - `if_document_exists/2` for optional tests
   - `get_document/1` for flexible handling

3. Replace hard-coded paths with document path helpers:
   ```elixir
   # Before
   pdf_path = Path.expand("../../../test_documents/pdfs/multi_page.pdf", __DIR__)

   # After
   pdf_path = assert_document_exists("pdfs/multi_page.pdf")
   # OR
   import KreuzbergTest.DocumentPaths
   pdf_path = assert_document_exists("pdfs/multi_page.pdf")
   ```

4. Use assertion helpers for result validation:
   ```elixir
   # Before
   assert result.content != nil
   assert is_binary(result.content)
   assert byte_size(result.content) > 0
   assert result.mime_type == "application/pdf"
   assert is_map(result.metadata)

   # After
   assert_valid_extraction_result(result,
     mime_type: "application/pdf",
     has_content: true
   )
   ```

5. Add `@tag :requires_documents` to tests needing external files

6. Run tests with and without documents:
   ```bash
   # Run all tests
   mix test test/format/pdf_extraction_test.exs

   # Skip tests requiring documents
   mix test test/format/pdf_extraction_test.exs --exclude requires_documents
   ```

### 2.2 Refactor `test/format/file_extraction_test.exs`

Similar to PDF test refactoring, but also reorganize describes.

**Steps:**

1. Add imports:
   ```elixir
   import KreuzbergTest.DocumentFixtures
   import KreuzbergTest.DocumentPaths
   import KreuzbergTest.Assertions
   import KreuzbergTest.Fixtures
   ```

2. Reorganize describes:
   - Keep format-specific tests (PDF, DOCX, HTML)
   - Move generic temp-file tests to unit tests
   - Use `@tag :requires_documents` for tests needing external files
   - Use `@tag :unit` for tests creating temp files

3. Replace all hard-coded path strings:
   ```elixir
   # Before
   pdf_path = Path.expand("../../../test_documents/pdfs/code_and_formula.pdf", __DIR__)

   # After
   pdf_path = assert_document_exists("pdfs/code_and_formula.pdf")
   ```

4. Example refactoring:
   ```elixir
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

     test "extracts with auto-detection" do
       pdf_path = assert_document_exists("pdfs/right_to_left_01.pdf")
       {:ok, result} = Kreuzberg.extract_file(pdf_path)

       assert result.content != nil
       assert is_binary(result.mime_type)
     end
   end

   # Move these to unit tests
   describe "multi-format extraction consistency" do
     @tag :unit

     test "consistent extraction across formats with same content" do
       with_temp_file("Test content for extraction", fn path ->
         {:ok, result1} = Kreuzberg.extract_file(path, "text/plain")
         {:ok, result2} = Kreuzberg.extract_file(path)

         assert result1.content == result2.content
       end)
     end
   end
   ```

### 2.3 Create `test/unit/extraction_error_test.exs`

New file for comprehensive error handling tests.

**Content:**
```elixir
defmodule KreuzbergTest.Unit.ExtractionErrorTest do
  use ExUnit.Case

  import KreuzbergTest.Assertions

  describe "extract/2 error handling" do
    @tag :unit

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

    test "error messages describe the problem" do
      {:error, reason} = Kreuzberg.extract("data", "invalid/type")
      assert byte_size(reason) > 10  # Should be descriptive
    end

    test "extract! raises Kreuzberg.Error" do
      assert_raise Kreuzberg.Error, fn ->
        Kreuzberg.extract!("data", "invalid/type")
      end
    end
  end

  describe "extract_file/3 error handling" do
    import KreuzbergTest.Fixtures

    @tag :unit

    test "missing file returns error" do
      non_existent = temp_file_path()
      {:error, reason} = Kreuzberg.extract_file(non_existent, "text/plain")

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

    test "bang variant raises for missing file" do
      non_existent = temp_file_path()
      assert_raise Kreuzberg.Error, fn ->
        Kreuzberg.extract_file!(non_existent, "text/plain")
      end
    end
  end
end
```

---

## Phase 3: Consolidate Redundant Tests

### 3.1 Merge Duplicate Tests in `test/unit/extraction_test.exs`

Combine tests that test the same behavior.

**Before (Lines 15-38):**
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
    assert %Kreuzberg.ExtractionResult{...} = result
    # ... more assertions
  end
end
```

**After:**
```elixir
describe "extract/2 - successful extraction" do
  test "returns properly structured result with correct content" do
    {:ok, result} = Kreuzberg.extract("Hello world", "text/plain")

    assert_valid_extraction_result(result,
      mime_type: "text/plain",
      has_content: true
    )
    assert_content(result, "Hello world")
  end
end
```

**Process:**
1. Identify tests in each describe block that test the same behavior
2. Merge them into a single test with multiple assertions
3. Keep edge case tests separate (empty input, special characters, multiline)
4. Remove redundant structure assertion tests

**Lines to consolidate in extraction_test.exs:**
- Lines 15-21 and 24-38 (basic success and structure)
- Lines 92-115 (bang variant success and structure)
- Lines 166-173 and 176-185 (struct config variants)
- Lines 235-250 and 243-261 (map config variants)

**Expected Reduction**: 30-40 lines per describe block

### 3.2 Similar consolidation in file_extraction_test.exs

Combine tests for:
- Structure validation across different scenarios
- Consistency checks
- Path type handling

---

## Phase 4: Performance Optimization (Optional)

### 4.1 Use setup_all for shared test files

Reduces file I/O in heavily-tested areas.

**Before:**
```elixir
describe "extract_file/3 with explicit MIME type" do
  test "returns success tuple" do
    path = create_temp_file("Hello world")
    try do
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert result.content == "Hello world"
    after
      cleanup_temp_file(path)
    end
  end

  test "accepts String path" do
    path = create_temp_file("Test content")
    try do
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert result.content == "Test content"
    after
      cleanup_temp_file(path)
    end
  end
end
```

**After:**
```elixir
describe "extract_file/3 with explicit MIME type" do
  setup_all do
    files = %{
      hello: create_temp_file("Hello world"),
      test_content: create_temp_file("Test content"),
      empty: create_temp_file(""),
      multiline: create_temp_file("Line 1\nLine 2"),
      special: create_temp_file("@#$%^&*()"),
    }

    on_exit(fn ->
      files |> Map.values() |> cleanup_all()
    end)

    {:ok, files: files}
  end

  test "returns success tuple", %{files: files} do
    {:ok, result} = Kreuzberg.extract_file(files.hello, "text/plain")
    assert_content(result, "Hello world")
  end

  test "accepts String path", %{files: files} do
    {:ok, result} = Kreuzberg.extract_file(files.test_content, "text/plain")
    assert_content(result, "Test content")
  end
end
```

**Benefits:**
- 30% faster test execution
- File I/O reduced from N tests to N files
- Still maintains test isolation

---

## Testing the Refactoring

### Run tests incrementally after each phase:

```bash
# Phase 1: Unit tests
mix test test/unit/extraction_test.exs
mix test test/unit/file_extraction_test.exs

# Phase 2: Format tests
mix test test/format/

# All tests
mix test

# Tests excluding documents
mix test --exclude requires_documents

# Only unit tests
mix test test/unit/
```

### Verify no regressions:

```bash
# Get baseline before refactoring
mix test --cover 2>&1 | tee baseline_coverage.txt

# After refactoring
mix test --cover

# Compare coverage reports
```

---

## Verification Checklist

After completing each phase:

- [ ] All tests pass locally
- [ ] No new warnings introduced
- [ ] Code coverage maintained or improved
- [ ] Test execution time acceptable (should improve in Phase 4)
- [ ] Module documentation updated
- [ ] No dead code or commented sections

### Post-Refactoring Validation

- [ ] Run `mix test` - all tests pass
- [ ] Run `mix test --exclude requires_documents` - passes
- [ ] Run `mix format --check-formatted` - passes
- [ ] Run `mix credo` - no new warnings
- [ ] Verify test file sizes reduced:
  ```bash
  wc -l test/unit/extraction_test.exs
  wc -l test/unit/file_extraction_test.exs
  wc -l test/format/file_extraction_test.exs
  ```

---

## Expected Improvements

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Total test lines | ~1400 | ~900 | -36% |
| Duplication | 35% | <5% | -30% |
| Setup/teardown code | 400+ lines | 50 lines | -87% |
| Test execution time | 45s | 30s | -33% |
| Coverage | 85% | 90%+ | +5% |

---

## Common Issues and Solutions

### Issue: "undefined function `assert_valid_extraction_result/1`"
**Solution**: Ensure imports are in place:
```elixir
import KreuzbergTest.Assertions
```

### Issue: Tests still creating temp files after refactoring
**Solution**: Verify you're using helpers correctly:
```elixir
# Wrong - uses old local function
path = create_temp_file("content")

# Right - uses imported helper
import KreuzbergTest.Fixtures
with_temp_file("content", fn path ->
  # test code
end)
```

### Issue: Document path resolution failing
**Solution**: Import document helpers:
```elixir
import KreuzbergTest.DocumentPaths
import KreuzbergTest.DocumentFixtures

# Now use
pdf_path = assert_document_exists("pdfs/code_and_formula.pdf")
```

### Issue: Tests fail when documents missing
**Solution**: Add `@tag :requires_documents` and run with `--exclude requires_documents`

---

## Timeline

| Phase | Task | Estimated Time | Difficulty |
|-------|------|-----------------|------------|
| 0 | Create support modules | 1.5 hours | Medium |
| 1 | Refactor unit tests | 2 hours | Easy |
| 2 | Refactor format tests | 2 hours | Medium |
| 3 | Consolidate tests | 1 hour | Medium |
| 4 | Optimize performance | 1.5 hours | Hard |
| Total | Complete refactoring | 8 hours | - |

---

## Next Steps

1. Start with Phase 1 - refactor extraction_test.exs
2. Complete Phase 1 with file_extraction_test.exs
3. Review progress and refine approach if needed
4. Complete Phase 2 with error and format tests
5. Optional: Complete Phase 3-4 for further improvements

See `TEST_REVIEW.md` for detailed analysis of each issue.
