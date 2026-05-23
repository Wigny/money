defmodule Money.ExchangeRatesCallbackMock do
  @behaviour Money.ExchangeRates.Callback

  @impl true
  def latest_rates_retrieved(_rates, _retrieved_at) do
    :ok
  end

  @impl true
  def historic_rates_retrieved(_rates, _date) do
    :ok
  end
end
