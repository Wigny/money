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

    start_supervised!({Money.ExchangeRates.Retriever, [config: config]})
    :ok
  end

  describe "latest_rates/0" do
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

    test "invokes latest_rates_retrieved callback after retrieval" do
      pid = Process.whereis(Money.ExchangeRates.Retriever)
      trace_module(pid, Money.ExchangeRatesCallbackMock)

      Retriever.latest_rates()

      assert_received {:trace, ^pid, :call,
                       {Money.ExchangeRatesCallbackMock, :latest_rates_retrieved,
                        [_rates, _retrieved_at]}}
    end
  end

  describe "historic_rates/1" do
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

    test "invokes historic_rates_retrieved callback after retrieval" do
      pid = Process.whereis(Money.ExchangeRates.Retriever)
      trace_module(pid, Money.ExchangeRatesCallbackMock)

      Retriever.historic_rates(~D[2017-01-01])

      assert_received {:trace, ^pid, :call,
                       {Money.ExchangeRatesCallbackMock, :historic_rates_retrieved, [_rates, _date]}}
    end

    test "returns a list of results for each date in a range" do
      range = Date.range(~D[2017-01-01], ~D[2017-01-02])

      assert Retriever.historic_rates(range) ==
               [
                 {:ok,
                  %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}},
                 {:ok, %{AUD: Decimal.new("0.4"), EUR: Decimal.new("0.9"), USD: Decimal.new("0.6")}}
               ]
    end

    test "returns an error when the service is not running for a range" do
      stop_supervised!(Money.ExchangeRates.Retriever)

      range = Date.range(~D[2017-01-01], ~D[2017-01-02])

      assert Retriever.historic_rates(range) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns mixed results for a range that includes a date with no available rates" do
      range = Date.range(~D[2017-01-02], ~D[2017-01-03])

      assert Retriever.historic_rates(range) == [
               {:ok, %{AUD: Decimal.new("0.4"), EUR: Decimal.new("0.9"), USD: Decimal.new("0.6")}},
               {:error, {Money.ExchangeRateError, "No exchange rates for 2017-01-03 were found"}}
             ]
    end

    test "accepts any date-compatible struct for a single date" do
      assert Retriever.historic_rates(~N[2017-01-01 00:00:00]) ==
               {:ok, %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}}
    end

    test "returns an error for an invalid date-compatible struct" do
      assert Retriever.historic_rates(%{year: 2017, month: 13, day: 1}) == {:error, :invalid_date}
    end
  end

  describe "historic_rates/2" do
    test "returns a list of results for each date in the range" do
      assert Retriever.historic_rates(~D[2017-01-01], ~D[2017-01-02]) ==
               [
                 {:ok,
                  %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}},
                 {:ok, %{AUD: Decimal.new("0.4"), EUR: Decimal.new("0.9"), USD: Decimal.new("0.6")}}
               ]
    end

    test "a range of one date returns a single-element list" do
      assert Retriever.historic_rates(~D[2017-01-01], ~D[2017-01-01]) ==
               [{:ok, %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}}]
    end

    test "accepts any date-compatible struct" do
      from = ~N[2017-01-01 00:00:00]
      to = ~N[2017-01-02 00:00:00]

      assert [{:ok, _rates1}, {:ok, _rates2}] = Retriever.historic_rates(from, to)
    end

    test "includes error tuples for dates with no available rates" do
      assert [
               {:ok, _rates},
               {:error, {Money.ExchangeRateError, "No exchange rates for 2017-01-03 were found"}}
             ] = Retriever.historic_rates(~D[2017-01-02], ~D[2017-01-03])
    end

    test "returns an error when the service is not running" do
      stop_supervised!(Money.ExchangeRates.Retriever)

      assert Retriever.historic_rates(~D[2017-01-01], ~D[2017-01-02]) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns an error for an invalid from date" do
      assert Retriever.historic_rates(%{year: 2017, month: 13, day: 1}, ~N[2017-01-02 00:00:00]) ==
               {:error, :invalid_date}
    end

    test "returns an error for an invalid to date" do
      assert Retriever.historic_rates(~N[2017-01-01 00:00:00], %{year: 2017, month: 13, day: 1}) ==
               {:error, :invalid_date}
    end
  end

  describe "latest_rates_available?/0" do
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

  describe "last_updated/0" do
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
