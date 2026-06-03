defmodule CartValuationBench do
  @moduledoc false

  def run do
    # Use fast tuples in all input arguments
    small_cart = List.duplicate({"sku_102", 2, 150.0}, 5)
    large_cart = List.duplicate({"sku_509", 10, 89.90}, 150)

    # Place fake rules at the beginning, and active ones at the very end
    fake_rules = Enum.map(1..100, fn i -> {"sku_fake_#{i}", 5, 2} end)

    raw_rules = fake_rules ++ [
      {"sku_102", 15, 2},
      {"sku_509", 10, 5}
    ]

    rules_resource = CartEngine.RustBridge.compile_rules(raw_rules)

    Benchee.run(
      %{
        "elixir_pure_valuation" => fn cart ->
          CartEngine.ElixirValuation.evaluate(cart, raw_rules)
        end,
        "rust_nif_valuation" => fn cart ->
          CartEngine.RustBridge.evaluate_cart(cart, rules_resource)
        end
      },
      warmup: 2,
      time: 5,
      memory_time: 2,
      inputs: %{
        "Small Cart (5 items)" => small_cart,
        "Large Cart (150 items)" => large_cart
      }
    )
  end
end

CartValuationBench.run()
