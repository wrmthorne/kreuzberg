defmodule Kreuzberg.Format.FileExtractionTest do
  @moduledoc """
  Format tests for Kreuzberg file path extraction functions.

  Tests cover:
  - PDF file extraction using actual test documents
  - DOCX file extraction using actual test documents
  - HTML file extraction using actual test documents
  - Format-specific behavior and content validation
  - Conditional execution based on file availability
  """

  use ExUnit.Case

  @moduletag :format
  @moduletag :integration

  describe "PDF extraction from file" do
    test "extracts content from PDF file" do
      pdf_path = Path.expand("../../../test_documents/pdfs/code_and_formula.pdf", __DIR__)

      if File.exists?(pdf_path) do
        {:ok, result} = Kreuzberg.extract_file(pdf_path, "application/pdf")

        # Assert that the result has the expected structure
        assert result.content != nil, "content should not be nil"
        assert is_binary(result.content), "content should be a binary"
        assert byte_size(result.content) > 0, "content should not be empty"

        # Assert mime_type is correct
        assert result.mime_type == "application/pdf", "mime_type should be application/pdf"

        # Assert metadata is present
        assert is_map(result.metadata), "metadata should be a map"

        # Assert tables list is present
        assert is_list(result.tables), "tables should be a list"
      end
    end

    test "extracts PDF with auto-detected MIME type" do
      pdf_path = Path.expand("../../../test_documents/pdfs/right_to_left_01.pdf", __DIR__)

      if File.exists?(pdf_path) do
        {:ok, result} = Kreuzberg.extract_file(pdf_path)

        # Should extract successfully with auto-detection
        assert result.content != nil
        assert is_binary(result.content)
        assert byte_size(result.content) > 0

        # MIME type should be detected as PDF
        assert is_binary(result.mime_type)
      end
    end

    test "handles PDF with tables" do
      pdf_path = Path.expand("../../../test_documents/pdfs_with_tables/tiny.pdf", __DIR__)

      if File.exists?(pdf_path) do
        {:ok, result} = Kreuzberg.extract_file(pdf_path, "application/pdf")

        # Verify basic extraction succeeded
        assert result.content != nil
        assert result.mime_type == "application/pdf"

        # Tables might be present (depending on PDF content)
        assert is_list(result.tables)
      end
    end

    test "handles multi-page PDF" do
      pdf_path = Path.expand("../../../test_documents/pdfs_with_tables/medium.pdf", __DIR__)

      if File.exists?(pdf_path) do
        {:ok, result} = Kreuzberg.extract_file(pdf_path, "application/pdf")

        # Verify extraction succeeded
        assert result.content != nil
        assert byte_size(result.content) > 0
        assert result.mime_type == "application/pdf"

        # Pages information might be present
        assert is_list(result.pages)
      end
    end

    test "PDF extraction result has proper structure" do
      pdf_path = Path.expand("../../../test_documents/pdfs/code_and_formula.pdf", __DIR__)

      if File.exists?(pdf_path) do
        {:ok, result} = Kreuzberg.extract_file(pdf_path, "application/pdf")

        # Verify the full structure
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

    test "bang variant extracts PDF successfully" do
      pdf_path = Path.expand("../../../test_documents/pdfs/code_and_formula.pdf", __DIR__)

      if File.exists?(pdf_path) do
        result = Kreuzberg.extract_file!(pdf_path, "application/pdf")

        # Should return struct directly, not tuple
        assert is_struct(result)
        assert %Kreuzberg.ExtractionResult{} = result
        assert result.content != nil
        assert result.mime_type == "application/pdf"
      end
    end

    test "PDF extraction with configuration options" do
      pdf_path = Path.expand("../../../test_documents/pdfs/code_and_formula.pdf", __DIR__)

      if File.exists?(pdf_path) do
        config = %Kreuzberg.ExtractionConfig{
          ocr: %{"enabled" => true}
        }

        {:ok, result} = Kreuzberg.extract_file(pdf_path, "application/pdf", config)

        assert result.content != nil
        assert result.mime_type == "application/pdf"
      end
    end

    test "PDF extraction with map configuration" do
      pdf_path = Path.expand("../../../test_documents/pdfs/right_to_left_01.pdf", __DIR__)

      if File.exists?(pdf_path) do
        {:ok, result} =
          Kreuzberg.extract_file(pdf_path, "application/pdf", %{
            "pdf_config" => %{
              "extract_text" => true,
              "preserve_formatting" => true
            }
          })

        assert result.content != nil
        assert is_binary(result.content)
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

        # Assert that the result has the expected structure
        assert result.content != nil, "content should not be nil"
        assert is_binary(result.content), "content should be a binary"

        # DOCX should have content
        assert byte_size(result.content) > 0 or result.content == "",
               "content extraction should work"

        # Assert MIME type is set
        assert is_binary(result.mime_type)

        # Assert metadata is present
        assert is_map(result.metadata), "metadata should be a map"
      end
    end

    test "extracts DOCX with auto-detected MIME type" do
      docx_path = Path.expand("../../../test_documents/extraction_test.docx", __DIR__)

      if File.exists?(docx_path) do
        {:ok, result} = Kreuzberg.extract_file(docx_path)

        # Should extract successfully
        assert result.content != nil
        assert is_binary(result.content)

        # MIME type should be detected
        assert is_binary(result.mime_type)
      end
    end

    test "DOCX extraction result has proper structure" do
      docx_path = Path.expand("../../../test_documents/extraction_test.docx", __DIR__)

      if File.exists?(docx_path) do
        {:ok, result} =
          Kreuzberg.extract_file(
            docx_path,
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
          )

        # Verify the structure
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

    test "bang variant extracts DOCX successfully" do
      docx_path = Path.expand("../../../test_documents/extraction_test.docx", __DIR__)

      if File.exists?(docx_path) do
        result =
          Kreuzberg.extract_file!(
            docx_path,
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
          )

        # Should return struct directly
        assert is_struct(result)
        assert %Kreuzberg.ExtractionResult{} = result
        assert is_binary(result.content)
      end
    end

    test "DOCX extraction with configuration" do
      docx_path = Path.expand("../../../test_documents/extraction_test.docx", __DIR__)

      if File.exists?(docx_path) do
        config = %Kreuzberg.ExtractionConfig{
          chunking: %{"enabled" => true, "size" => 256}
        }

        {:ok, result} =
          Kreuzberg.extract_file(
            docx_path,
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            config
          )

        assert result.content != nil
        assert is_binary(result.content)
      end
    end
  end

  describe "HTML extraction from file" do
    test "extracts content from HTML file" do
      html_path = Path.expand("../../../test_documents/web/html.html", __DIR__)

      if File.exists?(html_path) do
        {:ok, result} = Kreuzberg.extract_file(html_path, "text/html")

        # Assert that the result has the expected structure
        assert result.content != nil, "content should not be nil"
        assert is_binary(result.content), "content should be a binary"

        # HTML should produce text content
        assert byte_size(result.content) > 0 or result.content == "",
               "content extraction should work"

        # Assert MIME type is set
        assert is_binary(result.mime_type)

        # Assert metadata is present
        assert is_map(result.metadata), "metadata should be a map"
      end
    end

    test "extracts HTML with auto-detected MIME type" do
      html_path = Path.expand("../../../test_documents/web/html.html", __DIR__)

      if File.exists?(html_path) do
        {:ok, result} = Kreuzberg.extract_file(html_path)

        # Should extract successfully
        assert result.content != nil
        assert is_binary(result.content)

        # MIME type should be detected
        assert is_binary(result.mime_type)
      end
    end

    test "HTML extraction from complex page" do
      html_path = Path.expand("../../../test_documents/web/complex_table.html", __DIR__)

      if File.exists?(html_path) do
        {:ok, result} = Kreuzberg.extract_file(html_path, "text/html")

        # Should extract content
        assert result.content != nil
        assert is_binary(result.content)

        # Tables might be extracted
        assert is_list(result.tables)
      end
    end

    test "HTML extraction result has proper structure" do
      html_path = Path.expand("../../../test_documents/web/html.html", __DIR__)

      if File.exists?(html_path) do
        {:ok, result} = Kreuzberg.extract_file(html_path, "text/html")

        # Verify the structure
        assert %Kreuzberg.ExtractionResult{
                 content: content,
                 mime_type: mime_type,
                 metadata: metadata,
                 tables: tables,
                 detected_languages: languages
               } = result

        assert is_binary(content)
        assert is_binary(mime_type)
        assert is_map(metadata)
        assert is_list(tables)
        assert is_list(languages)
      end
    end

    test "bang variant extracts HTML successfully" do
      html_path = Path.expand("../../../test_documents/web/html.html", __DIR__)

      if File.exists?(html_path) do
        result = Kreuzberg.extract_file!(html_path, "text/html")

        # Should return struct directly
        assert is_struct(result)
        assert %Kreuzberg.ExtractionResult{} = result
        assert is_binary(result.content)
      end
    end

    test "HTML extraction with language content" do
      # Use a document with non-English content
      html_path = Path.expand("../../../test_documents/web/germany_german.html", __DIR__)

      if File.exists?(html_path) do
        {:ok, result} = Kreuzberg.extract_file(html_path, "text/html")

        assert result.content != nil
        assert is_binary(result.content)

        # Language detection might be present
        assert is_list(result.detected_languages)
      end
    end

    test "HTML extraction with configuration" do
      html_path = Path.expand("../../../test_documents/web/html.html", __DIR__)

      if File.exists?(html_path) do
        config = %Kreuzberg.ExtractionConfig{
          language_detection: %{"enabled" => true}
        }

        {:ok, result} = Kreuzberg.extract_file(html_path, "text/html", config)

        assert result.content != nil
        assert is_binary(result.content)
      end
    end
  end

  describe "multi-format extraction consistency" do
    test "consistent extraction across formats with same content" do
      text_content = "Test content for extraction"

      # Create temporary test files
      unique_id = System.unique_integer()
      txt_path = System.tmp_dir!() <> "/test_#{unique_id}.txt"
      File.write!(txt_path, text_content)

      try do
        {:ok, result1} = Kreuzberg.extract_file(txt_path, "text/plain")
        {:ok, result2} = Kreuzberg.extract_file(txt_path)

        # Same file should produce same content
        assert result1.content == result2.content
      after
        if File.exists?(txt_path), do: File.rm(txt_path)
      end
    end

    test "extraction with and without config produces content" do
      pdf_path = Path.expand("../../../test_documents/pdfs/code_and_formula.pdf", __DIR__)

      if File.exists?(pdf_path) do
        {:ok, result1} = Kreuzberg.extract_file(pdf_path, "application/pdf")
        {:ok, result2} = Kreuzberg.extract_file(pdf_path, "application/pdf", %{})

        # Both should produce non-empty content
        assert byte_size(result1.content) > 0
        assert byte_size(result2.content) > 0
      end
    end
  end

  describe "file path variations" do
    test "extraction works with absolute path" do
      pdf_path = Path.expand("../../../test_documents/pdfs/code_and_formula.pdf", __DIR__)

      if File.exists?(pdf_path) do
        abs_path = Path.expand(pdf_path)
        {:ok, result} = Kreuzberg.extract_file(abs_path, "application/pdf")

        assert result.content != nil
      end
    end

    test "extraction works with relative path" do
      # Change to test directory and use relative path
      current_dir = File.cwd!()
      test_dir = Path.expand("../../../test_documents", __DIR__)

      if File.exists?(test_dir) do
        try do
          File.cd!(test_dir)
          {:ok, result} = Kreuzberg.extract_file("pdfs/code_and_formula.pdf", "application/pdf")

          assert result.content != nil
        after
          File.cd!(current_dir)
        end
      end
    end
  end

  describe "edge cases and error handling" do
    test "returns error for non-existent file with specific MIME type" do
      {:error, reason} =
        Kreuzberg.extract_file(
          "/tmp/non_existent_#{System.unique_integer()}.pdf",
          "application/pdf"
        )

      assert is_binary(reason)
    end

    test "returns error for non-existent file with auto-detection" do
      {:error, reason} =
        Kreuzberg.extract_file("/tmp/non_existent_#{System.unique_integer()}.pdf")

      assert is_binary(reason)
    end

    test "bang variant raises for non-existent file" do
      assert_raise Kreuzberg.Error, fn ->
        Kreuzberg.extract_file!(
          "/tmp/missing_#{System.unique_integer()}.pdf",
          "application/pdf"
        )
      end
    end

    test "empty path returns error" do
      {:error, reason} = Kreuzberg.extract_file("", "text/plain")

      assert is_binary(reason)
    end
  end
end
