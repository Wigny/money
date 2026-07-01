defmodule Money.CompileTimeCurrencyTest do
  # async: false because some tests mutate the :custom_currencies application
  # environment, which is global.
  use ExUnit.Case, async: false

  import Money.Sigil

  # These module attributes are evaluated at COMPILE TIME, reproducing the
  # scenario from https://github.com/kipcole9/money/issues/195 where a private
  # or custom currency is used in a compile-time position. They compile only
  # because :XCT is declared in the :custom_currencies configuration (see
  # config/test.exs), which is readable at compile time.
  @sigil_price ~M[100]XCT
  @new_price Money.new(:XCT, "250.50")

  describe "compile-time positions" do
    test "a configured currency can be used in a ~M sigil module attribute" do
      assert %Money{currency: :XCT} = @sigil_price
      assert @sigil_price == Money.new!(:XCT, "100")
    end

    test "a configured currency can be used with Money.new/2 in a module attribute" do
      assert %Money{currency: :XCT} = @new_price
      assert Decimal.equal?(@new_price.amount, Decimal.new("250.50"))
    end

    test "a struct built at compile time formats at runtime via the store" do
      assert {:ok, formatted} = Money.to_string(@new_price)
      assert formatted =~ "250.50"
    end
  end

  describe "configuration as a validation source" do
    test "a configured currency validates even when it is not in the store" do
      previous = Application.get_env(:ex_money, :custom_currencies)

      # Declare a currency in configuration but do not register it in the store
      # (the store is not restarted). This reproduces compile time, where the
      # configuration is readable but the store is unavailable.
      Application.put_env(:ex_money, :custom_currencies, [{:XCF, name: "Config Fallback"}])

      try do
        assert Money.Currency.Store.get(:XCF) == nil
        assert Money.validate_currency("XCF") == {:ok, :XCF}
        assert Money.validate_currency(:XCF) == {:ok, :XCF}
      after
        if previous do
          Application.put_env(:ex_money, :custom_currencies, previous)
        else
          Application.delete_env(:ex_money, :custom_currencies)
        end
      end
    end

    test "the configured currency from config/test.exs validates" do
      assert Money.validate_currency("XCT") == {:ok, :XCT}
    end

    test "a private currency that is neither configured nor registered is unknown" do
      assert {:error, {Money.UnknownCurrencyError, _reason}} = Money.validate_currency("XZZ")
    end
  end
end
