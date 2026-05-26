defmodule Money.ExchangeRates.RetrieverTest do
  use ExUnit.Case, async: false

  alias Money.ExchangeRates.Retriever

  doctest Retriever

  describe "historic_rates/1" do
    test "returns rates for a single date" do
      assert Retriever.historic_rates(~D[2017-01-01]) ==
               {:ok, %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}}
    end

    test "returns an error for a date with no available rates" do
      assert Retriever.historic_rates(~D[2017-01-03]) ==
               {:error, {Money.ExchangeRateError, "No exchange rates for 2017-01-03 were found"}}
    end

    test "returns an error when the service is not running" do
      on_exit(fn -> Money.ExchangeRates.Supervisor.restart_retriever() end)
      Money.ExchangeRates.Supervisor.stop_retriever()

      assert Retriever.historic_rates(~D[2017-01-01]) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns a list of results for each date in the range" do
      range = Date.range(~D[2017-01-01], ~D[2017-01-02])

      assert Retriever.historic_rates(range) ==
               [
                 {:ok,
                  %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}},
                 {:ok, %{AUD: Decimal.new("0.4"), EUR: Decimal.new("0.9"), USD: Decimal.new("0.6")}}
               ]
    end

    test "returns an error when the service is not running for a range" do
      on_exit(fn -> Money.ExchangeRates.Supervisor.restart_retriever() end)
      Money.ExchangeRates.Supervisor.stop_retriever()

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
      on_exit(fn -> Money.ExchangeRates.Supervisor.restart_retriever() end)
      Money.ExchangeRates.Supervisor.stop_retriever()

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
end
