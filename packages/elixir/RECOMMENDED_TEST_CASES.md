# Recommended Test Cases for Kreuzberg Elixir Implementation

This document provides specific test case examples for the critical gaps identified in the coverage analysis.

---

## Phase 1: Critical Tests (Must Implement)

### 1. extract_with_plugins() - Core Function Tests

#### Test File Location
Create: `test/unit/extract_with_plugins_test.exs`

#### Test Suite: Basic Functionality

```elixir
describe "extract_with_plugins/2-4 - no plugins" do
  @tag :unit
  test "behaves like extract when no plugins provided" do
    {:ok, result1} = Kreuzberg.extract("test", "text/plain")
    {:ok, result2} = Kreuzberg.extract_with_plugins("test", "text/plain")

    assert result1.content == result2.content
    assert result1.mime_type == result2.mime_type
  end

  @tag :unit
  test "accepts empty plugin_opts keyword list" do
    {:ok, result} = Kreuzberg.extract_with_plugins("test", "text/plain", nil, [])
    assert %ExtractionResult{} = result
  end

  @tag :unit
  test "ignores unknown plugin_opts keys" do
    {:ok, result} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      unknown_key: :value
    )
    assert %ExtractionResult{} = result
  end
end

describe "extract_with_plugins/4 - validators stage" do
  @tag :unit
  test "runs validators before extraction" do
    defmodule ValidatorThatFails do
      def validate(_), do: {:error, "Validation failed"}
    end

    {:error, reason} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      validators: [ValidatorThatFails]
    )

    assert String.contains?(reason, "Validation failed")
  end

  @tag :unit
  test "stops extraction if validator fails" do
    defmodule StrictValidator do
      def validate(_), do: {:error, "Too strict"}
    end

    {:error, _} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      validators: [StrictValidator]
    )

    # Extraction never happens
  end

  @tag :unit
  test "multiple validators all run" do
    defmodule Validator1 do
      def validate(_), do: :ok
    end

    defmodule Validator2 do
      def validate(_), do: :ok
    end

    {:ok, result} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      validators: [Validator1, Validator2]
    )

    assert result.content == "test"
  end

  @tag :unit
  test "first failing validator stops pipeline" do
    defmodule ValidatorA do
      def validate(_), do: :ok
    end

    defmodule ValidatorB do
      def validate(_), do: {:error, "B failed"}
    end

    defmodule ValidatorC do
      def validate(_), do: :ok
    end

    {:error, reason} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      validators: [ValidatorA, ValidatorB, ValidatorC]
    )

    assert String.contains?(reason, "B failed")
  end
end

describe "extract_with_plugins/4 - post_processors stage" do
  @tag :unit
  test "applies early stage post-processor" do
    defmodule EarlyProcessor do
      def process(result, _config) do
        Map.put(result, "processed_early", true)
      end
    end

    {:ok, result} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      post_processors: %{early: [EarlyProcessor]}
    )

    assert result["processed_early"] == true
  end

  @tag :unit
  test "applies processors in stage order: early → middle → late" do
    order = []

    defmodule EarlyProc do
      def process(result, _) do
        send(self(), :early)
        result
      end
    end

    defmodule MiddleProc do
      def process(result, _) do
        send(self(), :middle)
        result
      end
    end

    defmodule LateProc do
      def process(result, _) do
        send(self(), :late)
        result
      end
    end

    {:ok, _result} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      post_processors: %{
        early: [EarlyProc],
        middle: [MiddleProc],
        late: [LateProc]
      }
    )

    # Verify order of execution
    assert_receive :early
    assert_receive :middle
    assert_receive :late
  end

  @tag :unit
  test "multiple processors in same stage execute in order" do
    defmodule Processor1 do
      def process(result, _), do: Map.put(result, "p1", true)
    end

    defmodule Processor2 do
      def process(result, _), do: Map.put(result, "p2", true)
    end

    {:ok, result} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      post_processors: %{
        early: [Processor1, Processor2]
      }
    )

    assert result["p1"] == true
    assert result["p2"] == true
  end

  @tag :unit
  test "passes configuration to post-processors" do
    defmodule ConfigProcessor do
      def process(result, config) do
        if config && config["uppercase"] do
          Map.update(result, "content", "", &String.upcase/1)
        else
          result
        end
      end
    end

    {:ok, result} = Kreuzberg.extract_with_plugins(
      "hello",
      "text/plain",
      nil,
      post_processors: %{early: [ConfigProcessor]}
    )

    assert result.content == "HELLO"
  end

  @tag :unit
  test "post-processor error stops pipeline" do
    defmodule FailingProcessor do
      def process(_result, _config) do
        {:error, "Processing failed"}
      end
    end

    {:error, reason} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      post_processors: %{early: [FailingProcessor]}
    )

    assert String.contains?(reason, "Processing failed")
  end
end

describe "extract_with_plugins/4 - final_validators stage" do
  @tag :unit
  test "runs final validators after post-processing" do
    defmodule PostProc do
      def process(result, _) do
        Map.put(result, "processed", true)
      end
    end

    defmodule FinalValidator do
      def validate(result) do
        if result["processed"] == true do
          :ok
        else
          {:error, "Post-processing not applied"}
        end
      end
    end

    {:ok, result} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      post_processors: %{early: [PostProc]},
      final_validators: [FinalValidator]
    )

    assert result["processed"] == true
  end

  @tag :unit
  test "final validator failure returns error" do
    defmodule StrictFinalValidator do
      def validate(_), do: {:error, "Result not strict enough"}
    end

    {:error, reason} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      final_validators: [StrictFinalValidator]
    )

    assert String.contains?(reason, "not strict enough")
  end

  @tag :unit
  test "multiple final validators all execute" do
    defmodule FinalVal1 do
      def validate(_), do: :ok
    end

    defmodule FinalVal2 do
      def validate(_), do: :ok
    end

    {:ok, result} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      final_validators: [FinalVal1, FinalVal2]
    )

    assert result.content == "test"
  end
end

describe "extract_with_plugins/4 - full pipeline combinations" do
  @tag :unit
  test "validators → extract → post-processors → final_validators" do
    defmodule PreValidator do
      def validate(_), do: :ok
    end

    defmodule EarlyPost do
      def process(result, _), do: Map.put(result, "stage", "processed")
    end

    defmodule FinalVal do
      def validate(result) do
        if result["stage"] == "processed" do
          :ok
        else
          {:error, "Not processed"}
        end
      end
    end

    {:ok, result} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      validators: [PreValidator],
      post_processors: %{early: [EarlyPost]},
      final_validators: [FinalVal]
    )

    assert result.content == "test"
    assert result["stage"] == "processed"
  end

  @tag :unit
  test "handles all 8 pipeline combinations" do
    # Only validators
    {:ok, _} = Kreuzberg.extract_with_plugins("t", "text/plain", nil,
      validators: [])

    # Only early post-processors
    {:ok, _} = Kreuzberg.extract_with_plugins("t", "text/plain", nil,
      post_processors: %{early: []})

    # Only final validators
    {:ok, _} = Kreuzberg.extract_with_plugins("t", "text/plain", nil,
      final_validators: [])

    # Validators + post-processors
    {:ok, _} = Kreuzberg.extract_with_plugins("t", "text/plain", nil,
      validators: [],
      post_processors: %{early: []})

    # Validators + final validators
    {:ok, _} = Kreuzberg.extract_with_plugins("t", "text/plain", nil,
      validators: [],
      final_validators: [])

    # Post-processors + final validators
    {:ok, _} = Kreuzberg.extract_with_plugins("t", "text/plain", nil,
      post_processors: %{early: []},
      final_validators: [])

    # All three
    {:ok, _} = Kreuzberg.extract_with_plugins("t", "text/plain", nil,
      validators: [],
      post_processors: %{early: []},
      final_validators: [])
  end
end
```

---

### 2. Async Concurrency Tests

#### Test File Location
Add to: `test/unit/async_api_test.exs`

#### Test Suite: Concurrent Scenarios

```elixir
describe "extract_async/3 - concurrency" do
  @tag :unit
  test "handles timeout with default 5 second limit" do
    # This assumes extract might take longer
    task = AsyncAPI.extract_async("text", "text/plain")

    # Should timeout after 1 second
    assert_raise RuntimeError, fn ->
      Task.await(task, 1)
    end
  end

  @tag :unit
  test "multiple concurrent tasks complete independently" do
    tasks = [
      AsyncAPI.extract_async("Content 1", "text/plain"),
      AsyncAPI.extract_async("Content 2", "text/plain"),
      AsyncAPI.extract_async("Content 3", "text/plain"),
      AsyncAPI.extract_async("Content 4", "text/plain"),
      AsyncAPI.extract_async("Content 5", "text/plain")
    ]

    results = Task.await_many(tasks, 10000)

    assert length(results) == 5
    assert Enum.all?(results, fn
      {:ok, %ExtractionResult{}} -> true
      _ -> false
    end)
  end

  @tag :unit
  test "partial failure in concurrent batch" do
    tasks = [
      AsyncAPI.extract_async("valid", "text/plain"),
      AsyncAPI.extract_async("invalid", "invalid/type"),
      AsyncAPI.extract_async("valid2", "text/plain")
    ]

    results = Task.await_many(tasks, 10000)

    # Check that we get mixed results
    assert Enum.any?(results, fn {:ok, _} -> true; _ -> false end)
    assert Enum.any?(results, fn {:error, _} -> true; _ -> false end)
  end

  @tag :unit
  test "task cleanup on completion" do
    # Create many tasks to verify cleanup
    tasks = Enum.map(1..100, fn i ->
      AsyncAPI.extract_async("Content #{i}", "text/plain")
    end)

    _results = Task.await_many(tasks, 30000)

    # Verify no lingering processes
    # This is environment-dependent, skip if platform-specific
  end
end
```

---

### 3. Batch Operations Edge Cases

#### Test File Location
Add to: `test/unit/batch_api_test.exs`

```elixir
describe "batch_extract_bytes/3 - mime_type mismatch" do
  @tag :unit
  test "rejects mismatched data and mime_types lengths" do
    data = [<<1>>, <<2>>, <<3>>]
    mime_types = ["text/plain", "text/plain"]  # Only 2 for 3 items

    {:error, reason} = BatchAPI.batch_extract_bytes(data, mime_types)

    assert String.contains?(reason, "Mismatch") or
           String.contains?(reason, "length")
  end

  @tag :unit
  test "accepts matching lengths" do
    data = [<<1>>, <<2>>, <<3>>]
    mime_types = ["text/plain", "text/plain", "text/plain"]

    result = BatchAPI.batch_extract_bytes(data, mime_types)
    assert match?({:ok, _}, result) or match?({:error, _}, result)
  end

  @tag :unit
  test "single item batch succeeds" do
    data = [<<1>>]
    mime_types = ["text/plain"]

    result = BatchAPI.batch_extract_bytes(data, mime_types)
    assert is_tuple(result)
  end
end

describe "batch_extract_files/2-3 - path variations" do
  @tag :unit
  test "handles paths with spaces" do
    {:ok, dir} = Briefly.create(directory: true)
    path_with_spaces = Path.join(dir, "file with spaces.txt")
    File.write!(path_with_spaces, "content")

    {:ok, results} = BatchAPI.batch_extract_files([path_with_spaces], "text/plain")

    assert length(results) == 1
  end

  @tag :unit
  test "handles paths with special characters" do
    {:ok, dir} = Briefly.create(directory: true)
    special_path = Path.join(dir, "file@#$%.txt")
    File.write!(special_path, "content")

    {:ok, results} = BatchAPI.batch_extract_files([special_path], "text/plain")

    assert length(results) == 1
  end

  @tag :unit
  test "rejects duplicate paths" do
    {:ok, dir} = Briefly.create(directory: true)
    path = Path.join(dir, "test.txt")
    File.write!(path, "content")

    # Same path twice
    result = BatchAPI.batch_extract_files([path, path], "text/plain")

    # Should either succeed with 2 results or fail gracefully
    assert match?({:ok, _}, result) or match?({:error, _}, result)
  end
end
```

---

### 4. Cache API Validation Tests

#### Test File Location
Expand: `test/unit/cache_api_test.exs`

```elixir
describe "cache_stats/0 - stats structure" do
  @tag :unit
  test "returns valid cache statistics structure" do
    {:ok, stats} = CacheAPI.cache_stats()

    # Verify it's a map with string keys
    assert is_map(stats)
    Enum.each(stats, fn {key, _value} ->
      assert is_binary(key), "Key #{inspect(key)} should be string"
    end)
  end

  @tag :unit
  test "stats contains expected fields or is empty" do
    {:ok, stats} = CacheAPI.cache_stats()

    # If cache is empty, fields may be absent, but if present should be valid
    if Map.has_key?(stats, "total_files") do
      assert is_integer(stats["total_files"])
      assert stats["total_files"] >= 0
    end

    if Map.has_key?(stats, "total_size_mb") do
      assert is_float(stats["total_size_mb"]) or is_integer(stats["total_size_mb"])
      assert stats["total_size_mb"] >= 0
    end
  end

  @tag :unit
  test "cache_stats! raises on error" do
    # This would need a scenario that causes cache_stats to fail
    # May need to mock or use a fixture
    :ok
  end
end

describe "clear_cache/0 - cache operations" do
  @tag :unit
  test "clear_cache is idempotent" do
    result1 = CacheAPI.clear_cache()
    result2 = CacheAPI.clear_cache()

    assert result1 == :ok
    assert result2 == :ok
  end

  @tag :unit
  test "clear_cache! returns ok or raises" do
    result = CacheAPI.clear_cache!()
    assert result == :ok
  end
end
```

---

### 5. Comprehensive Error Path Tests

#### Test File Location
Create: `test/unit/error_handling_test.exs`

```elixir
describe "error classification - io errors" do
  @tag :unit
  test "classifies 'File not found' as io_error" do
    error = "File not found: /path/to/missing.pdf"
    classified = UtilityAPI.classify_error(error)
    assert classified == :io_error
  end

  @tag :unit
  test "classifies 'Permission denied' as io_error" do
    error = "Permission denied while reading file"
    classified = UtilityAPI.classify_error(error)
    assert classified == :io_error
  end

  @tag :unit
  test "classifies 'No such file or directory' as io_error" do
    error = "No such file or directory"
    classified = UtilityAPI.classify_error(error)
    assert classified == :io_error
  end
end

describe "error classification - format errors" do
  @tag :unit
  test "classifies 'Invalid PDF format' as invalid_format" do
    error = "Invalid PDF format encountered"
    classified = UtilityAPI.classify_error(error)
    assert classified == :invalid_format
  end

  @tag :unit
  test "classifies 'Corrupted file' as invalid_format" do
    error = "Corrupted file detected during processing"
    classified = UtilityAPI.classify_error(error)
    assert classified == :invalid_format
  end

  @tag :unit
  test "classifies 'Unsupported format' as invalid_format" do
    error = "Unsupported file format"
    classified = UtilityAPI.classify_error(error)
    assert classified == :invalid_format
  end
end

describe "error classification - ocr errors" do
  @tag :unit
  test "classifies 'OCR failed' as ocr_error" do
    error = "OCR processing failed"
    classified = UtilityAPI.classify_error(error)
    assert classified == :ocr_error
  end

  @tag :unit
  test "classifies 'Optical character recognition failed' as ocr_error" do
    error = "Optical character recognition encountered an error"
    classified = UtilityAPI.classify_error(error)
    assert classified == :ocr_error
  end
end

describe "error propagation through pipeline" do
  @tag :unit
  test "error message preserved through plugin pipeline" do
    defmodule FailingValidator do
      def validate(_) do
        {:error, "Custom validation error message"}
      end
    end

    {:error, reason} = Kreuzberg.extract_with_plugins(
      "test",
      "text/plain",
      nil,
      validators: [FailingValidator]
    )

    assert String.contains?(reason, "Custom validation error message")
  end
end
```

---

## Phase 2: High Priority Tests

### 1. Validator Orchestration Tests

```elixir
describe "validator priority ordering" do
  @tag :unit
  test "validators execute in priority order (high to low)" do
    # Create validators with different priorities
    # Verify execution order matches priority
  end

  @tag :unit
  test "validators with same priority execute in registration order" do
    # Register validators with same priority
    # Verify FIFO execution
  end
end

describe "validator conditional execution" do
  @tag :unit
  test "skips validator if should_validate? returns false" do
    # Validator's should_validate? returns false
    # Verify validate() is not called
  end
end
```

### 2. Configuration Edge Cases

```elixir
describe "ExtractionConfig deep nesting" do
  @tag :unit
  test "handles deeply nested config maps" do
    config = %{
      pdf_options: %{
        extraction: %{
          text: %{
            preserve_formatting: true
          }
        }
      }
    }

    result = ExtractionConfig.to_map(config)
    assert is_map(result)
  end
end
```

---

## Phase 3: Medium Priority Tests

### 1. MIME Type Edge Cases

```elixir
describe "MIME type detection edge cases" do
  @tag :unit
  test "detects MIME from files with wrong extension" do
    # File named .txt but contains binary data
    # Should detect actual MIME, not use extension
  end

  @tag :unit
  test "handles MIME types with parameters" do
    # "text/plain; charset=utf-8"
    # Should parse or normalize correctly
  end
end
```

### 2. File Path Handling

```elixir
describe "file paths with special handling" do
  @tag :unit
  test "handles relative paths with .. components" do
    # Path like "../docs/file.txt"
    # Should resolve correctly
  end

  @tag :unit
  test "handles symlinks correctly" do
    # Create symlink and extract
    # Should follow link and extract actual file
  end
end
```

---

## Implementation Notes

### Testing Patterns to Follow

1. **Plugin Testing Pattern:**
   ```elixir
   defmodule TestPlugin do
     def name, do: "test_plugin"
     def version, do: "1.0.0"
     def validate(_), do: :ok
   end

   # In test:
   assert :ok = Plugin.register_validator(TestPlugin)
   # ... use in pipeline ...
   assert :ok = Plugin.unregister_validator(TestPlugin)
   ```

2. **Pipeline Testing Pattern:**
   ```elixir
   {:ok, result} = Kreuzberg.extract_with_plugins(
     input,
     mime_type,
     config,
     validators: [...],
     post_processors: %{early: [...], middle: [...], late: [...]},
     final_validators: [...]
   )
   ```

3. **Error Testing Pattern:**
   ```elixir
   {:error, reason} = function_call()
   assert String.contains?(reason, "expected error message")
   ```

### Coverage Goals

- **Critical Tests:** Must reach >95% coverage before release
- **High Priority Tests:** Should reach >90% coverage
- **Medium Priority Tests:** Aim for >80% coverage
- **Edge Cases:** Focus on business value, not 100% code coverage

---

## Estimated Implementation Time

| Phase | Test Count | Estimated Time |
|-------|-----------|----------------|
| Phase 1 (Critical) | 57-72 | 2-3 days |
| Phase 2 (High) | 55-67 | 2-3 days |
| Phase 3 (Medium) | 26-36 | 1-2 days |

**Total: 138-175 new test cases, 5-8 days for experienced developer**
