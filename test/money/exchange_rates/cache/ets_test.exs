defmodule Money.ExchangeRates.Cache.EtsTest do
  use ExUnit.Case

  alias Money.ExchangeRates.Cache.Ets

  doctest Ets

  @rates %{USD: Decimal.new(1), AUD: Decimal.new("1.5")}
  @date ~D[2099-01-01]

  setup do
    name = :"ets_test_#{System.unique_integer([:positive])}"
    cache = Ets.init(name)

    {:ok, cache: cache}
  end

  describe "init/1" do
    test "returns a usable ETS table reference", %{cache: cache} do
      assert :ets.info(cache) != :undefined
    end

    test "reuses an existing table instead of raising", %{cache: cache} do
      assert Ets.init(cache) == cache
      assert :ets.info(cache) != :undefined
    end
  end

  describe "terminate/1" do
    test "is a no-op that leaves the underlying table intact", %{cache: cache} do
      assert Ets.terminate(cache) == :ok
      assert :ets.info(cache) != :undefined
    end
  end

  describe "store_latest_rates/3 and latest_rates/1" do
    test "returns stored rates", %{cache: cache} do
      retrieved_at = DateTime.utc_now()
      Ets.store_latest_rates(cache, @rates, retrieved_at)
      assert Ets.latest_rates(cache) == {:ok, @rates}
    end
  end

  describe "store_historic_rates/3 and historic_rates/2" do
    test "returns stored rates for a Date", %{cache: cache} do
      Ets.store_historic_rates(cache, @rates, @date)
      assert Ets.historic_rates(cache, @date) == {:ok, @rates}
    end

    test "returns an error for an unstored date", %{cache: cache} do
      assert Ets.historic_rates(cache, ~D[2099-12-31]) ==
               {:error, {Money.ExchangeRateError, "No exchange rates for 2099-12-31 were found"}}
    end
  end

  describe "last_updated/1" do
    test "returns the timestamp stored alongside the latest rates", %{cache: cache} do
      retrieved_at = DateTime.utc_now()
      Ets.store_latest_rates(cache, @rates, retrieved_at)
      assert Ets.last_updated(cache) == {:ok, retrieved_at}
    end
  end
end
