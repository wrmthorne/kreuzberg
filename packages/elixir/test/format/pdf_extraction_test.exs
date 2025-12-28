defmodule Kreuzberg.Format.PdfExtractionTest do
  use ExUnit.Case

  @moduletag :integration

  describe "PDF extraction" do
    @describetag :format
    test "extracts content and metadata from PDF" do
      pdf_path = Path.expand("../../../test_documents/pdfs/multi_page.pdf", __DIR__)

      if File.exists?(pdf_path) do
        {:ok, pdf_binary} = File.read(pdf_path)

        # Extract from the PDF
        result = Kreuzberg.extract!(pdf_binary, "application/pdf")

        # Assert that the result has the expected structure
        assert result.content != nil, "content should not be nil"
        assert is_binary(result.content), "content should be a binary"
        assert byte_size(result.content) > 0, "content should not be empty"

        # Assert mime_type is correct
        assert result.mime_type == "application/pdf", "mime_type should be application/pdf"

        # Assert metadata is present
        assert is_map(result.metadata), "metadata should be a map"
      end
    end

    test "handles PDF with various content types" do
      pdf_path = Path.expand("../../../test_documents/pdfs/embedded_images_tables.pdf", __DIR__)

      if File.exists?(pdf_path) do
        {:ok, pdf_binary} = File.read(pdf_path)
        result = Kreuzberg.extract!(pdf_binary, "application/pdf")

        # Verify basic extraction succeeded
        assert result.content != nil
        assert result.mime_type == "application/pdf"

        # Tables might be present
        assert is_list(result.tables)
      end
    end
  end
end
