defmodule Money.AtomSafetyTest do
  use ExUnit.Case, async: false

  # Unknown currency codes frequently arrive from untrusted sources (URL
  # params, form fields, JSON). Converting them with `String.to_atom/1` would
  # let an attacker exhaust the atom table and crash the BEAM. These tests
  # assert the currency code never becomes a *new* atom — proved directly
  # (the atom does not exist before or after), so the result is immune to
  # atom-table noise from other tests.

  defp atom_exists?(string) do
    _ = String.to_existing_atom(string)
    true
  rescue
    ArgumentError -> false
  end

  describe "no atoms are created for unknown currency codes" do
    test "Money.validate_currency/1 does not mint an atom" do
      code = "ZQUNMINT1"
      refute atom_exists?(code)

      assert {:error, {Money.UnknownCurrencyError, _}} = Money.validate_currency(code)

      refute atom_exists?(code)
    end

    test "Money.new/2 does not mint an atom" do
      code = "ZQUNMINT2"
      refute atom_exists?(code)

      assert {:error, {Money.UnknownCurrencyError, _}} = Money.new("100", code)

      refute atom_exists?(code)
    end

    test "Money.Currency.currency_for_code/1 does not mint an atom" do
      code = "ZQUNMINT3"
      refute atom_exists?(code)

      assert {:error, {Money.UnknownCurrencyError, _}} = Money.Currency.currency_for_code(code)

      refute atom_exists?(code)
    end

    test "a bulk of distinct unknown codes mints no atoms" do
      codes = for n <- 1..500, do: "ZQBULK" <> Integer.to_string(n)

      Enum.each(codes, fn code ->
        assert {:error, {Money.UnknownCurrencyError, _}} = Money.validate_currency(code)
      end)

      Enum.each(codes, fn code ->
        refute atom_exists?(String.upcase(code))
      end)
    end

    test "the unknown-currency message reflects the code as given" do
      assert {:error, {Money.UnknownCurrencyError, message}} = Money.validate_currency("nosuchcur")
      assert message == "The currency \"nosuchcur\" is not known."

      assert {:error, {Money.UnknownCurrencyError, atom_message}} =
               Money.validate_currency(:NOSUCHATOM)

      assert atom_message == "The currency :NOSUCHATOM is not known."
    end
  end

  describe "known and registered currencies still validate" do
    test "ISO currencies validate without case sensitivity" do
      assert {:ok, :USD} = Money.validate_currency("usd")
      assert {:ok, :USD} = Money.validate_currency(:USD)
    end

    test "a registered private currency validates" do
      case Money.Currency.new(:XAS, name: "Atom Safety Currency") do
        {:ok, _} -> :ok
        {:error, %Money.CurrencyAlreadyDefinedError{}} -> :ok
      end

      assert {:ok, :XAS} = Money.validate_currency("xas")
      assert {:ok, :XAS} = Money.validate_currency(:XAS)
    end
  end
end
