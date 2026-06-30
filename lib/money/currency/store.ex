defmodule Money.Currency.Store do
  @moduledoc """
  Persistent-term-backed store for custom currencies.

  Custom currencies are currencies defined with `Money.Currency.new/2`,
  either at runtime or declaratively through the `:custom_currencies`
  application configuration. They are stored in `:persistent_term` for
  fast concurrent read access.

  This module is started as part of the Money application supervision
  tree. Currencies declared in `:custom_currencies` are registered each
  time the store starts, so they are restored automatically after a
  supervisor restart; currencies added at runtime with
  `Money.Currency.new/2` are not.

  """

  use GenServer
  require Logger

  @persistent_key {:ex_money, :custom_currencies}

  # ── Client API ────────────────────────────────────────────────

  @doc """
  Starts the custom currency store.

  """
  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc """
  Returns all custom currencies as a map of `%{currency_code => currency_struct}`.

  ### Returns

  * A map of custom currencies. Returns an empty map if no custom
    currencies have been defined.

  """
  @spec all() :: %{atom() => Localize.Currency.t()}
  def all do
    :persistent_term.get(@persistent_key, %{})
  end

  @doc """
  Returns a list of all custom currency codes.

  ### Returns

  * A list of atom currency codes.

  """
  @spec codes() :: [atom()]
  def codes do
    Map.keys(all())
  end

  @doc """
  Stores a custom currency.

  ### Arguments

  * `currency` is a `t:Localize.Currency.t/0` struct.

  ### Returns

  * `{:ok, currency}` on success.

  * `{:error, Money.CurrencyNotSavedError.t()}` if the store
    is not running.

  """
  @spec put(Localize.Currency.t()) ::
          {:ok, Localize.Currency.t()} | {:error, Exception.t()}
  def put(%Localize.Currency{} = currency) do
    GenServer.call(__MODULE__, {:put, currency})
  catch
    :exit, _reason ->
      {:error, Money.CurrencyNotSavedError.exception(currency: currency.code)}
  end

  @doc """
  Returns the custom currency for the given code, or `nil`.

  ### Arguments

  * `code` is a currency code atom.

  ### Returns

  * A `t:Localize.Currency.t/0` struct or `nil`.

  """
  @spec get(atom()) :: Localize.Currency.t() | nil
  def get(code) when is_atom(code) do
    Map.get(all(), code)
  end

  # ── Server callbacks ──────────────────────────────────────────

  @impl true
  def init(_options) do
    # Currencies declared in the `:custom_currencies` configuration are
    # materialised here so that they are (re-)registered every time the store
    # starts, including after a supervisor restart. Runtime currencies added
    # later with `Money.Currency.new/2` do not survive a restart.
    currencies = configured_currencies()
    :persistent_term.put(@persistent_key, currencies)
    {:ok, currencies}
  end

  defp configured_currencies do
    :ex_money
    |> Application.get_env(:custom_currencies, [])
    |> List.wrap()
    |> Enum.reduce(%{}, &put_configured_currency/2)
  end

  defp put_configured_currency({code, options}, currencies) do
    case Money.Currency.build(code, options) do
      {:ok, currency} ->
        Map.put(currencies, currency.code, currency)

      {:error, exception} ->
        Logger.warning(
          "Failed to register custom currency #{inspect(code)}: " <>
            Exception.message(exception)
        )

        currencies
    end
  end

  defp put_configured_currency(other, currencies) do
    Logger.warning(
      "Ignoring invalid :custom_currencies entry #{inspect(other)}; " <>
        "expected a {code, options} tuple"
    )

    currencies
  end

  @impl true
  def handle_call({:put, %Localize.Currency{code: code} = currency}, _from, state) do
    currencies = :persistent_term.get(@persistent_key, %{})
    updated = Map.put(currencies, code, currency)
    :persistent_term.put(@persistent_key, updated)
    {:reply, {:ok, currency}, state}
  end
end
