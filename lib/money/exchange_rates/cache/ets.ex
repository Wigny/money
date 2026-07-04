defmodule Money.ExchangeRates.Cache.Ets do
  @moduledoc """
  Money.ExchangeRates.Cache implementation for
  :ets
  """

  use Money.ExchangeRates.Cache.EtsDets

  @impl true
  def init(name) do
    if :ets.info(name) == :undefined do
      :ets.new(name, [
        :named_table,
        :public,
        read_concurrency: true
      ])
    else
      name
    end
  end

  @impl true
  def terminate(_table) do
    :ok
  end

  defp get(table, key) do
    with tid when tid != :undefined <- :ets.whereis(table),
         [{^key, value}] <- :ets.lookup(tid, key) do
      value
    else
      _ -> nil
    end
  end

  defp put(table, key, value) do
    :ets.insert(table, {key, value})
    value
  end
end
