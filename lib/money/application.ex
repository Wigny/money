defmodule Money.Application do
  @moduledoc false
  use Application
  require Logger

  @impl true
  def start(_type, args) do
    children = [
      Money.Currency.Store
      | exchange_rate_supervisor()
    ]

    opts =
      if args == [] do
        [strategy: :one_for_one, name: Money.Supervisor]
      else
        args
      end

    # Currencies declared in `:custom_currencies` are registered by
    # `Money.Currency.Store` when it starts (and after any restart), so no
    # separate registration step is required here.
    Supervisor.start_link(children, opts)
  end

  defp exchange_rate_supervisor do
    maybe_log_deprecation()

    if Money.get_env(:auto_start_exchange_rate_service, true, :boolean) do
      [Money.ExchangeRates.Supervisor]
    else
      []
    end
  end

  @doc """
  Registers the currencies declared in the `:custom_currencies` configuration
  into the running currency store.

  This is an escape hatch, not the normal flow. Configured currencies are
  registered automatically by `Money.Currency.Store` when it starts, and again
  after any supervisor restart, so most applications never call this function.
  Use it only to re-apply the configuration to an already-running store after
  changing `:custom_currencies` at runtime. Currencies that are already
  registered are left unchanged, and any entry that fails to register is logged
  and skipped rather than raised.

  ### Returns

  * `:ok` in all cases. Per-currency failures are emitted as log warnings, not
    returned.

  ### Examples

      iex> Money.Application.register_custom_currencies()
      :ok

  """
  @spec register_custom_currencies() :: :ok
  def register_custom_currencies do
    Money.Currency.configured_currency_specs()
    |> Enum.each(&register_configured_currency/1)
  end

  defp register_configured_currency({code, options}) do
    case Money.Currency.new(code, options) do
      {:ok, _currency} ->
        :ok

      {:error, exception} ->
        Logger.warning(
          "Failed to register custom currency #{inspect(code)}: " <>
            Exception.message(exception)
        )
    end
  end

  defp register_configured_currency(other) do
    Logger.warning(
      "Ignoring invalid :custom_currencies entry #{inspect(other)}; " <>
        "expected a {code, options} tuple"
    )
  end

  @doc false
  @spec maybe_log_deprecation() :: :ok | nil
  def maybe_log_deprecation do
    case Application.fetch_env(:ex_money, :delay_before_first_retrieval) do
      {:ok, _} ->
        Logger.warning(
          "[ex_money] Configuration option :delay_before_first_retrieval is deprecated. " <>
            "Please remove it from your configuration."
        )

        Application.delete_env(:ex_money, :delay_before_first_retrieval)

      :error ->
        nil
    end

    case Application.fetch_env(:ex_money, :exchange_rate_service) do
      {:ok, start?} ->
        Logger.warning(
          "[ex_money] Configuration option :exchange_rate_service is deprecated " <>
            "in favour of :auto_start_exchange_rate_service.  Please " <>
            "update your configuration."
        )

        Application.put_env(:ex_money, :auto_start_exchange_rate_service, start?)
        Application.delete_env(:ex_money, :exchange_rate_service)

      :error ->
        nil
    end

    case Application.fetch_env(:ex_money, :auto_start_exchange_rate_service) do
      {:ok, true} ->
        Logger.warning(
          "[ex_money] Automatically starting the exchange rate service is deprecated. " <>
            "Set `auto_start_exchange_rate_service: false` and add " <>
            "`Money.ExchangeRates.Retriever` to your supervision tree."
        )

      {:ok, false} ->
        nil

      :error ->
        Logger.warning(
          "[ex_money] Automatically starting the exchange rate service is deprecated. " <>
            "Set `auto_start_exchange_rate_service: false` and, if you use the service, " <>
            "add `Money.ExchangeRates.Retriever` to your supervision tree."
        )
    end
  end
end
