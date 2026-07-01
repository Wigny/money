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

    test "compile-time validity matches store registration (build/2) exactly" do
      previous = Application.get_env(:ex_money, :custom_currencies)

      # One buildable entry, one with a valid code but missing :name (the store
      # cannot register it), and one malformed code. Compile-time acceptance
      # must equal store registration for every one of them.
      specs = [
        {:XVA, [name: "Valid"]},
        {:XVO, []},
        {:AB, [name: "Too Short"]}
      ]

      Application.put_env(:ex_money, :custom_currencies, specs)

      try do
        for {code, options} <- specs do
          registers? = match?({:ok, _}, Money.Currency.build(code, options))
          assert Money.Currency.configured?(code) == registers?
        end

        # Concretely: only the buildable entry is accepted at compile time.
        assert Money.Currency.configured?(:XVA)
        refute Money.Currency.configured?(:XVO)
        refute Money.Currency.configured?(:AB)
      after
        if previous do
          Application.put_env(:ex_money, :custom_currencies, previous)
        else
          Application.delete_env(:ex_money, :custom_currencies)
        end
      end
    end

    test "a malformed code is not accepted as a currency even when declared in configuration" do
      previous = Application.get_env(:ex_money, :custom_currencies)

      # "AB" is too short and "1XY" starts with a digit — neither conforms to the
      # custom/private currency code format, so the configuration fallback must
      # not treat them as valid currencies even though they are declared. This
      # mirrors the store, which logs and skips such entries at startup.
      # (Whether such a code resolves to a digital token is a separate concern;
      # the point here is that it must not validate as the configured currency.)
      Application.put_env(:ex_money, :custom_currencies, [
        {:AB, name: "Too Short"},
        {:"1XY", name: "Digit First"}
      ])

      try do
        refute Money.validate_currency("AB") == {:ok, :AB}
        refute Money.validate_currency("1XY") == {:ok, :"1XY"}
      after
        if previous do
          Application.put_env(:ex_money, :custom_currencies, previous)
        else
          Application.delete_env(:ex_money, :custom_currencies)
        end
      end
    end
  end
end
