defmodule Money.ExchangeRates.Callback do
  @moduledoc """
  Behaviour for exchange rates retrieval callbacks.

  Implement this behaviour to react to successful rate retrievals — for
  example, to persist rates to a database or broadcast them to subscribers.
  Configure the implementing module via the `:callback_module` application
  config key. The default is `nil`, meaning no callbacks are invoked.

  Implementations must not raise. Any exception propagates through the
  Retriever and may interrupt the scheduled retrieval cycle.
  """

  @doc """
  Invoked after the latest exchange rates have been successfully retrieved.
  Use this callback to perform any desired side effects such as persisting
  rates to a database.
  """
  @callback latest_rates_retrieved(%{}, DateTime.t()) :: :ok

  @doc """
  Invoked after historic exchange rates for a given date have been successfully
  retrieved. Use this callback to perform any desired side effects such as
  persisting rates to a database.
  """
  @callback historic_rates_retrieved(%{}, Date.t()) :: :ok
end
