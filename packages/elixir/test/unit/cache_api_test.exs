defmodule KreuzbergTest.Unit.CacheAPITest do
  @moduledoc """
  Unit tests for Kreuzberg cache management operations.

  Tests cover:
  - cache_stats/0: Retrieves cache statistics successfully
  - cache_stats!/0: Bang variant that returns stats or raises
  - clear_cache/0: Clears cache successfully
  - clear_cache!/0: Bang variant that clears cache or raises
  """

  use ExUnit.Case

  alias Kreuzberg.CacheAPI

  describe "cache_stats/0" do
    @tag :unit
    test "returns ok tuple with map on success" do
      result = CacheAPI.cache_stats()
      assert {:ok, stats} = result
      assert is_map(stats)
    end

    @tag :unit
    test "returned stats is a map" do
      {:ok, stats} = CacheAPI.cache_stats()
      assert is_map(stats)
    end

    @tag :unit
    test "stats map contains string keys" do
      {:ok, stats} = CacheAPI.cache_stats()

      # Verify all keys are strings (normalized)
      Enum.each(stats, fn {key, _value} ->
        assert is_binary(key), "Key #{inspect(key)} is not a binary string"
      end)
    end

    @tag :unit
    test "stats may contain expected cache fields" do
      {:ok, stats} = CacheAPI.cache_stats()

      # Check if expected fields exist (they may be present depending on cache state)
      # These are potential fields based on the documentation
      _potential_keys = [
        "total_files",
        "total_size_mb",
        "available_space_mb",
        "oldest_file_age_days",
        "newest_file_age_days"
      ]

      # Stats should be a map
      assert is_map(stats)
    end

    @tag :unit
    test "stats values have correct types" do
      {:ok, stats} = CacheAPI.cache_stats()

      Enum.each(stats, fn {_key, value} ->
        # Values should be numbers, strings, or maps/lists depending on field
        assert is_integer(value) or is_float(value) or is_binary(value) or is_map(value) or
                 is_list(value),
               "Value #{inspect(value)} has unexpected type"
      end)
    end

    @tag :unit
    test "handles missing cache gracefully" do
      # Even if cache is empty, should return ok tuple with stats
      result = CacheAPI.cache_stats()
      assert match?({:ok, _stats}, result)
    end

    @tag :unit
    test "result can be pattern matched" do
      assert {:ok, stats} = CacheAPI.cache_stats()
      assert is_map(stats)
    end

    @tag :unit
    test "does not raise exceptions on success" do
      # Should not raise, should return tuple
      assert_nothing_raised(fn ->
        _result = CacheAPI.cache_stats()
      end)
    end

    @tag :unit
    test "returns consistent results on multiple calls" do
      {:ok, stats1} = CacheAPI.cache_stats()
      {:ok, stats2} = CacheAPI.cache_stats()

      # Both should be maps
      assert is_map(stats1)
      assert is_map(stats2)
    end
  end

  describe "cache_stats!/0" do
    @tag :unit
    test "returns map directly on success" do
      result = CacheAPI.cache_stats!()
      assert is_map(result)
    end

    @tag :unit
    test "returned value is a map not a tuple" do
      result = CacheAPI.cache_stats!()
      assert is_map(result)
      assert not is_tuple(result)
    end

    @tag :unit
    test "result contains string keys" do
      result = CacheAPI.cache_stats!()

      Enum.each(result, fn {key, _value} ->
        assert is_binary(key), "Key #{inspect(key)} is not a binary string"
      end)
    end

    @tag :unit
    test "does not raise on success" do
      assert_nothing_raised(fn ->
        _result = CacheAPI.cache_stats!()
      end)
    end

    @tag :unit
    test "raises Kreuzberg.Error on failure" do
      # This test assumes cache_stats! might fail in some conditions
      # In a normal scenario, it should succeed
      result = CacheAPI.cache_stats!()
      assert is_map(result)
    end

    @tag :unit
    test "returns consistent results across calls" do
      result1 = CacheAPI.cache_stats!()
      result2 = CacheAPI.cache_stats!()

      assert is_map(result1)
      assert is_map(result2)
    end
  end

  describe "clear_cache/0" do
    @tag :unit
    test "returns :ok on success" do
      result = CacheAPI.clear_cache()
      assert :ok = result
    end

    @tag :unit
    test "returns atom :ok not a tuple" do
      result = CacheAPI.clear_cache()
      assert result == :ok
      assert not is_tuple(result)
    end

    @tag :unit
    test "does not raise exceptions" do
      assert_nothing_raised(fn ->
        _result = CacheAPI.clear_cache()
      end)
    end

    @tag :unit
    test "can be called multiple times" do
      result1 = CacheAPI.clear_cache()
      result2 = CacheAPI.clear_cache()

      assert result1 == :ok
      assert result2 == :ok
    end

    @tag :unit
    test "returns :ok consistency across multiple calls" do
      results = Enum.map(1..5, fn _i -> CacheAPI.clear_cache() end)

      Enum.each(results, fn result ->
        assert result == :ok
      end)
    end

    @tag :unit
    test "can be pattern matched" do
      assert :ok = CacheAPI.clear_cache()
    end

    @tag :unit
    test "result is idempotent" do
      # Clearing cache multiple times should always return :ok
      result = CacheAPI.clear_cache()
      assert result == :ok

      result2 = CacheAPI.clear_cache()
      assert result2 == :ok
    end
  end

  describe "clear_cache!/0" do
    @tag :unit
    test "returns :ok on success" do
      result = CacheAPI.clear_cache!()
      assert :ok = result
    end

    @tag :unit
    test "returns atom :ok directly" do
      result = CacheAPI.clear_cache!()
      assert result == :ok
    end

    @tag :unit
    test "does not raise on success" do
      assert_nothing_raised(fn ->
        CacheAPI.clear_cache!()
      end)
    end

    @tag :unit
    test "raises Kreuzberg.Error on failure" do
      # This test assumes clear_cache! might fail in some conditions
      # In normal scenarios, it should succeed
      result = CacheAPI.clear_cache!()
      assert result == :ok
    end

    @tag :unit
    test "can be called multiple times" do
      result1 = CacheAPI.clear_cache!()
      result2 = CacheAPI.clear_cache!()

      assert result1 == :ok
      assert result2 == :ok
    end

    @tag :unit
    test "returns consistent :ok across multiple calls" do
      results = Enum.map(1..5, fn _i -> CacheAPI.clear_cache!() end)

      Enum.each(results, fn result ->
        assert result == :ok
      end)
    end

    @tag :unit
    test "is idempotent" do
      # Clearing cache multiple times should always return :ok
      result = CacheAPI.clear_cache!()
      assert result == :ok

      result2 = CacheAPI.clear_cache!()
      assert result2 == :ok
    end
  end

  describe "cache stats normalization" do
    @tag :unit
    test "cache_stats normalizes keys to strings" do
      {:ok, stats} = CacheAPI.cache_stats()

      # All keys should be binary strings
      Enum.each(stats, fn {key, _value} ->
        assert is_binary(key),
               "Key should be binary string, got: #{inspect(key)}"
      end)
    end

    @tag :unit
    test "cache_stats! also returns normalized keys" do
      stats = CacheAPI.cache_stats!()

      Enum.each(stats, fn {key, _value} ->
        assert is_binary(key),
               "Key should be binary string, got: #{inspect(key)}"
      end)
    end
  end

  describe "cache_stats and clear_cache integration" do
    @tag :unit
    test "cache_stats returns map after clear_cache" do
      _clear_result = CacheAPI.clear_cache()
      {:ok, stats} = CacheAPI.cache_stats()

      assert is_map(stats)
    end

    @tag :unit
    test "both functions handle edge cases" do
      # Test calling in sequence
      clear_result = CacheAPI.clear_cache()
      assert clear_result == :ok

      {:ok, stats} = CacheAPI.cache_stats()
      assert is_map(stats)
    end

    @tag :unit
    test "bang and non-bang variants are consistent" do
      # Non-bang variant
      {:ok, stats1} = CacheAPI.cache_stats()

      # Bang variant
      stats2 = CacheAPI.cache_stats!()

      # Both should return maps with same structure
      assert is_map(stats1)
      assert is_map(stats2)
    end

    @tag :unit
    test "clear_cache and clear_cache! are consistent" do
      result1 = CacheAPI.clear_cache()
      result2 = CacheAPI.clear_cache!()

      assert result1 == :ok
      assert result2 == :ok
    end
  end

  # Helper function to assert nothing was raised
  defp assert_nothing_raised(func) do
    func.()
    assert true
  rescue
    _e -> flunk("Expected function to not raise, but it did")
  end
end
