defmodule CombinatorialValuationBench do
  @moduledoc false

  def run do
    # Cart with 5 items
    cart = [
      {"sku_1", 5, 100.0},
      {"sku_2", 5, 200.0},
      {"sku_3", 5, 300.0},
      {"sku_4", 5, 400.0},
      {"sku_5", 5, 500.0}
    ]

    # Generate 15 applicable rules with cross-conflicts
    # Format: {rule_id, item_id, discount_pct, min_qty, conflicting_rules}
    raw_rules = [
      {1, "sku_1", 10, 2, [2, 3]},
      {2, "sku_1", 15, 3, [1, 3]},
      {3, "sku_1", 20, 5, [1, 2]},

      {4, "sku_2", 10, 2, [5, 6]},
      {5, "sku_2", 15, 3, [4, 6]},
      {6, "sku_2", 20, 5, [4, 5]},

      {7, "sku_3", 10, 2, [8, 9]},
      {8, "sku_3", 15, 3, [7, 9]},
      {9, "sku_3", 20, 5, [7, 8]},

      {10, "sku_4", 10, 2, [11, 12]},
      {11, "sku_4", 15, 3, [10, 12]},
      {12, "sku_4", 20, 5, [10, 11]},

      {13, "sku_5", 10, 2, [14, 15]},
      {14, "sku_5", 15, 3, [13, 15]},
      {15, "sku_5", 20, 5, [13, 14]}
    ]

    # Compile rules on the Rust side
    rules_resource = CartEngine.RustBridge.compile_combinatorial_rules(raw_rules)

    Benchee.run(
      %{
        "elixir_pure_combinatorial" => fn ->
          CartEngine.ElixirCombinatorial.evaluate(cart, raw_rules)
        end,
        "rust_nif_combinatorial" => fn ->
          CartEngine.RustBridge.evaluate_combinatorial_cart(cart, rules_resource)
        end
      },
      warmup: 2,
      time: 5,
      memory_time: 2,
      print: [fast_warning: false]
    )
  end
end

CombinatorialValuationBench.run()
