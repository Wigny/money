defmodule Money.ExchangeRates.Cache.Dets do
  @moduledoc """
  `Money.ExchangeRates.Cache` implementation backed by `:dets`.

  Rates are stored in a `:dets` file (`<tmp_dir>/.exchange_rates`) and survive
  process restarts. The table is opened on `init/0` and flushed to disk on
  `terminate/0`.
  """

  use Money.ExchangeRates.Cache.EtsDets

  @ets_table :exchange_rates

  @impl true
  def init do
    path = System.tmp_dir!() |> Path.join(".exchange_rates") |> String.to_charlist()
    {:ok, name} = :dets.open_file(@ets_table, file: path)
    name
  end

  @impl true
  def terminate do
    :dets.close(@ets_table)
  end

  defp get(key) do
    case :dets.lookup(@ets_table, key) do
      [{^key, value}] -> value
      [] -> nil
    end
  end

  defp put(key, value) do
    :dets.insert(@ets_table, {key, value})
    value
  end
end
