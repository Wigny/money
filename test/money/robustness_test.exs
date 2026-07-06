defmodule Money.RobustnessTest do
  # async: false — these tests restart the custom currency store and start
  # named retrievers, both of which touch global state.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Money.ExchangeRates.Retriever

  # An exchange rates API module that always raises, simulating a provider
  # response that cannot be decoded.
  defmodule RaisingApi do
    @behaviour Money.ExchangeRates

    @impl true
    def get_latest_rates(_config), do: raise(ArgumentError, "malformed provider response")

    @impl true
    def get_historic_rates(_date, _config), do: raise(ArgumentError, "malformed provider response")
  end

  # A callback module that always raises, simulating a defective user callback.
  defmodule RaisingCallback do
    @behaviour Money.ExchangeRates.Callback

    @impl true
    def latest_rates_retrieved(_rates, _retrieved_at), do: raise(RuntimeError, "callback boom")

    @impl true
    def historic_rates_retrieved(_rates, _date), do: raise(RuntimeError, "callback boom")
  end

  # A cache that never holds anything, so every retrieval is forced through
  # the API module regardless of what other tests have cached in the shared
  # ETS cache.
  defmodule EmptyCache do
    @behaviour Money.ExchangeRates.Cache

    @impl true
    def init, do: :ok
    @impl true
    def terminate, do: :ok
    @impl true
    def latest_rates, do: {:error, {Money.ExchangeRateError, "empty"}}
    @impl true
    def historic_rates(_date), do: {:error, {Money.ExchangeRateError, "empty"}}
    @impl true
    def last_updated, do: {:error, {Money.ExchangeRateError, "empty"}}
    @impl true
    def store_latest_rates(_rates, _retrieved_at), do: :ok
    @impl true
    def store_historic_rates(_rates, _date), do: :ok
  end

  # Returns a money whose custom currency is no longer resolvable: the
  # currency is registered at runtime, the money created, and then the store
  # is restarted (runtime-registered currencies are intentionally not
  # restored). This is the realistic path by which `Money.round/2` returns an
  # error tuple for an otherwise valid-looking money.
  defp money_with_lost_currency(code, amount) do
    case Money.Currency.new(code, name: "Ephemeral #{code}") do
      {:ok, _} -> :ok
      {:error, %Money.CurrencyAlreadyDefinedError{}} -> :ok
    end

    money = Money.new(code, amount)

    :ok = Supervisor.terminate_child(Money.Supervisor, Money.Currency.Store)
    {:ok, pid} = Supervisor.restart_child(Money.Supervisor, Money.Currency.Store)
    _ = :sys.get_state(pid)

    assert {:error, _} = Money.Currency.currency_for_code(code)
    money
  end

  describe "round/2 error propagation" do
    test "spread/2 returns an error tuple when the currency cannot be resolved" do
      money = money_with_lost_currency(:XRB1, "100.126")

      assert {:error, {Money.UnknownCurrencyError, _}} = Money.spread(money, 3)
    end

    test "to_integer_exp/1 returns an error tuple when the currency cannot be resolved" do
      money = money_with_lost_currency(:XRB2, "100.126")

      assert {:error, {Money.UnknownCurrencyError, _}} = Money.to_integer_exp(money)
    end

    test "Subscription.change_plan/3 returns an error tuple when the plan currency cannot be resolved" do
      money = money_with_lost_currency(:XRB3, "100")

      plan_1 = %{price: money, interval: :month, interval_count: 1}
      plan_2 = %{price: money, interval: :month, interval_count: 1}

      assert {:error, {Money.UnknownCurrencyError, _}} =
               Money.Subscription.change_plan(
                 plan_1,
                 plan_2,
                 current_interval_started: ~D[2026-01-01],
                 effective: ~D[2026-01-15],
                 prorate: :price
               )
    end
  end

  describe "new/3 locale error surfacing" do
    test "an invalid :locale option is reported as the cause" do
      assert {:error, {Money.Invalid, message}} =
               Money.new(:USD, "1.234,56", locale: "not a locale!!")

      assert message =~ ":locale option is invalid"
      assert message =~ "not a locale!!"
    end

    test "a valid :locale option still parses a localized amount" do
      assert Money.new(:USD, "1.234,56", locale: "de") == Money.new(:USD, "1234.56")
    end
  end

  defp start_retriever(config) do
    name = :"robustness_#{System.unique_integer([:positive])}"
    pid = start_supervised!({Retriever, [name: name, config: config]}, id: name)
    _ = :sys.get_state(pid)
    {name, pid}
  end

  describe "retriever exception boundaries" do
    test "a raising api module returns an error tuple and does not crash the retriever" do
      config = %{
        Money.ExchangeRates.default_config()
        | api_module: RaisingApi,
          cache_module: EmptyCache,
          log_levels: %{success: nil, failure: nil, info: nil}
      }

      {name, pid} = start_retriever(config)

      assert {:error, {Money.ExchangeRateError, message}} = Retriever.latest_rates(name)
      assert message =~ "RaisingApi"
      assert message =~ "malformed provider response"
      assert Process.alive?(pid)

      assert {:error, {Money.ExchangeRateError, _}} =
               Retriever.historic_rates(name, ~D[2026-01-01])

      assert Process.alive?(pid)
    end

    test "a raising callback module logs the exception but keeps the retrieved rates" do
      config = %{
        Money.ExchangeRates.default_config()
        | api_module: Money.ExchangeRatesMock,
          callback_module: RaisingCallback,
          cache_module: EmptyCache,
          log_levels: %{success: nil, failure: :warning, info: nil}
      }

      {name, pid} = start_retriever(config)

      log =
        capture_log(fn ->
          assert {:ok, %{USD: _}} = Retriever.latest_rates(name)
        end)

      assert log =~ "RaisingCallback"
      assert log =~ "callback boom"
      assert Process.alive?(pid)
    end
  end
end
