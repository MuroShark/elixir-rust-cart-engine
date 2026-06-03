defmodule CartEngine.ElixirValuation do
  @moduledoc """
  Pure Elixir implementation for result validation and tuple-based performance benchmarks.
  """

  @spec evaluate(list({String.t(), integer(), float()}), list({String.t(), integer(), integer()})) ::
          float()
  def evaluate(cart, rules) do
    Enum.reduce(cart, 0.0, fn {item_id, qty, price}, total ->
      rule = Enum.find(rules, fn {r_id, _, _} -> r_id == item_id end)

      item_total =
        if rule do
          {_, discount_pct, min_qty} = rule

          if qty >= min_qty do
            discount = discount_pct / 100.0
            price * (1.0 - discount) * qty
          else
            price * qty
          end
        else
          price * qty
        end

      total + item_total
    end)
  end
end
