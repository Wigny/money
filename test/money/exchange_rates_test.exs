defmodule Money.ExchangeRatesTest do
  use ExUnit.Case, async: false

  alias Money.ExchangeRates

  doctest ExchangeRates

  setup do
    start_supervised!(Money.ExchangeRates.Retriever)
    :ok
  end

  describe "historic_rates/1" do
    test "returns a list of results for each date in a range" do
      range = Date.range(~D[2017-01-01], ~D[2017-01-02])

      assert ExchangeRates.historic_rates(range) ==
               [
                 {:ok,
                  %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}},
                 {:ok, %{AUD: Decimal.new("0.4"), EUR: Decimal.new("0.9"), USD: Decimal.new("0.6")}}
               ]
    end

    test "returns error tuples for each date in a range when the service is not running" do
      stop_supervised!(Money.ExchangeRates.Retriever)

      range = Date.range(~D[2017-01-01], ~D[2017-01-02])

      error =
        {:error, {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}

      assert ExchangeRates.historic_rates(range) == [error, error]
    end

    test "returns mixed results for a range that includes a date with no available rates" do
      range = Date.range(~D[2017-01-02], ~D[2017-01-03])

      assert ExchangeRates.historic_rates(range) == [
               {:ok, %{AUD: Decimal.new("0.4"), EUR: Decimal.new("0.9"), USD: Decimal.new("0.6")}},
               {:error, {Money.ExchangeRateError, "No exchange rates for 2017-01-03 were found"}}
             ]
    end

    test "accepts any date-compatible struct for a single date" do
      assert ExchangeRates.historic_rates(~N[2017-01-01 00:00:00]) ==
               {:ok, %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}}
    end
  end

  describe "historic_rates/2" do
    test "returns a list of results for each date in the range" do
      assert ExchangeRates.historic_rates(~D[2017-01-01], ~D[2017-01-02]) ==
               [
                 {:ok,
                  %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}},
                 {:ok, %{AUD: Decimal.new("0.4"), EUR: Decimal.new("0.9"), USD: Decimal.new("0.6")}}
               ]
    end

    test "a range of one date returns a single-element list" do
      assert ExchangeRates.historic_rates(~D[2017-01-01], ~D[2017-01-01]) ==
               [{:ok, %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}}]
    end

    test "accepts any date-compatible struct" do
      from = ~N[2017-01-01 00:00:00]
      to = ~N[2017-01-02 00:00:00]

      assert [{:ok, _rates1}, {:ok, _rates2}] = ExchangeRates.historic_rates(from, to)
    end

    test "includes error tuples for dates with no available rates" do
      assert [
               {:ok, _rates},
               {:error, {Money.ExchangeRateError, "No exchange rates for 2017-01-03 were found"}}
             ] = ExchangeRates.historic_rates(~D[2017-01-02], ~D[2017-01-03])
    end

    test "returns error tuples for each date when the service is not running" do
      stop_supervised!(Money.ExchangeRates.Retriever)

      error =
        {:error, {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}

      assert ExchangeRates.historic_rates(~D[2017-01-01], ~D[2017-01-02]) == [error, error]
    end
  end
end
