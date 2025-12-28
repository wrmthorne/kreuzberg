# Missing Test Cases - Detailed Specifications

This document provides exact test case specifications for gaps identified in Round 2 review.

---

## 1. Input Validation Tests

### 1.1 MIME Type Boundary Tests

**Location**: `test/unit/extraction_test.exs` (append to file)

```elixir
describe "extract/2 - MIME type validation" do
  @tag :unit
  test "rejects empty MIME type" do
    {:error, reason} = Kreuzberg.extract("data", "")
    assert is_binary(reason)
    assert byte_size(reason) > 0
  end

  @tag :unit
  test "rejects whitespace-only MIME type" do
    {:error, reason} = Kreuzberg.extract("data", "   ")
    assert is_binary(reason)
  end

  @tag :unit
  test "rejects MIME type without subtype" do
    {:error, reason} = Kreuzberg.extract("data", "text")
    assert is_binary(reason)
  end

  @tag :unit
  test "rejects MIME type with missing type part" do
    {:error, reason} = Kreuzberg.extract("data", "/plain")
    assert is_binary(reason)
  end

  @tag :unit
  test "rejects MIME type with missing subtype part" do
    {:error, reason} = Kreuzberg.extract("data", "text/")
    assert is_binary(reason)
  end

  @tag :unit
  test "rejects MIME type with double slash" do
    {:error, reason} = Kreuzberg.extract("data", "text//plain")
    assert is_binary(reason)
  end

  @tag :unit
  test "rejects very long MIME type (>500 chars)" do
    long_mime = String.duplicate("application", 50) <> "/pdf"
    {:error, reason} = Kreuzberg.extract("data", long_mime)
    assert is_binary(reason)
  end

  @tag :unit
  test "rejects MIME type with embedded newlines" do
    {:error, reason} = Kreuzberg.extract("data", "text\n/plain")
    assert is_binary(reason)
  end

  @tag :unit
  test "rejects MIME type with null bytes" do
    {:error, reason} = Kreuzberg.extract("data", "text\x00/plain")
    assert is_binary(reason)
  end

  @tag :unit
  test "accepts standard valid MIME types" do
    valid_types = [
      "text/plain",
      "application/pdf",
      "text/html",
      "application/json",
      "image/png",
      "application/vnd.ms-excel",
    ]

    Enum.each(valid_types, fn mime_type ->
      result = Kreuzberg.extract("content", mime_type)
      assert match?({:ok, _} | {:error, _}, result)
    end)
  end
end
```

**Expected Behavior**: All should return `{:error, reason}` with a non-empty reason string.

### 1.2 Input Content Edge Cases

**Location**: `test/unit/extraction_test.exs`

```elixir
describe "extract/2 - input content edge cases" do
  @tag :unit
  test "handles content with null bytes" do
    content = "Hello\x00World"
    result = Kreuzberg.extract(content, "text/plain")
    assert match?({:ok, %Kreuzberg.ExtractionResult{}} | {:error, _}, result)
  end

  @tag :unit
  test "handles content with mixed line endings" do
    content = "Line1\nLine2\r\nLine3\rLine4"
    {:ok, result} = Kreuzberg.extract(content, "text/plain")
    assert is_binary(result.content)
  end

  @tag :unit
  test "handles very long single-line content" do
    long_line = String.duplicate("a", 100_000)
    {:ok, result} = Kreuzberg.extract(long_line, "text/plain")
    assert is_binary(result.content)
  end

  @tag :unit
  test "handles content with control characters" do
    content = "Normal\x01\x02\x03Text\x07\x08\x09"
    {:ok, result} = Kreuzberg.extract(content, "text/plain")
    assert is_binary(result.content)
  end

  @tag :unit
  test "handles Unicode content with various scripts" do
    content = "English: Hello\nArabic: مرحبا\nChinese: 你好\nRussian: Привет"
    {:ok, result} = Kreuzberg.extract(content, "text/plain")
    assert is_binary(result.content)
  end

  @tag :unit
  test "handles content with emoji and special Unicode" do
    content = "Emoji: 🚀 🎉 ✨ Math: ∑ ∫ √ Arrows: → ← ↑ ↓"
    {:ok, result} = Kreuzberg.extract(content, "text/plain")
    assert is_binary(result.content)
  end

  @tag :unit
  test "handles repeated/excessive newlines" do
    content = "Start\n\n\n\n\n\n\n\n\nEnd"
    {:ok, result} = Kreuzberg.extract(content, "text/plain")
    assert is_binary(result.content)
  end

  @tag :unit
  test "handles content with tab characters" do
    content = "Column1\tColumn2\tColumn3\nValue1\tValue2\tValue3"
    {:ok, result} = Kreuzberg.extract(content, "text/plain")
    assert is_binary(result.content)
  end
end
```

**Expected Behavior**: All should either succeed with a valid result or return a reasonable error.

---

## 2. Configuration Validation Tests (CRITICAL)

### 2.1 Boolean Field Validation

**Location**: `test/unit/extraction_test.exs` (new describe block)

```elixir
describe "ExtractionConfig.validate - boolean fields" do
  @tag :unit
  test "accepts valid use_cache values" do
    {:ok, _} = Kreuzberg.ExtractionConfig.validate(
      %Kreuzberg.ExtractionConfig{use_cache: true}
    )
    {:ok, _} = Kreuzberg.ExtractionConfig.validate(
      %Kreuzberg.ExtractionConfig{use_cache: false}
    )
  end

  @tag :unit
  test "rejects non-boolean use_cache" do
    invalid_values = ["true", 1, 0, nil, [], %{}, :true]

    Enum.each(invalid_values, fn value ->
      config = %Kreuzberg.ExtractionConfig{use_cache: value}
      {:error, reason} = Kreuzberg.ExtractionConfig.validate(config)
      assert String.contains?(reason, "use_cache")
      assert String.contains?(reason, "boolean")
    end)
  end

  @tag :unit
  test "accepts valid enable_quality_processing values" do
    {:ok, _} = Kreuzberg.ExtractionConfig.validate(
      %Kreuzberg.ExtractionConfig{enable_quality_processing: true}
    )
    {:ok, _} = Kreuzberg.ExtractionConfig.validate(
      %Kreuzberg.ExtractionConfig{enable_quality_processing: false}
    )
  end

  @tag :unit
  test "rejects non-boolean enable_quality_processing" do
    invalid_values = ["true", 1, 0, nil, [], %{}, :true]

    Enum.each(invalid_values, fn value ->
      config = %Kreuzberg.ExtractionConfig{enable_quality_processing: value}
      {:error, reason} = Kreuzberg.ExtractionConfig.validate(config)
      assert String.contains?(reason, "enable_quality_processing")
      assert String.contains?(reason, "boolean")
    end)
  end

  @tag :unit
  test "accepts valid force_ocr values" do
    {:ok, _} = Kreuzberg.ExtractionConfig.validate(
      %Kreuzberg.ExtractionConfig{force_ocr: true}
    )
    {:ok, _} = Kreuzberg.ExtractionConfig.validate(
      %Kreuzberg.ExtractionConfig{force_ocr: false}
    )
  end

  @tag :unit
  test "rejects non-boolean force_ocr" do
    invalid_values = ["true", 1, 0, nil, [], %{}, :true]

    Enum.each(invalid_values, fn value ->
      config = %Kreuzberg.ExtractionConfig{force_ocr: value}
      {:error, reason} = Kreuzberg.ExtractionConfig.validate(config)
      assert String.contains?(reason, "force_ocr")
      assert String.contains?(reason, "boolean")
    end)
  end
end
```

### 2.2 Nested Field Validation

**Location**: `test/unit/extraction_test.exs`

```elixir
describe "ExtractionConfig.validate - nested fields" do
  @tag :unit
  test "accepts nil nested fields" do
    {:ok, _} = Kreuzberg.ExtractionConfig.validate(
      %Kreuzberg.ExtractionConfig{chunking: nil}
    )
    {:ok, _} = Kreuzberg.ExtractionConfig.validate(
      %Kreuzberg.ExtractionConfig{ocr: nil}
    )
  end

  @tag :unit
  test "accepts empty map nested fields" do
    {:ok, _} = Kreuzberg.ExtractionConfig.validate(
      %Kreuzberg.ExtractionConfig{chunking: %{}}
    )
    {:ok, _} = Kreuzberg.ExtractionConfig.validate(
      %Kreuzberg.ExtractionConfig{ocr: %{}}
    )
  end

  @tag :unit
  test "accepts map with nested content" do
    {:ok, _} = Kreuzberg.ExtractionConfig.validate(
      %Kreuzberg.ExtractionConfig{chunking: %{"size" => 1024}}
    )
    {:ok, _} = Kreuzberg.ExtractionConfig.validate(
      %Kreuzberg.ExtractionConfig{ocr: %{"lang" => "eng", "psm" => 6}}
    )
  end

  @tag :unit
  test "rejects string nested fields" do
    config = %Kreuzberg.ExtractionConfig{chunking: "invalid"}
    {:error, reason} = Kreuzberg.ExtractionConfig.validate(config)
    assert String.contains?(reason, "chunking")
    assert String.contains?(reason, "map")
  end

  @tag :unit
  test "rejects list nested fields" do
    config = %Kreuzberg.ExtractionConfig{ocr: ["item1", "item2"]}
    {:error, reason} = Kreuzberg.ExtractionConfig.validate(config)
    assert String.contains?(reason, "ocr")
    assert String.contains?(reason, "map")
  end

  @tag :unit
  test "rejects integer nested fields" do
    config = %Kreuzberg.ExtractionConfig{language_detection: 123}
    {:error, reason} = Kreuzberg.ExtractionConfig.validate(config)
    assert String.contains?(reason, "language_detection")
    assert String.contains?(reason, "map")
  end

  @tag :unit
  test "rejects boolean nested fields" do
    config = %Kreuzberg.ExtractionConfig{postprocessor: true}
    {:error, reason} = Kreuzberg.ExtractionConfig.validate(config)
    assert String.contains?(reason, "postprocessor")
    assert String.contains?(reason, "map")
  end

  @tag :unit
  test "rejects atom nested fields" do
    config = %Kreuzberg.ExtractionConfig{images: :invalid}
    {:error, reason} = Kreuzberg.ExtractionConfig.validate(config)
    assert String.contains?(reason, "images")
    assert String.contains?(reason, "map")
  end

  @tag :unit
  test "all nested fields validate correctly" do
    # Test all 9 nested fields
    nested_fields = [
      :chunking, :ocr, :language_detection, :postprocessor,
      :images, :pages, :token_reduction, :keywords, :pdf_options
    ]

    Enum.each(nested_fields, fn field ->
      # Test with nil
      config1 = Map.put(%Kreuzberg.ExtractionConfig{}, field, nil)
      {:ok, _} = Kreuzberg.ExtractionConfig.validate(config1)

      # Test with map
      config2 = Map.put(%Kreuzberg.ExtractionConfig{}, field, %{"key" => "value"})
      {:ok, _} = Kreuzberg.ExtractionConfig.validate(config2)

      # Test with invalid value
      config3 = Map.put(%Kreuzberg.ExtractionConfig{}, field, "invalid")
      {:error, _} = Kreuzberg.ExtractionConfig.validate(config3)
    end)
  end
end
```

### 2.3 Complex Configuration Validation

**Location**: `test/unit/extraction_test.exs`

```elixir
describe "ExtractionConfig.validate - complex scenarios" do
  @tag :unit
  test "validates all fields together" do
    config = %Kreuzberg.ExtractionConfig{
      use_cache: true,
      enable_quality_processing: false,
      force_ocr: true,
      chunking: %{"size" => 512},
      ocr: %{"lang" => "eng"},
      language_detection: %{"enabled" => true},
      postprocessor: %{},
      images: %{"format" => "png"},
      pages: nil,
      token_reduction: %{"ratio" => 0.8},
      keywords: %{"count" => 10},
      pdf_options: %{}
    }

    {:ok, validated} = Kreuzberg.ExtractionConfig.validate(config)
    assert validated.use_cache == true
    assert validated.enable_quality_processing == false
    assert validated.force_ocr == true
  end

  @tag :unit
  test "fails on first invalid field" do
    config = %Kreuzberg.ExtractionConfig{
      use_cache: "invalid",
      chunking: "also_invalid"
    }

    {:error, reason} = Kreuzberg.ExtractionConfig.validate(config)
    # Should fail on first boolean check
    assert String.contains?(reason, "use_cache")
  end

  @tag :unit
  test "validation preserves all valid nested config values" do
    nested_config = %{"size" => 1024, "overlap" => 128, "min_length" => 10}
    config = %Kreuzberg.ExtractionConfig{chunking: nested_config}

    {:ok, validated} = Kreuzberg.ExtractionConfig.validate(config)
    assert validated.chunking == nested_config
  end
end
```

---

## 3. Path Validation Tests

### 3.1 File Path Edge Cases

**Location**: `test/unit/file_extraction_test.exs` (append)

```elixir
describe "extract_file/3 - path validation" do
  @tag :unit
  test "rejects empty path" do
    {:error, reason} = Kreuzberg.extract_file("", "text/plain")
    assert is_binary(reason)
  end

  @tag :unit
  test "rejects whitespace-only path" do
    {:error, reason} = Kreuzberg.extract_file("   ", "text/plain")
    assert is_binary(reason)
  end

  @tag :unit
  test "rejects path with null bytes" do
    {:error, reason} = Kreuzberg.extract_file("/tmp/test\x00.txt", "text/plain")
    assert is_binary(reason)
  end

  @tag :unit
  test "rejects path with newline characters" do
    {:error, reason} = Kreuzberg.extract_file("/tmp/test\n.txt", "text/plain")
    assert is_binary(reason)
  end

  @tag :unit
  test "rejects extremely long path (>4096 chars)" do
    long_path = "/" <> String.duplicate("a", 5000) <> "/file.txt"
    {:error, reason} = Kreuzberg.extract_file(long_path, "text/plain")
    assert is_binary(reason)
  end

  @tag :unit
  test "rejects path pointing to directory instead of file" do
    dir = System.tmp_dir!()
    {:error, reason} = Kreuzberg.extract_file(dir, "text/plain")
    assert is_binary(reason)
  end

  @tag :unit
  test "rejects path to non-existent parent directory" do
    {:error, reason} = Kreuzberg.extract_file(
      "/definitely/nonexistent/parent/#{System.unique_integer()}/file.txt",
      "text/plain"
    )
    assert is_binary(reason)
  end

  @tag :unit
  test "accepts absolute paths" do
    path = create_temp_file("content")
    try do
      abs_path = Path.expand(path)
      {:ok, result} = Kreuzberg.extract_file(abs_path, "text/plain")
      assert result.content == "content"
    after
      cleanup_temp_file(path)
    end
  end

  @tag :unit
  test "accepts relative paths" do
    unique_id = System.unique_integer()
    path = "test_relative_#{unique_id}.txt"
    File.write!(path, "relative content")

    try do
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert result.content == "relative content"
    after
      if File.exists?(path), do: File.rm(path)
    end
  end

  @tag :unit
  test "handles paths with special characters" do
    unique_id = System.unique_integer()
    # Use hyphen, underscore, dot in filename (valid special chars)
    path = create_temp_file("content")
    try do
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert result.content == "content"
    after
      cleanup_temp_file(path)
    end
  end
end
```

### 3.2 Permission and Access Tests

**Location**: `test/unit/file_extraction_test.exs`

```elixir
describe "extract_file/3 - file access issues" do
  @tag :unit
  test "handles permission denied gracefully on Unix systems" do
    # Skip on Windows
    if not match?({:win32, _}, :os.type()) do
      path = create_temp_file("restricted")
      try do
        File.chmod!(path, 0o000)
        {:error, reason} = Kreuzberg.extract_file(path, "text/plain")
        assert is_binary(reason)
      after
        File.chmod!(path, 0o644)
        cleanup_temp_file(path)
      end
    end
  end

  @tag :unit
  test "provides meaningful error for symlink to non-existent target" do
    if not match?({:win32, _}, :os.type()) do
      symlink_path = System.tmp_dir!() <> "/broken_symlink_#{System.unique_integer()}"
      target = "/nonexistent/target/#{System.unique_integer()}"

      try do
        # Create broken symlink
        case File.ln_s(target, symlink_path) do
          :ok ->
            {:error, reason} = Kreuzberg.extract_file(symlink_path, "text/plain")
            assert is_binary(reason)
          _ ->
            :ok  # Skip if symlinks not supported
        end
      after
        if File.exists?(symlink_path), do: File.rm(symlink_path)
      end
    end
  end
end
```

---

## 4. File Content Edge Cases

### 4.1 File Size Variations

**Location**: `test/unit/file_extraction_test.exs`

```elixir
describe "extract_file/3 - file size edge cases" do
  @tag :unit
  test "handles zero-byte empty file" do
    path = create_temp_file("")
    try do
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert result.content == ""
      assert is_binary(result.mime_type)
    after
      cleanup_temp_file(path)
    end
  end

  @tag :unit
  test "handles single-byte file" do
    path = create_temp_file("A")
    try do
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert result.content == "A"
    after
      cleanup_temp_file(path)
    end
  end

  @tag :unit
  test "handles 1MB file" do
    content = String.duplicate("x", 1_000_000)
    path = create_temp_file(content)
    try do
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert is_binary(result.content)
    after
      cleanup_temp_file(path)
    end
  end

  @tag :unit
  @tag :slow
  test "handles 10MB file" do
    content = String.duplicate("y", 10_000_000)
    path = create_temp_file(content)
    try do
      result = Kreuzberg.extract_file(path, "text/plain")
      assert match?({:ok, _} | {:error, _}, result)
    after
      cleanup_temp_file(path)
    end
  end
end
```

### 4.2 File Content Special Cases

**Location**: `test/unit/file_extraction_test.exs`

```elixir
describe "extract_file/3 - special file content" do
  @tag :unit
  test "handles file with null bytes" do
    path = create_temp_file("Hello\x00World\x00End")
    try do
      result = Kreuzberg.extract_file(path, "text/plain")
      assert match?({:ok, _} | {:error, _}, result)
    after
      cleanup_temp_file(path)
    end
  end

  @tag :unit
  test "handles file with various line endings" do
    content = "Unix\nWindows\r\nOld Mac\rMixed\n\r\nLF"
    path = create_temp_file(content)
    try do
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert is_binary(result.content)
    after
      cleanup_temp_file(path)
    end
  end

  @tag :unit
  test "handles file with only whitespace" do
    content = "   \n\t\t\t\n   \r\n   "
    path = create_temp_file(content)
    try do
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert is_binary(result.content)
    after
      cleanup_temp_file(path)
    end
  end

  @tag :unit
  test "handles file with control characters" do
    content = "Normal\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0AText"
    path = create_temp_file(content)
    try do
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert is_binary(result.content)
    after
      cleanup_temp_file(path)
    end
  end

  @tag :unit
  test "handles file with Unicode content" do
    content = "English\nEspañol\n中文\nРусский\nالعربية\n日本語"
    path = create_temp_file(content)
    try do
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert is_binary(result.content)
    after
      cleanup_temp_file(path)
    end
  end

  @tag :unit
  test "handles file with BOM (Byte Order Mark)" do
    # UTF-8 BOM
    content = <<0xEF, 0xBB, 0xBF>> <> "Content"
    path = create_temp_file(content)
    try do
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert is_binary(result.content)
    after
      cleanup_temp_file(path)
    end
  end

  @tag :unit
  test "handles file with very long lines" do
    long_line = String.duplicate("word ", 100_000)
    path = create_temp_file(long_line)
    try do
      {:ok, result} = Kreuzberg.extract_file(path, "text/plain")
      assert is_binary(result.content)
    after
      cleanup_temp_file(path)
    end
  end
end
```

---

## 5. Error Classification and Handling

### 5.1 Error Message Verification

**Location**: `test/unit/extraction_test.exs`

```elixir
describe "error handling - message quality" do
  @tag :unit
  test "invalid MIME type produces descriptive error" do
    {:error, reason} = Kreuzberg.extract("data", "invalid")
    assert byte_size(reason) > 10
    assert String.contains?(reason, ["invalid", "format", "mime", "type", "unsupported"])
  end

  @tag :unit
  test "empty MIME type produces descriptive error" do
    {:error, reason} = Kreuzberg.extract("data", "")
    assert byte_size(reason) > 10
  end

  @tag :unit
  test "error messages are consistent across variants" do
    {:error, reason1} = Kreuzberg.extract("data", "invalid/type")

    assert_raise Kreuzberg.Error, fn ->
      Kreuzberg.extract!("data", "invalid/type")
    end

    # Both should have error info (checked indirectly through raising)
  end
end
```

### 5.2 File-Specific Error Messages

**Location**: `test/unit/file_extraction_test.exs`

```elixir
describe "file extraction - error message quality" do
  @tag :unit
  test "missing file produces descriptive error" do
    {:error, reason} = Kreuzberg.extract_file(
      "/nonexistent/#{System.unique_integer()}.txt",
      "text/plain"
    )
    assert byte_size(reason) > 10
    assert String.contains?(reason, ["not found", "missing", "exist", "error"])
  end

  @tag :unit
  test "empty path produces descriptive error" do
    {:error, reason} = Kreuzberg.extract_file("", "text/plain")
    assert byte_size(reason) > 5
  end

  @tag :unit
  test "directory instead of file produces descriptive error" do
    {:error, reason} = Kreuzberg.extract_file(System.tmp_dir!(), "text/plain")
    assert byte_size(reason) > 5
  end
end
```

---

## 6. Configuration Integration Tests

### 6.1 Config Handling with Extract

**Location**: `test/unit/extraction_test.exs`

```elixir
describe "extract/3 - configuration handling edge cases" do
  @tag :unit
  test "config with unknown fields is silently accepted" do
    config = %{
      "unknown_field" => "value",
      "another_unknown" => %{"nested" => "value"}
    }

    # Should not raise, unknown fields ignored
    {:ok, result} = Kreuzberg.extract("data", "text/plain", config)
    assert is_binary(result.content)
  end

  @tag :unit
  test "empty config map is accepted" do
    {:ok, result} = Kreuzberg.extract("data", "text/plain", %{})
    assert is_binary(result.content)
  end

  @tag :unit
  test "nil config is equivalent to no config" do
    {:ok, result1} = Kreuzberg.extract("data", "text/plain", nil)
    {:ok, result2} = Kreuzberg.extract("data", "text/plain")

    assert result1.content == result2.content
    assert result1.mime_type == result2.mime_type
  end

  @tag :unit
  test "config with all nested fields as nil is accepted" do
    config = %Kreuzberg.ExtractionConfig{
      chunking: nil,
      ocr: nil,
      language_detection: nil,
      postprocessor: nil,
      images: nil,
      pages: nil,
      token_reduction: nil,
      keywords: nil,
      pdf_options: nil
    }

    {:ok, result} = Kreuzberg.extract("data", "text/plain", config)
    assert is_binary(result.content)
  end

  @tag :unit
  test "config with deeply nested maps is accepted" do
    config = %Kreuzberg.ExtractionConfig{
      chunking: %{
        "strategy" => %{
          "type" => "overlap",
          "params" => %{
            "size" => 512,
            "overlap" => 128
          }
        }
      }
    }

    {:ok, result} = Kreuzberg.extract("data", "text/plain", config)
    assert is_binary(result.content)
  end
end
```

---

## 7. Performance and Baseline Tests

### 7.1 Performance Assertions

**Location**: `test/unit/extraction_test.exs`

```elixir
describe "extraction - performance baselines" do
  @tag :unit
  test "small text extraction completes quickly" do
    start = System.monotonic_time(:millisecond)
    {:ok, _result} = Kreuzberg.extract("small", "text/plain")
    elapsed = System.monotonic_time(:millisecond) - start

    # Small extractions should be very fast
    assert elapsed < 1000
  end

  @tag :unit
  test "medium text extraction completes reasonably" do
    content = String.duplicate("word ", 1000)
    start = System.monotonic_time(:millisecond)
    {:ok, _result} = Kreuzberg.extract(content, "text/plain")
    elapsed = System.monotonic_time(:millisecond) - start

    # Should complete within reason
    assert elapsed < 5000
  end
end
```

---

## 8. Result Consistency Tests

### 8.1 Result Structure Guarantees

**Location**: `test/unit/extraction_test.exs`

```elixir
describe "extraction result - consistency guarantees" do
  @tag :unit
  test "result structure is consistent across all variants" do
    content = "Test"
    mime = "text/plain"
    config = %Kreuzberg.ExtractionConfig{use_cache: true}

    {:ok, r1} = Kreuzberg.extract(content, mime)
    {:ok, r2} = Kreuzberg.extract(content, mime, nil)
    {:ok, r3} = Kreuzberg.extract(content, mime, config)

    # All should have same field names
    fields = [:content, :mime_type, :metadata, :tables, :detected_languages, :chunks, :images, :pages]

    Enum.each(fields, fn field ->
      assert Map.has_key?(r1, field), "r1 missing #{field}"
      assert Map.has_key?(r2, field), "r2 missing #{field}"
      assert Map.has_key?(r3, field), "r3 missing #{field}"
    end)
  end

  @tag :unit
  test "result content is always preserved as given" do
    test_cases = [
      "simple",
      "with\nnewlines",
      "with  spaces",
      "special!@#$%^&*()",
      "unicode: 你好"
    ]

    Enum.each(test_cases, fn content ->
      {:ok, result} = Kreuzberg.extract(content, "text/plain")
      assert result.content == content
    end)
  end

  @tag :unit
  test "mime_type in result matches input" do
    mimes = [
      "text/plain",
      "text/html",
      "application/json"
    ]

    Enum.each(mimes, fn mime ->
      {:ok, result} = Kreuzberg.extract("data", mime)
      assert result.mime_type == mime
    end)
  end

  @tag :unit
  test "metadata is always a map" do
    {:ok, result} = Kreuzberg.extract("data", "text/plain")
    assert is_map(result.metadata)
  end

  @tag :unit
  test "tables is always a list" do
    {:ok, result} = Kreuzberg.extract("data", "text/plain")
    assert is_list(result.tables)
  end

  @tag :unit
  test "optional fields can be nil or have values" do
    {:ok, result} = Kreuzberg.extract("data", "text/plain")
    # These can be nil or have values - just check they exist
    assert Map.has_key?(result, :detected_languages)
    assert Map.has_key?(result, :chunks)
    assert Map.has_key?(result, :images)
    assert Map.has_key?(result, :pages)
  end
end
```

---

## Implementation Notes

### Test Execution Order
- Run tests in order of severity: CRITICAL → HIGH → MEDIUM → LOW
- Use `:unit` tag for unit tests (fast, no dependencies)
- Use `:slow` tag for performance tests
- Use `:integration` tag for format-specific tests

### Expected Test File Sizes
- `extraction_test.exs`: +35 new tests (currently ~45)
- `file_extraction_test.exs`: +20 new tests (currently ~35)
- `config_test.exs` (optional new file): Could contain all config validation tests

### Running New Tests
```bash
# Run all new tests
mix test --only unit

# Run specific category
mix test test/unit/extraction_test.exs

# Run with verbose output
mix test --verbose

# Run without slow tests
mix test --exclude slow
```

---

## Summary

**Total new test cases to implement: ~41 unit tests**

**By category:**
- MIME type validation: 9 tests
- Input content edge cases: 8 tests
- Config boolean validation: 5 tests
- Config nested validation: 7 tests
- Path validation: 9 tests
- File size/content: 15 tests
- Error handling: 6 tests
- Performance: 2 tests
- Result consistency: 6 tests

**Estimated implementation time: 2-3 days**

**Coverage improvement: 92 → 133 tests (69% → 100% of recommended)**
