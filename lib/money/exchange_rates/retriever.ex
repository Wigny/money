defmodule Money.ExchangeRates.Retriever do
  @moduledoc """
  A `GenServer` that retrieves exchange rates from a configured API module on a
  periodic or on-demand basis.

  Add it to your application's supervision tree to enable the exchange rates
  service:

      children = [
        MyApp.Repo,
        Money.ExchangeRates.Retriever
      ]

  To start with a custom configuration:

      children = [
        {Money.ExchangeRates.Retriever, [config: my_config]}
      ]

  Multiple named retrievers can be started independently, each backed by a
  different API source:

      children = [
        {Money.ExchangeRates.Retriever, [name: :open_exchange_rates, config: oxr_config]},
        {Money.ExchangeRates.Retriever, [name: :fixer, config: fixer_config]}
      ]

      Money.ExchangeRates.Retriever.latest_rates(:open_exchange_rates)
      Money.ExchangeRates.Retriever.historic_rates(:fixer, ~D[2024-01-01])

  By default exchange rates are retrieved from
  [Open Exchange Rates](http://openexchangerates.org). The retrieval interval
  is configured via the `:exchange_rates_retrieve_every` key (milliseconds):

      config :ex_money,
        exchange_rates_retrieve_every: 300_000

  """

  use GenServer
  require Logger

  @doc false
  def start_link(opts \\ []) do
    config = Keyword.get(opts, :config, Money.ExchangeRates.config())
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, config, name: name)
  end

  @spec latest_rates(GenServer.server()) :: {:ok, map()} | {:error, {Exception.t(), binary}}
  def latest_rates(name \\ __MODULE__) do
    case Process.whereis(name) do
      nil -> {:error, exchange_rate_service_error()}
      pid -> GenServer.call(pid, :latest_rates)
    end
  end

  @doc """
  Returns the historic exchange rates for a date.

  * `date` is a `Date.t()` with `Calendar.ISO` calendar.

  Reads from the cache if available. If the cache has no rates for the given date,
  requests a retrieval from the configured API module and stores the result before
  returning.

  Returns:

  * `{:ok, rates}` where `rates` is a map of exchange rates if available.

  * `{:error, reason}` if the retriever is not running or the API call fails.

  """
  @spec historic_rates(GenServer.server(), Date.t()) :: {:ok, map()} | {:error, {Exception.t(), binary}}
  def historic_rates(name \\ __MODULE__, %Date{calendar: Calendar.ISO} = date) do
    case Process.whereis(name) do
      nil -> {:error, exchange_rate_service_error()}
      pid -> GenServer.call(pid, {:historic_rates, date})
    end
  end

  @doc """
  Returns `true` if the latest exchange rates are available in the cache,
  `false` otherwise.

  Returns `false` when the retriever is not running, even if the cache table
  still exists.
  """
  @spec latest_rates_available?(GenServer.server()) :: boolean
  def latest_rates_available?(name \\ __MODULE__) do
    case Process.whereis(name) do
      nil -> false
      pid -> GenServer.call(pid, :latest_rates_available?)
    end
  end

  @doc """
  Returns the timestamp of the last successful exchange rate retrieval.

  Returns:

  * `{:ok, datetime}` if rates have been retrieved at least once.

  * `{:error, reason}` if the retriever is not running or no retrieval has
    occurred yet.

  """
  @spec last_updated(GenServer.server()) :: {:ok, DateTime.t()} | {:error, {Exception.t(), binary}}
  def last_updated(name \\ __MODULE__) do
    case Process.whereis(name) do
      nil -> {:error, exchange_rate_service_error()}
      pid -> GenServer.call(pid, :last_updated)
    end
  end

  @doc """
  Returns the current configuration of the Exchange Rates
  Retrieval service

  """
  def config(name \\ __MODULE__) do
    GenServer.call(name, :config)
  end

  #
  # Server implementation
  #

  @impl true
  def init(config) do
    :erlang.process_flag(:trap_exit, true)
    config.cache_module.init()

    if is_integer(config.retrieve_every) do
      log(config, :info, log_init_message(config.retrieve_every))
      schedule_retrieve_latest_rates(0)
    end

    if config.preload_historic_rates do
      log(config, :info, "Preloading historic rates for #{inspect(config.preload_historic_rates)}")
      preload_historic_rates(config.preload_historic_rates)
    end

    {:ok, config}
  end

  @impl true
  def terminate(reason, config) when reason in [:normal, :shutdown] do
    config.cache_module.terminate()
  end

  def terminate(reason, _config) do
    Logger.error("[ExchangeRates.Retriever] Unexpected terminate: #{inspect(reason)}")
  end

  @impl true
  def handle_call(:latest_rates, _from, config) do
    {:reply, retrieve_latest_rates(config), config}
  end

  def handle_call({:historic_rates, date}, _from, config) do
    {:reply, retrieve_historic_rates(date, config), config}
  end

  def handle_call(:latest_rates_available?, _from, config) do
    {:reply, match?({:ok, _rates}, config.cache_module.latest_rates()), config}
  end

  def handle_call(:last_updated, _from, config) do
    {:reply, config.cache_module.last_updated(), config}
  end

  def handle_call(:config, _from, config) do
    {:reply, config, config}
  end

  @impl true
  def handle_info(:latest_rates, config) do
    retrieve_latest_rates(config)
    schedule_retrieve_latest_rates(config.retrieve_every)
    {:noreply, config}
  end

  def handle_info({:historic_rates, %Date{calendar: Calendar.ISO} = date}, config) do
    retrieve_historic_rates(date, config)
    {:noreply, config}
  end

  def handle_info(message, config) do
    Logger.error("[ExchangeRates.Retriever] Unexpected message: #{inspect(message)}")
    {:noreply, config}
  end

  defp retrieve_latest_rates(config) do
    case config.cache_module.latest_rates() do
      {:ok, rates} -> {:ok, rates}
      {:error, _reason} -> fetch_latest_rates(config)
    end
  end

  defp fetch_latest_rates(config) do
    case config.api_module.get_latest_rates(config) do
      {:ok, :not_modified} ->
        log(config, :success, "Latest exchange rates unchanged")
        config.cache_module.latest_rates()

      {:ok, rates} ->
        retrieved_at = DateTime.utc_now()
        config.cache_module.store_latest_rates(rates, retrieved_at)

        if config.callback_module,
          do: config.callback_module.latest_rates_retrieved(rates, retrieved_at)

        log(config, :success, "Retrieved latest exchange rates successfully")
        {:ok, rates}

      {:error, reason} ->
        log(config, :failure, "Could not retrieve latest exchange rates: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp retrieve_historic_rates(date, config) do
    case config.cache_module.historic_rates(date) do
      {:ok, rates} -> {:ok, rates}
      {:error, _reason} -> fetch_historic_rates(date, config)
    end
  end

  defp fetch_historic_rates(date, config) do
    case config.api_module.get_historic_rates(date, config) do
      {:ok, :not_modified} ->
        log(config, :success, "Historic exchange rates for #{Date.to_string(date)} unchanged")
        config.cache_module.historic_rates(date)

      {:ok, rates} ->
        config.cache_module.store_historic_rates(rates, date)
        if config.callback_module, do: config.callback_module.historic_rates_retrieved(rates, date)

        log(
          config,
          :success,
          "Retrieved historic exchange rates for #{Date.to_string(date)} successfully"
        )

        {:ok, rates}

      {:error, reason} ->
        log(
          config,
          :failure,
          "Could not retrieve historic exchange rates for #{Date.to_string(date)}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp schedule_retrieve_latest_rates(delay_ms) do
    Process.send_after(self(), :latest_rates, delay_ms)
  end

  # Don't retrieve historic rates if they are
  # already cached.  Note that this is only
  # called at retriever initialization, not
  # through the public api.
  #
  # This depends on:
  # 1. The cache is persistent, like Cache.Dets
  # 2. The assumption that historic rates don't change
  # A persistent cache will reduce the number of
  # external API calls and it means the cache
  # will survive restarts both intentional and
  # unintentional
  defp preload_historic_rates(%Date.Range{} = range) do
    for date <- range do
      preload_historic_rates(date)
    end
  end

  defp preload_historic_rates(%Date{calendar: Calendar.ISO} = date) do
    Process.send(self(), {:historic_rates, date}, [])
  end

  defp log(%{log_levels: log_levels}, key, message) do
    case Map.get(log_levels, key) do
      nil -> :ok
      level -> Logger.log(level, message)
    end
  end

  defp log_init_message(every) do
    seconds = div(every, 1000)
    unit = if seconds == 1, do: "second", else: "seconds"
    {:ok, formatted} = Localize.Number.to_string(seconds)
    "Exchange Rates will be retrieved now and then every #{formatted} #{unit}."
  end

  defp exchange_rate_service_error do
    {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}
  end
end
