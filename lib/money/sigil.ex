defmodule Money.Sigil do
  @moduledoc """
  Implements the `~M` sigil for constructing `t:Money.t/0` values.

  Import the module to bring the sigil into scope:

      import Money.Sigil
      ~M[1000]USD

  """

  @doc ~S"""
  Implements the sigil `~M` for Money

  The lower case `~m` variant does not exist as interpolation and excape
  characters are not useful for Money sigils.

  ## Example

      iex> import Money.Sigil
      iex> ~M[1000]usd
      Money.new(:USD, "1000")
      iex> ~M[1000.34]usd
      Money.new(:USD, "1000.34")

  """
  @spec sigil_M(binary, list(char)) :: Money.t() | {:error, {module(), String.t()}}
  def sigil_M(amount, [_ | _] = currency) do
    Money.new(to_decimal(amount), atomize(currency))
  end

  defp to_decimal(string) do
    string
    |> String.replace("_", "")
    |> Decimal.new()
  end

  defp atomize(currency) do
    currency
    |> List.to_string()
    |> validate_currency!
  end

  def validate_currency!(currency) do
    case Money.validate_currency(currency) do
      {:ok, currency} ->
        currency

      {:error, {_exception, reason}} ->
        store_running? = Process.whereis(Money.Currency.Store) != nil
        raise Money.UnknownCurrencyError, unknown_currency_message(currency, reason, store_running?)
    end
  end

  @doc false
  # Builds the error message raised when a `~M` sigil names an unknown
  # currency. Custom and private currencies are registered at runtime, so a
  # tailored message is produced to explain why one may be unavailable. The
  # `store_running?` argument distinguishes a compile-time use (the currency
  # store is not running, e.g. the sigil is in a module attribute) from a
  # runtime use where the currency simply has not been registered.
  @spec unknown_currency_message(String.t(), String.t(), boolean()) :: String.t()
  def unknown_currency_message(currency, default_reason, store_running?) do
    cond do
      not Money.Currency.private_or_custom_code?(currency) ->
        default_reason

      store_running? ->
        "The currency #{inspect(currency)} looks like a private or custom currency but is not " <>
          "registered. Register it at application start with the :custom_currencies configuration " <>
          "key or with Money.Currency.new/2 before use."

      true ->
        "The currency #{inspect(currency)} looks like a private or custom currency. Currencies " <>
          "added at runtime with Money.Currency.new/2 are not available in a compile-time position " <>
          "such as a module attribute, a defstruct default or a module body. Declare it in the " <>
          ":custom_currencies configuration to use it here, or move the sigil into a function body."
    end
  end
end
