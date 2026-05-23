defmodule Money.ExchangeRatesTest do
  use ExUnit.Case
  alias Money.ExchangeRates

  doctest ExchangeRates

  test "Get exchange rates from ExchangeRates.Retriever" do
    test_result = {:ok, %{USD: Decimal.new(1), AUD: Decimal.new("0.7"), EUR: Decimal.new("1.2")}}
    assert Money.ExchangeRates.latest_rates() == test_result
  end


  test "that api latest_rates callbacks are executed" do
    config =
      Money.ExchangeRates.default_config()
      |> Map.put(:callback_module, Money.ExchangeRatesCallbackMock)

    Money.ExchangeRates.Retriever.reconfigure(config)
    Money.ExchangeRates.Retriever.latest_rates()

    assert Application.get_env(:ex_money, :test) == "Latest Rates Retrieved"

    Money.ExchangeRates.default_config()
    |> Money.ExchangeRates.Retriever.reconfigure()
  end

  test "that api historic_rates callbacks are executed" do
    config =
      Money.ExchangeRates.default_config()
      |> Map.put(:callback_module, Money.ExchangeRatesCallbackMock)

    Money.ExchangeRates.Retriever.reconfigure(config)
    Money.ExchangeRates.Retriever.historic_rates(~D[2017-01-01])

    assert Application.get_env(:ex_money, :test) == "Historic Rates Retrieved"

    Money.ExchangeRates.default_config()
    |> Money.ExchangeRates.Retriever.reconfigure()
  end

  test "that the last_udpated timestamp is returned in a success tuple" do
    # warm up cache
    Money.ExchangeRates.Retriever.latest_rates()

    assert {:ok, %DateTime{}} = Money.ExchangeRates.last_updated()
  end
end
