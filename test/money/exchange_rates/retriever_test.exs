defmodule Money.ExchangeRates.RetrieverTest do
  use ExUnit.Case, async: false

  alias Money.ExchangeRates.Retriever

  doctest Retriever

  @rates %{
    AUD: Decimal.new("0.5"),
    EUR: Decimal.new("1.1"),
    USD: Decimal.new("0.7")
  }

  setup do
    Code.ensure_loaded!(Money.ExchangeRatesCallbackMock)

    config = %{
      Money.ExchangeRates.default_config()
      | callback_module: Money.ExchangeRatesCallbackMock
    }

    %{retriever: start_supervised!({Money.ExchangeRates.Retriever, [config: config]})}
  end

  describe "latest_rates/1" do
    test "returns rates from the cache when available" do
      Money.ExchangeRates.Cache.Ets.store_latest_rates(@rates, DateTime.utc_now())

      assert Retriever.latest_rates() == {:ok, @rates}
    end

    test "fetches from the api when the cache is empty" do
      assert Retriever.latest_rates() ==
               {:ok, %{AUD: Decimal.new("0.7"), EUR: Decimal.new("1.2"), USD: Decimal.new(1)}}
    end

    test "returns an error when the retriever is not running" do
      stop_supervised!(Money.ExchangeRates.Retriever)

      assert Retriever.latest_rates() ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns an error when api reports not_modified and cache is empty" do
      stop_supervised!(Money.ExchangeRates.Retriever)

      config = %{
        Money.ExchangeRates.default_config()
        | retriever_options: %{skip_fetch: true}
      }

      start_supervised!({Money.ExchangeRates.Retriever, [config: config]})

      assert Retriever.latest_rates() ==
               {:error, {Money.ExchangeRateError, "No exchange rates were found"}}
    end

    test "routes to the correct process when called with a custom name" do
      config = %{
        Money.ExchangeRates.default_config()
        | callback_module: Money.ExchangeRatesCallbackMock
      }

      start_supervised!({Retriever, [name: :custom_retriever, config: config]},
        id: :custom_retriever
      )

      assert {:ok, _rates} = Retriever.latest_rates(:custom_retriever)
    end

    test "invokes latest_rates_retrieved callback after retrieval", %{retriever: retriever} do
      trace_module(retriever, Money.ExchangeRatesCallbackMock)

      Retriever.latest_rates()

      assert_received {:trace, ^retriever, :call,
                       {Money.ExchangeRatesCallbackMock, :latest_rates_retrieved,
                        [_rates, _retrieved_at]}}
    end
  end

  describe "historic_rates/2" do
    test "returns rates from the cache when available" do
      Money.ExchangeRates.Cache.Ets.store_historic_rates(@rates, ~D[2017-01-01])

      assert Retriever.historic_rates(~D[2017-01-01]) == {:ok, @rates}
    end

    test "fetches from the api when the cache is empty" do
      assert Retriever.historic_rates(~D[2017-01-01]) == {:ok, @rates}
    end

    test "returns an error when the retriever is not running" do
      stop_supervised!(Money.ExchangeRates.Retriever)

      assert Retriever.historic_rates(~D[2017-01-01]) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns an error when api reports not_modified and cache is empty" do
      stop_supervised!(Money.ExchangeRates.Retriever)

      config = %{
        Money.ExchangeRates.default_config()
        | retriever_options: %{skip_fetch: true}
      }

      start_supervised!({Money.ExchangeRates.Retriever, [config: config]})

      assert Retriever.historic_rates(~D[2017-01-01]) ==
               {:error, {Money.ExchangeRateError, "No exchange rates for 2017-01-01 were found"}}
    end

    test "routes to the correct process when called with a custom name" do
      config = %{
        Money.ExchangeRates.default_config()
        | callback_module: Money.ExchangeRatesCallbackMock
      }

      start_supervised!({Retriever, [name: :custom_retriever, config: config]},
        id: :custom_retriever
      )

      assert {:ok, _rates} = Retriever.historic_rates(:custom_retriever, ~D[2017-01-01])
    end

    test "invokes historic_rates_retrieved callback after retrieval", %{retriever: retriever} do
      trace_module(retriever, Money.ExchangeRatesCallbackMock)

      Retriever.historic_rates(~D[2017-01-01])

      assert_received {:trace, ^retriever, :call,
                       {Money.ExchangeRatesCallbackMock, :historic_rates_retrieved, [_rates, _date]}}
    end
  end

  describe "latest_rates_available?/1" do
    test "routes to the correct process when called with a custom name" do
      config = %{
        Money.ExchangeRates.default_config()
        | callback_module: Money.ExchangeRatesCallbackMock
      }

      start_supervised!({Retriever, [name: :custom_retriever, config: config]},
        id: :custom_retriever
      )

      Retriever.latest_rates(:custom_retriever)

      assert Retriever.latest_rates_available?(:custom_retriever)
    end

    test "returns true when rates are in the cache" do
      Money.ExchangeRates.Cache.Ets.store_latest_rates(@rates, DateTime.utc_now())

      assert Retriever.latest_rates_available?()
    end

    test "returns false when no rates are cached" do
      :ets.delete(:exchange_rates, :latest_rates)

      refute Retriever.latest_rates_available?()
    end

    test "returns false when the retriever is not running" do
      stop_supervised!(Money.ExchangeRates.Retriever)

      refute Retriever.latest_rates_available?()
    end

    test "returns false when retriever stops even if cache had rates" do
      Money.ExchangeRates.Cache.Ets.store_latest_rates(@rates, DateTime.utc_now())
      stop_supervised!(Money.ExchangeRates.Retriever)

      refute Retriever.latest_rates_available?()
    end
  end

  describe "last_updated/1" do
    test "routes to the correct process when called with a custom name" do
      config = %{
        Money.ExchangeRates.default_config()
        | callback_module: Money.ExchangeRatesCallbackMock
      }

      start_supervised!({Retriever, [name: :custom_retriever, config: config]},
        id: :custom_retriever
      )

      Retriever.latest_rates(:custom_retriever)

      assert {:ok, _datetime} = Retriever.last_updated(:custom_retriever)
    end

    test "returns the time when rates have been stored" do
      retrieved_at = DateTime.utc_now(:second)
      Money.ExchangeRates.Cache.Ets.store_latest_rates(@rates, retrieved_at)

      assert Retriever.last_updated() == {:ok, retrieved_at}
    end

    test "returns an error when the retriever is not running" do
      stop_supervised!(Money.ExchangeRates.Retriever)

      assert Retriever.last_updated() ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end
  end

  defp trace_module(pid, module) do
    session = :trace.session_create(:exchange_rates_test, self(), [])
    :trace.function(session, {module, :_, :_}, true, [:local])
    :trace.process(session, pid, true, [:call])
    on_exit(fn -> :trace.session_destroy(session) end)
  end
end
