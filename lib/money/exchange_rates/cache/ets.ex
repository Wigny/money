defmodule Money.ExchangeRates.Cache.Ets do
  @moduledoc """
  `Money.ExchangeRates.Cache` implementation backed by `:ets`.

  Rates are stored in a named, public `:ets` table (`:exchange_rates`) with
  read concurrency enabled. Data is held in memory only and does not survive
  process restarts.
  """

  use Money.ExchangeRates.Cache.EtsDets

  @ets_table :exchange_rates

  @impl true
  def init do
    if :ets.info(@ets_table) == :undefined do
      :ets.new(@ets_table, [
        :named_table,
        :public,
        read_concurrency: true
      ])
    else
      @ets_table
    end
  end

  @impl true
  def terminate do
    :ok
  end

  defp get(key) do
    with tid when is_reference(tid) <- :ets.whereis(@ets_table),
         [{^key, value}] <- :ets.lookup(tid, key) do
      value
    else
      _other -> nil
    end
  end

  defp put(key, value) do
    :ets.insert(@ets_table, {key, value})
    value
  end
end
