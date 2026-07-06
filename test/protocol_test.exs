defmodule Money.Protocol.Test do
  use ExUnit.Case

  test "Money with format options with String.Chars protocol" do
    assert to_string(Money.new!(:USD, 100, fractional_digits: 4)) == "$100.0000"
  end

  test "Subscription with String.Chars" do
    {:ok, plan} = Money.Subscription.Plan.new(Money.new(:USD, 10), :year)
    assert "$10.00 per year" = to_string(plan)
  end

  describe "Inspect protocol" do
    test "a plain money inspects as a Money.new/2 call" do
      assert inspect(Money.new(:USD, 100)) == ~s|Money.new(:USD, "100")|
    end

    test "a money with format options inspects as a Money.new/3 call including the options" do
      money = Money.new!(:USD, 100, fractional_digits: 4)
      result = inspect(money)

      assert result =~ "Money.new(:USD,"
      assert result =~ "fractional_digits: 4"
    end

    if Code.ensure_loaded?(DigitalToken) do
      test "a digital token money inspects using the token short name, not the token id" do
        money = Money.new("BTC", "100")
        result = inspect(money)

        # The raw currency is an ISO 24165 token id; inspect resolves it to the
        # human-readable short name.
        refute result =~ money.currency
        assert result =~ "Money.new("
        assert result =~ "100"
      end

      test "a token-shaped currency unknown to DigitalToken inspects with the raw token id" do
        # 9-byte binaries are treated as digital token ids; an id that
        # DigitalToken cannot resolve falls back to the id itself.
        money = %Money{currency: "ZZZZZZZZZ", amount: Decimal.new(1), format_options: []}

        assert inspect(money) == ~s|Money.new("ZZZZZZZZZ", "1")|
      end
    end
  end
end
