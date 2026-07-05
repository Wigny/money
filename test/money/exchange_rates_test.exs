defmodule Money.ExchangeRatesTest do
  use ExUnit.Case, async: false

  alias Money.ExchangeRates
  alias Money.ExchangeRates.Cache.Ets

  doctest ExchangeRates

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

    start_supervised!({Money.ExchangeRates.Retriever, [config: config]})
    :ok
  end

  describe "latest_rates/0" do
    test "fetches from the cache when rates are cached" do
      Ets.store_latest_rates(@rates, DateTime.utc_now())

      assert ExchangeRates.latest_rates() == {:ok, @rates}
    end

    test "fetches from the retriever when the cache is empty" do
      assert ExchangeRates.latest_rates() ==
               {:ok, %{AUD: Decimal.new("0.7"), EUR: Decimal.new("1.2"), USD: Decimal.new(1)}}
    end

    test "returns an error if the retriever is not running" do
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.latest_rates() ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns error when retriever stops even if cache has rates" do
      Ets.store_latest_rates(@rates, DateTime.utc_now())
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.latest_rates() ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "invokes latest_rates_retrieved callback after retrieval" do
      pid = Process.whereis(Money.ExchangeRates.Retriever)
      trace_module(pid, Money.ExchangeRatesCallbackMock)

      ExchangeRates.latest_rates()

      assert_received {:trace, ^pid, :call,
                       {Money.ExchangeRatesCallbackMock, :latest_rates_retrieved,
                        [_rates, _retrieved_at]}}
    end
  end

  describe "latest_rates/1" do
    test "queries the given retriever process" do
      name = start_named_retriever()

      assert ExchangeRates.latest_rates(name) ==
               {:ok, %{AUD: Decimal.new("0.7"), EUR: Decimal.new("1.2"), USD: Decimal.new(1)}}

      stop_supervised(name)

      assert ExchangeRates.latest_rates(name) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end
  end

  describe "historic_rates/1" do
    test "fetches from the cache when rates are cached" do
      Ets.store_historic_rates(@rates, ~D[2017-01-01])

      assert ExchangeRates.historic_rates(~D[2017-01-01]) == {:ok, @rates}
    end

    test "fetches from the retriever when the cache is empty" do
      assert ExchangeRates.historic_rates(~D[2017-01-01]) == {:ok, @rates}
    end

    test "returns an error when the retriever is not running" do
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.historic_rates(~D[2017-01-01]) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns error when retriever stops even if cache has rates" do
      Ets.store_historic_rates(@rates, ~D[2017-01-01])
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.historic_rates(~D[2017-01-01]) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "invokes historic_rates_retrieved callback after retrieval" do
      pid = Process.whereis(Money.ExchangeRates.Retriever)
      trace_module(pid, Money.ExchangeRatesCallbackMock)

      ExchangeRates.historic_rates(~D[2017-01-01])

      assert_received {:trace, ^pid, :call,
                       {Money.ExchangeRatesCallbackMock, :historic_rates_retrieved, [_rates, _date]}}
    end
  end

  describe "historic_rates/2 with a retriever" do
    test "queries the given retriever process" do
      name = start_named_retriever()

      assert ExchangeRates.historic_rates(name, ~D[2017-01-01]) == {:ok, @rates}

      stop_supervised(name)

      assert ExchangeRates.historic_rates(name, ~D[2017-01-01]) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end
  end

  describe "historic_rates/3 with a retriever" do
    test "queries the given retriever process" do
      name = start_named_retriever()

      assert ExchangeRates.historic_rates(name, ~D[2017-01-01], ~D[2017-01-02]) == [
               {:ok, @rates},
               {:ok, %{AUD: Decimal.new("0.4"), EUR: Decimal.new("0.9"), USD: Decimal.new("0.6")}}
             ]

      stop_supervised(name)

      assert ExchangeRates.historic_rates(name, ~D[2017-01-01], ~D[2017-01-02]) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end
  end

  describe "latest_rates_available?/0" do
    test "returns true when rates are in the cache" do
      Ets.store_latest_rates(@rates, DateTime.utc_now())

      assert ExchangeRates.latest_rates_available?()
    end

    test "returns false when no rates are cached" do
      refute ExchangeRates.latest_rates_available?()
    end

    test "returns false when the retriever is not running" do
      stop_supervised(Money.ExchangeRates.Retriever)

      refute ExchangeRates.latest_rates_available?()
    end

    test "returns false when retriever stops even if cache has rates" do
      Ets.store_latest_rates(@rates, DateTime.utc_now())
      stop_supervised(Money.ExchangeRates.Retriever)

      refute ExchangeRates.latest_rates_available?()
    end
  end

  describe "latest_rates_available?/1" do
    test "queries the given retriever process" do
      name = start_named_retriever()

      refute ExchangeRates.latest_rates_available?(name)

      {:ok, _rates} = ExchangeRates.latest_rates(name)
      assert ExchangeRates.latest_rates_available?(name)

      stop_supervised(name)
      refute ExchangeRates.latest_rates_available?(name)
    end
  end

  describe "last_updated/0" do
    test "returns the time when rates have been stored" do
      retrieved_at = DateTime.utc_now(:second)
      Ets.store_latest_rates(@rates, retrieved_at)

      assert ExchangeRates.last_updated() == {:ok, retrieved_at}
    end

    test "returns an error when the retriever is not running" do
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.last_updated() ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns error when retriever stops even if timestamp is cached" do
      retrieved_at = DateTime.utc_now(:second)
      Ets.store_latest_rates(@rates, retrieved_at)
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.last_updated() ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end
  end

  describe "last_updated/1" do
    test "queries the given retriever process" do
      name = start_named_retriever()

      assert ExchangeRates.last_updated(name) ==
               {:error, {Money.ExchangeRateError, "Last updated date is not known"}}

      {:ok, _rates} = ExchangeRates.latest_rates(name)
      assert {:ok, %DateTime{}} = ExchangeRates.last_updated(name)

      stop_supervised(name)

      assert ExchangeRates.last_updated(name) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end
  end

  describe "config/0" do
    test "runs the api module's init/1 to populate retriever_options even when the module is not loaded (issue #202)" do
      # Reproduces https://github.com/ex-money/money/issues/202: during
      # application startup the API module is referenced only as a config atom
      # and may not be loaded, so `function_exported?/3` returns false and the
      # `init/1` callback (which sets `:retriever_options`) is skipped, leaving
      # it `nil` and crashing the first rate fetch with `{:badmap, nil}`.
      previous = Application.get_env(:ex_money, :api_module)
      Application.put_env(:ex_money, :api_module, Money.ExchangeRates.OpenExchangeRates)

      try do
        # Force the "not loaded yet" condition. Safe here: the retriever started
        # in setup uses the mock API module, so no process is running this code.
        :code.purge(Money.ExchangeRates.OpenExchangeRates)
        :code.delete(Money.ExchangeRates.OpenExchangeRates)

        refute :erlang.function_exported(Money.ExchangeRates.OpenExchangeRates, :init, 1),
               "precondition: the api module must be unloaded for this regression"

        config = Money.ExchangeRates.config()

        assert is_map(config.retriever_options),
               "retriever_options must be populated, got: #{inspect(config.retriever_options)}"

        assert Map.has_key?(config.retriever_options, :url)
        assert Map.has_key?(config.retriever_options, :app_id)
      after
        if previous do
          Application.put_env(:ex_money, :api_module, previous)
        else
          Application.delete_env(:ex_money, :api_module)
        end
      end
    end
  end

  defp start_named_retriever do
    name = :"exchange_rates_test_#{System.unique_integer([:positive])}"
    start_supervised!({Money.ExchangeRates.Retriever, [name: name]}, id: name)
    name
  end

  defp trace_module(pid, module) do
    :erlang.trace_pattern({module, :_, :_}, true, [:local])
    :erlang.trace(pid, true, [:call])

    on_exit(fn ->
      :erlang.trace_pattern({module, :_, :_}, false, [:local])
    end)
  end
end
