defmodule Money.CoverageTest do
  use ExUnit.Case, async: true

  # Exercises public functions and branches that the rest of the suite does not
  # reach. Each assertion checks real behaviour, not merely line execution.

  describe "min/2 and max/2" do
    test "min/2 returns the smaller money for every ordering" do
      assert Money.min(Money.new(:USD, 2), Money.new(:USD, 1)) == {:ok, Money.new(:USD, 1)}
      assert Money.min(Money.new(:USD, 1), Money.new(:USD, 1)) == {:ok, Money.new(:USD, 1)}
      assert Money.min(Money.new(:USD, 1), Money.new(:USD, 2)) == {:ok, Money.new(:USD, 1)}
    end

    test "max/2 returns the larger money for every ordering" do
      assert Money.max(Money.new(:USD, 1), Money.new(:USD, 2)) == {:ok, Money.new(:USD, 2)}
      assert Money.max(Money.new(:USD, 2), Money.new(:USD, 2)) == {:ok, Money.new(:USD, 2)}
      assert Money.max(Money.new(:USD, 2), Money.new(:USD, 1)) == {:ok, Money.new(:USD, 2)}
    end

    test "min/2 and max/2 error on mismatched currencies" do
      assert {:error, {_module, _message}} =
               Money.min(Money.new(:USD, 1), Money.new(:EUR, 1))

      assert {:error, {_module, _message}} =
               Money.max(Money.new(:USD, 1), Money.new(:EUR, 1))
    end
  end

  describe "min!/2 and max!/2" do
    test "min!/2 returns the smaller money for every ordering" do
      assert Money.min!(Money.new(:USD, 2), Money.new(:USD, 1)) == Money.new(:USD, 1)
      assert Money.min!(Money.new(:USD, 1), Money.new(:USD, 1)) == Money.new(:USD, 1)
      assert Money.min!(Money.new(:USD, 1), Money.new(:USD, 2)) == Money.new(:USD, 1)
    end

    test "max!/2 returns the larger money for every ordering" do
      assert Money.max!(Money.new(:USD, 1), Money.new(:USD, 2)) == Money.new(:USD, 2)
      assert Money.max!(Money.new(:USD, 2), Money.new(:USD, 2)) == Money.new(:USD, 2)
      assert Money.max!(Money.new(:USD, 2), Money.new(:USD, 1)) == Money.new(:USD, 2)
    end

    test "min!/2 and max!/2 raise on mismatched currencies" do
      assert_raise ArgumentError, fn ->
        Money.min!(Money.new(:USD, 1), Money.new(:EUR, 1))
      end

      assert_raise ArgumentError, fn ->
        Money.max!(Money.new(:USD, 1), Money.new(:EUR, 1))
      end
    end
  end

  describe "spread/2,3" do
    test "spreads an amount across an integer number of portions" do
      shares = Money.spread(Money.new(:USD, 100), 3)
      assert length(shares) == 3
      assert Money.equal?(Money.sum!(shares), Money.new(:USD, 100))
    end

    test "spreading an empty amount list returns an empty list" do
      assert Money.spread([], 3) == []
    end

    test "raises when the amount is not a Money" do
      assert_raise RuntimeError, ~r/must be Money/, fn ->
        Money.spread("not money", 3)
      end
    end
  end

  describe "round/1,2" do
    test "rounds a money to its currency digits" do
      assert Money.round(Money.new(:USD, "1.019")) == Money.new(:USD, "1.02")
    end

    test "leaves a digital token unchanged (no rounding)" do
      money = Money.new("BTC", "1.123456789")
      assert Money.round(money) == money
    end
  end

  describe "put_fraction/2" do
    test "sets the fractional part to the given number of cents" do
      assert Money.put_fraction(Money.new(:USD, "1.234"), 50) == Money.new(:USD, "1.5")
    end

    test "defaults the fraction to zero (whole units)" do
      assert Money.put_fraction(Money.new(:USD, "1.99")) == Money.new(:USD, "2.0")
    end

    test "returns an error when the requested fraction is invalid for the currency" do
      assert {:error, {Money.InvalidAmountError, _}} =
               Money.put_fraction(Money.new(:USD, "1.00"), 500)
    end
  end

  describe "reduce/1 (deprecated) delegates to normalize/1" do
    test "strips trailing zeroes like normalize/1" do
      money = Money.new(:USD, "1.00")
      assert Money.reduce(money) == Money.normalize(money)
    end
  end

  describe "new/2 and new!/2 rejected and edge inputs" do
    test "float amounts are rejected in both parameter orders" do
      assert {:error, {Money.InvalidAmountError, _}} = Money.new(:USD, 1.5)
      assert {:error, {Money.InvalidAmountError, _}} = Money.new(1.5, :USD)
    end

    test "new!/2 accepts a Decimal amount with a currency code" do
      assert Money.new!(:USD, Decimal.new(100)) == Money.new(:USD, 100)
      assert Money.new!("USD", Decimal.new(100)) == Money.new(:USD, 100)
    end
  end

  describe "put_format_options/2" do
    test "stores format options on the money" do
      money = Money.put_format_options(Money.new(:USD, 100), fractional_digits: 4)
      assert money.format_options == [fractional_digits: 4]
    end
  end

  describe "from_float!/2" do
    test "returns a money for a valid float" do
      assert Money.from_float!(:USD, 1.23) == Money.new(:USD, "1.23")
    end
  end

  describe "Subscription error and accessor paths" do
    alias Money.Subscription
    alias Money.Subscription.Plan

    test "new/3 returns a DateError for an invalid effective date" do
      plan = Plan.new!(Money.new(:USD, 100), :month)

      assert {:error, {Money.Subscription.DateError, _}} =
               Subscription.new(plan, :not_a_date)
    end

    test "new/3 returns a PlanError for an invalid plan with a valid date" do
      assert {:error, {Money.Subscription.PlanError, _}} =
               Subscription.new(:not_a_plan, ~D[2018-01-01])
    end

    test "new!/3 raises on an invalid effective date" do
      plan = Plan.new!(Money.new(:USD, 100), :month)

      assert_raise Money.Subscription.DateError, fn ->
        Subscription.new!(plan, :not_a_date)
      end
    end

    test "current_plan/2 returns nil for a subscription with no plans" do
      assert Subscription.current_plan(%{plans: []}) == nil
    end

    test "current_plan_start_date/1 returns the current plan's start date" do
      plan = Plan.new!(Money.new(:USD, 200), :month, 3)
      subscription = Subscription.new!(plan, ~D[2018-01-01])

      assert Subscription.current_plan_start_date(subscription) == ~D[2018-01-01]
    end

    test "current_interval_start_date/2 returns an error when there is no current plan" do
      assert {:error, {Money.Subscription.NoCurrentPlan, _}} =
               Subscription.current_interval_start_date(%{plans: []})
    end
  end

  describe "new/2 fallback error clauses for non-currency-code inputs" do
    test "an integer in the currency-code position is an unknown currency" do
      assert {:error, {Money.UnknownCurrencyError, _}} = Money.new(123, 456)
    end

    test "a Decimal amount with a non-currency-code first argument is unknown" do
      assert {:error, {Money.UnknownCurrencyError, _}} = Money.new(123, Decimal.new(1))
      assert {:error, {Money.UnknownCurrencyError, _}} = Money.new(Decimal.new(1), 123)
    end
  end

  describe "from_float!/2 error" do
    test "raises for an unknown currency" do
      assert_raise Money.UnknownCurrencyError, fn ->
        Money.from_float!(:NOTACUR, 1.5)
      end
    end
  end

  describe "sum/2 with an explicit rates result" do
    test "sums using rates wrapped in an {:ok, rates} tuple" do
      rates = %{AUD: Decimal.new("0.5"), EUR: Decimal.new("2")}

      assert Money.sum([Money.new(:USD, 100), Money.new(:AUD, 100)], {:ok, rates}) ==
               Money.sum([Money.new(:USD, 100), Money.new(:AUD, 100)], rates)
    end

    test "returns the error when the rates lookup failed" do
      assert Money.sum([Money.new(:USD, 100)], {:error, :boom}) == {:error, :boom}
    end
  end

  describe "get_env/3 coercions" do
    setup do
      Application.put_env(:ex_money, :cov_int, "42")
      Application.put_env(:ex_money, :cov_bool, true)
      Application.put_env(:ex_money, :cov_bad_bool, "yes")
      Application.put_env(:ex_money, :cov_system, {:system, "COV_ENV_ABSENT"})

      on_exit(fn ->
        Application.delete_env(:ex_money, :cov_int)
        Application.delete_env(:ex_money, :cov_bool)
        Application.delete_env(:ex_money, :cov_bad_bool)
        Application.delete_env(:ex_money, :cov_system)
      end)
    end

    test "coerces an :integer value" do
      assert Money.get_env(:cov_int, 0, :integer) == 42
    end

    test "returns a :boolean value unchanged" do
      assert Money.get_env(:cov_bool, false, :boolean) == true
    end

    test "raises for a non-boolean :boolean value" do
      assert_raise RuntimeError, ~r/must be either true or false/, fn ->
        Money.get_env(:cov_bad_bool, false, :boolean)
      end
    end

    test "resolves a {:system, var} value, falling back to the default when unset" do
      assert Money.get_env(:cov_system, "fallback") == "fallback"
    end
  end

  describe "JSON encoding" do
    test "Jason.Encoder serialises currency and amount" do
      encoded = Jason.encode!(Money.new(:USD, "100.00"))
      assert encoded =~ ~s|"currency":"USD"|
      assert encoded =~ ~s|"amount":"100.00"|
    end

    if Code.ensure_loaded?(JSON) do
      test "the built-in JSON.Encoder serialises currency and amount" do
        encoded = JSON.encode!(Money.new(:USD, "100.00"))
        assert encoded =~ ~s|"currency":"USD"|
        assert encoded =~ ~s|"amount":"100.00"|
      end
    end
  end
end
