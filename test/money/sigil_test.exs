defmodule Money.SigilTest do
  use ExUnit.Case, async: false

  import Money.Sigil

  doctest Money.Sigil

  defp ensure_currency(code, options) do
    case Money.Currency.new(code, options) do
      {:ok, _currency} -> :ok
      {:error, %Money.CurrencyAlreadyDefinedError{}} -> :ok
    end
  end

  describe "~M with ISO currencies" do
    test "resolves a known ISO currency" do
      assert ~M[100]USD == Money.new(:USD, "100")
    end
  end

  describe "~M with private currencies" do
    test "resolves a registered private currency" do
      ensure_currency(:XAB, name: "Sigil Private")

      assert sigil_M("100", ~c"XAB") == Money.new(:XAB, "100")
    end

    test "raises a runtime-registration hint for an unregistered private currency" do
      # The currency store is running during tests, so the message points at
      # runtime registration rather than the compile-time case.
      assert_raise Money.UnknownCurrencyError,
                   ~r/private or custom currency but is not registered/,
                   fn -> sigil_M("100", ~c"XQQ") end
    end

    test "raises the default error for an unknown ISO-shaped code" do
      # Not custom/private-shaped, so the default message is used unchanged
      # (no private-currency hint).
      assert_raise Money.UnknownCurrencyError, ~r/is not known/i, fn ->
        sigil_M("100", ~c"ZZZ")
      end
    end
  end

  describe "unknown_currency_message/3" do
    test "returns the default reason for a non custom/private code" do
      assert Money.Sigil.unknown_currency_message("ZZZ", "the default reason", true) ==
               "the default reason"

      assert Money.Sigil.unknown_currency_message("ZZZ", "the default reason", false) ==
               "the default reason"
    end

    test "hints at runtime registration when the store is running" do
      message = Money.Sigil.unknown_currency_message("XSC", "ignored", true)

      assert message =~ "private or custom currency but is not registered"
      assert message =~ ":custom_currencies"
      assert message =~ "Money.Currency.new/2"
    end

    test "explains the compile-time limitation when the store is not running" do
      message = Money.Sigil.unknown_currency_message("XSC", "ignored", false)

      assert message =~ "compile-time position"
      assert message =~ "module attribute"
      assert message =~ ":custom_currencies"
    end
  end
end
