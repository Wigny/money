defmodule Money.ExchangeRates.OpenExchangeRates do
  @moduledoc """
  Implements the `Money.ExchangeRates` for the Open Exchange
  Rates service.

  ## Required configuration:

  The configuration key `:open_exchange_rates_app_id` should be
  set to your `app_id`. For example:

      config :ex_money,
        open_exchange_rates_app_id: "your_app_id"

  or configure it via environment variable:

      config :ex_money,
        open_exchange_rates_app_id: {:system, "OPEN_EXCHANGE_RATES_APP_ID"}

  It is also possible to configure an alternative base url for this
  service in case it changes in the future. For example:

      config :ex_money,
        open_exchange_rates_app_id: "your_app_id"
        open_exchange_rates_url: "https://openexchangerates.org/alternative_api"

  """

  @behaviour Money.ExchangeRates

  @open_exchange_rate_url "https://openexchangerates.org/api"
  @etag_cache :open_exchange_rates_etag_cache

  @doc """
  Update the retriever configuration to include the requirements
  for Open Exchange Rates. This function is invoked when the
  exchange rate service starts up, just after the ets table
  :exchange_rates is created.

  * `default_config` is the configuration returned by `Money.ExchangeRates.default_config/0`

  Returns the configuration either unchanged or updated with
  additional configuration specific to this exchange
  rates retrieval module.
  """
  @impl true
  def init(default_config) do
    url = Money.get_env(:open_exchange_rates_url, @open_exchange_rate_url)
    app_id = Money.get_env(:open_exchange_rates_app_id, nil)

    if :ets.info(@etag_cache) == :undefined do
      :ets.new(@etag_cache, [:named_table, :public])
    end

    Map.put(default_config, :retriever_options, %{url: url, app_id: app_id})
  end

  @doc """
  Retrieves the latest exchange rates from Open Exchange Rates site.

  * `config` is the retrieval configuration. When invoked from the
  exchange rates service this will be the config returned from
  `Money.ExchangeRates.config/0`

  Returns:

  * `{:ok, rates}` if the rates can be retrieved

  * `{:ok, :not_modified}` if the rates are unchanged since the last retrieval

  * `{:error, reason}` if rates cannot be retrieved

  Typically this function is called by the exchange rates retrieval
  service although it can be called outside that context as
  required. When called outside the retrieval service, `init/1`
  must be called first to initialise the ETag cache.

  """
  @impl true
  def get_latest_rates(config) do
    url = config.retriever_options.url
    app_id = config.retriever_options.app_id
    retrieve_latest_rates(url, app_id, config)
  end

  defp retrieve_latest_rates(_url, nil, _config) do
    {:error, app_id_not_configured()}
  end

  @latest_rates "/latest.json"
  defp retrieve_latest_rates(url, app_id, config) do
    request(url <> @latest_rates <> "?app_id=" <> app_id, config)
  end

  @doc """
  Retrieves the historic exchange rates from Open Exchange Rates site.

  * `date` is a `Date.t` or any date-compatible map or struct (`Calendar.date/0`).

  * `config` is the retrieval configuration. When invoked from the
    exchange rates service this will be the config returned from
    `Money.ExchangeRates.config/0`

  Returns:

  * `{:ok, rates}` if the rates can be retrieved

  * `{:error, reason}` if rates cannot be retrieved

  Typically this function is called by the exchange rates retrieval
  service although it can be called outside that context as
  required. When called outside the retrieval service, `init/1`
  must be called first to initialise the ETag cache.
  """
  @impl true
  def get_historic_rates(date, config) do
    url = config.retriever_options.url
    app_id = config.retriever_options.app_id
    retrieve_historic_rates(date, url, app_id, config)
  end

  defp retrieve_historic_rates(_date, _url, nil, _config) do
    {:error, app_id_not_configured()}
  end

  @historic_rates "/historical/"
  defp retrieve_historic_rates(date, url, app_id, config) do
    request(
      url <> @historic_rates <> Date.to_string(date) <> ".json" <> "?app_id=" <> app_id,
      config
    )
  end

  defp request(url, config) do
    headers = if_none_match_header(url)
    http_client = Money.get_env(:exchange_rates_http_client, Localize.Utils.Http, :module)

    {url, headers}
    |> http_client.get_with_headers(verify_peer: config.verify_peer)
    |> process_response(url)
  end

  defp process_response({:ok, headers, body}, url) do
    cache_etag(headers, url)
    {:ok, decode_rates(body)}
  end

  defp process_response({:not_modified, headers}, url) do
    cache_etag(headers, url)
    {:ok, :not_modified}
  end

  defp process_response({:error, reason}, _url) do
    {:error, {Money.ExchangeRateError, "#{inspect(reason)}"}}
  end

  defp if_none_match_header(url) do
    case get_etag(url) do
      {etag, date} ->
        [
          {~c"If-None-Match", etag},
          {~c"If-Modified-Since", date}
        ]

      _ ->
        []
    end
  end

  defp cache_etag(headers, url) do
    etag = :proplists.get_value(~c"etag", headers)
    date = :proplists.get_value(~c"date", headers)

    if etag != :undefined and date != :undefined do
      :ets.insert(@etag_cache, {url, {etag, date}})
    else
      :ets.delete(@etag_cache, url)
    end
  end

  defp get_etag(url) do
    case :ets.lookup(@etag_cache, url) do
      [{^url, cached_value}] -> cached_value
      [] -> nil
    end
  end

  defp decode_rates(body) when is_list(body) do
    body
    |> List.to_string()
    |> decode_rates()
  end

  defp decode_rates(body) when is_binary(body) do
    %{"base" => _base, "rates" => rates} = :json.decode(body)

    rates
    |> Localize.Utils.Map.atomize_keys()
    |> Enum.map(fn
      {k, v} when is_float(v) -> {k, Decimal.from_float(v)}
      {k, v} when is_integer(v) -> {k, Decimal.new(v)}
    end)
    |> Enum.into(%{})
  end

  defp app_id_not_configured do
    "Open Exchange Rates app_id is not configured. Rates are not retrieved."
  end
end
