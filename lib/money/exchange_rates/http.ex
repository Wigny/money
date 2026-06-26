defmodule Money.ExchangeRates.HTTP do
  @moduledoc false

  @doc """
  Performs an HTTP GET request, automatically attaching conditional request headers
  (`if-none-match`, `if-modified-since`) from a node-wide ETag cache keyed by URL.
  Persists response headers back into the cache after each request.

  Returns:

  * `{:ok, body}` — the request succeeded and `body` contains the response body
  * `{:ok, :not_modified}` — the server returned 304; the cached response is still valid
  * `{:error, {Money.ExchangeRateError, reason}}` — the request failed
  """
  @spec get(url :: binary, opts :: keyword) ::
          {:ok, term} | {:ok, :not_modified} | {:error, {Money.ExchangeRateError, binary}}
  def get(url, opts \\ []) do
    cache = init_cache()

    http_client = Money.get_env(:exchange_rates_http_client, Localize.Utils.Http, :module)

    case http_client.get_with_headers({url, build_headers(cache, url)}, opts) do
      {:ok, headers, body} ->
        save_headers(cache, url, headers)
        {:ok, body}

      {:not_modified, headers} ->
        save_headers(cache, url, headers)
        {:ok, :not_modified}

      {:error, reason} ->
        {:error, {Money.ExchangeRateError, "#{inspect(reason)}"}}
    end
  end

  # The ETag cache is a node-wide named table shared by all retrievers. Because
  # multiple named retrievers may call `get/2` concurrently, creation must be
  # race-safe: two processes can both observe `:undefined` from `:ets.whereis/1`
  # and then race on `:ets.new/2`, where the loser would raise `ArgumentError`
  # for a duplicate named table. Rescue that case and return the existing table.
  defp init_cache do
    case :ets.whereis(:etag_cache) do
      :undefined ->
        try do
          :ets.new(:etag_cache, [:named_table, :public])
        rescue
          ArgumentError -> :etag_cache
        end

      _table ->
        :etag_cache
    end
  end

  defp build_headers(cache, url) do
    etag = :ets.lookup_element(cache, url, 2, nil)
    last_modified = :ets.lookup_element(cache, url, 3, nil)

    Enum.reject(
      [{~c"if-none-match", etag}, {~c"if-modified-since", last_modified}],
      &is_nil(elem(&1, 1))
    )
  end

  defp save_headers(cache, url, headers) do
    etag = :proplists.get_value(~c"etag", headers, nil)
    last_modified = :proplists.get_value(~c"last-modified", headers, nil)
    :ets.insert(cache, {url, etag, last_modified})
  end
end
