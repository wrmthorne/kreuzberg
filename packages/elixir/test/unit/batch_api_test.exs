defmodule KreuzbergTest.Unit.BatchAPITest do
  @moduledoc """
  Unit tests for batch extraction operations.

  Tests cover:
  - batch_extract_files/2-3: Batch file extraction with success and error cases
  - batch_extract_files!/2-3: Bang variant with direct returns and exceptions
  - batch_extract_bytes/2-3: Batch binary extraction
  - batch_extract_bytes!/2-3: Bang variant for batch binary extraction
  """

  use ExUnit.Case

  alias Kreuzberg.BatchAPI
  alias Kreuzberg.ExtractionConfig

  describe "batch_extract_files/2" do
    @tag :unit
    test "returns error for empty paths list" do
      {:error, reason} = BatchAPI.batch_extract_files([])
      assert is_binary(reason)
      assert String.contains?(reason, "empty")
    end

    @tag :unit
    test "returns error for empty paths list with mime type" do
      {:error, reason} = BatchAPI.batch_extract_files([], "text/plain")
      assert is_binary(reason)
      assert String.contains?(reason, "empty")
    end

    @tag :unit
    @tag :integration
    test "extracts from multiple text files" do
      # Create temporary test files
      {:ok, dir} = Briefly.create(directory: true)

      file1 = Path.join(dir, "test1.txt")
      file2 = Path.join(dir, "test2.txt")
      file3 = Path.join(dir, "test3.txt")

      File.write!(file1, "Content 1")
      File.write!(file2, "Content 2")
      File.write!(file3, "Content 3")

      paths = [file1, file2, file3]
      {:ok, results} = BatchAPI.batch_extract_files(paths, "text/plain")

      assert is_list(results)
      assert length(results) == 3

      [result1, result2, result3] = results

      assert result1.content == "Content 1"
      assert result2.content == "Content 2"
      assert result3.content == "Content 3"
    end

    @tag :unit
    @tag :integration
    test "returns error if any file fails" do
      # Mix valid and invalid files
      {:ok, dir} = Briefly.create(directory: true)
      valid_file = Path.join(dir, "valid.txt")
      File.write!(valid_file, "Valid content")

      paths = [valid_file, "/nonexistent/file.txt"]
      {:error, reason} = BatchAPI.batch_extract_files(paths, "text/plain")

      assert is_binary(reason)
    end
  end

  describe "batch_extract_files/3" do
    @tag :unit
    @tag :integration
    test "accepts ExtractionConfig struct" do
      {:ok, dir} = Briefly.create(directory: true)
      file = Path.join(dir, "test.txt")
      File.write!(file, "Test content")

      config = %ExtractionConfig{use_cache: false}
      {:ok, results} = BatchAPI.batch_extract_files([file], "text/plain", config)

      assert length(results) == 1
      assert hd(results).content == "Test content"
    end

    @tag :unit
    @tag :integration
    test "accepts map config" do
      {:ok, dir} = Briefly.create(directory: true)
      file = Path.join(dir, "test.txt")
      File.write!(file, "Test content")

      {:ok, results} =
        BatchAPI.batch_extract_files([file], "text/plain", %{
          "use_cache" => false
        })

      assert length(results) == 1
      assert hd(results).content == "Test content"
    end

    @tag :unit
    @tag :integration
    test "works with nil mime_type for auto-detection" do
      {:ok, dir} = Briefly.create(directory: true)
      file = Path.join(dir, "test.txt")
      File.write!(file, "Test content")

      {:ok, results} = BatchAPI.batch_extract_files([file], nil)

      assert length(results) == 1
      assert hd(results).content == "Test content"
    end
  end

  describe "batch_extract_files!/2" do
    @tag :unit
    test "raises on empty paths list" do
      assert_raise Kreuzberg.Error, fn ->
        BatchAPI.batch_extract_files!([])
      end
    end

    @tag :unit
    @tag :integration
    test "returns results directly on success" do
      {:ok, dir} = Briefly.create(directory: true)
      file = Path.join(dir, "test.txt")
      File.write!(file, "Test content")

      results = BatchAPI.batch_extract_files!([file], "text/plain")

      assert is_list(results)
      assert length(results) == 1
      assert hd(results).content == "Test content"
    end

    @tag :unit
    @tag :integration
    test "raises on file not found" do
      assert_raise Kreuzberg.Error, fn ->
        BatchAPI.batch_extract_files!(["/nonexistent/file.txt"], "text/plain")
      end
    end
  end

  describe "batch_extract_bytes/2" do
    @tag :unit
    test "returns error for empty data list" do
      {:error, reason} = BatchAPI.batch_extract_bytes([], [])
      assert is_binary(reason)
      assert String.contains?(reason, "empty")
    end

    @tag :unit
    test "returns error for mismatched lengths" do
      data_list = ["data1", "data2", "data3"]
      mime_types = ["text/plain", "text/plain"]

      {:error, reason} = BatchAPI.batch_extract_bytes(data_list, mime_types)
      assert is_binary(reason)
      assert String.contains?(reason, "Mismatch")
    end

    @tag :unit
    test "accepts single mime type for all inputs" do
      data_list = ["Content 1", "Content 2", "Content 3"]

      {:ok, results} = BatchAPI.batch_extract_bytes(data_list, "text/plain")

      assert is_list(results)
      assert length(results) == 3

      [result1, result2, result3] = results

      assert result1.content == "Content 1"
      assert result2.content == "Content 2"
      assert result3.content == "Content 3"
    end

    @tag :unit
    test "accepts list of mime types" do
      data_list = ["Content 1", "Content 2"]
      mime_types = ["text/plain", "text/plain"]

      {:ok, results} = BatchAPI.batch_extract_bytes(data_list, mime_types)

      assert length(results) == 2
      assert hd(results).content == "Content 1"
    end

    @tag :unit
    test "returns error if any extraction fails" do
      data_list = ["Valid content", "data"]
      mime_types = ["text/plain", "invalid/type"]

      {:error, reason} = BatchAPI.batch_extract_bytes(data_list, mime_types)
      assert is_binary(reason)
    end
  end

  describe "batch_extract_bytes/3" do
    @tag :unit
    test "accepts ExtractionConfig struct" do
      data_list = ["Content"]
      config = %ExtractionConfig{use_cache: false}

      {:ok, results} = BatchAPI.batch_extract_bytes(data_list, "text/plain", config)

      assert length(results) == 1
      assert hd(results).content == "Content"
    end

    @tag :unit
    test "accepts map config" do
      data_list = ["Content"]

      {:ok, results} =
        BatchAPI.batch_extract_bytes(data_list, "text/plain", %{
          "use_cache" => false
        })

      assert length(results) == 1
      assert hd(results).content == "Content"
    end
  end

  describe "batch_extract_bytes!/2" do
    @tag :unit
    test "raises on empty data list" do
      assert_raise Kreuzberg.Error, fn ->
        BatchAPI.batch_extract_bytes!([], [])
      end
    end

    @tag :unit
    test "returns results directly on success" do
      data_list = ["Content"]
      results = BatchAPI.batch_extract_bytes!(data_list, "text/plain")

      assert is_list(results)
      assert length(results) == 1
      assert hd(results).content == "Content"
    end

    @tag :unit
    test "raises on extraction failure" do
      data_list = ["data"]
      mime_types = ["invalid/type"]

      assert_raise Kreuzberg.Error, fn ->
        BatchAPI.batch_extract_bytes!(data_list, mime_types)
      end
    end
  end

  describe "result structure validation" do
    @tag :unit
    test "batch results contain expected fields" do
      data_list = ["Content"]
      {:ok, results} = BatchAPI.batch_extract_bytes(data_list, "text/plain")

      result = hd(results)

      assert %Kreuzberg.ExtractionResult{
               content: _,
               mime_type: _,
               metadata: _,
               tables: _,
               detected_languages: _,
               chunks: _,
               images: _,
               pages: _
             } = result
    end

    @tag :unit
    test "all batch results are ExtractionResult structs" do
      data_list = ["Content 1", "Content 2"]
      {:ok, results} = BatchAPI.batch_extract_bytes(data_list, "text/plain")

      Enum.each(results, fn result ->
        assert %Kreuzberg.ExtractionResult{} = result
      end)
    end
  end
end
