defmodule CartEngineTest do
  use ExUnit.Case

  alias CartEngine.ElixirCombinatorial
  alias CartEngine.ElixirValuation
  alias CartEngine.RustBridge

  setup do
    rules = [
      {"sku_102", 15, 2},
      {"sku_509", 10, 5}
    ]

    rules_resource = RustBridge.compile_rules(rules)

    combinatorial_rules = [
      {1, "sku_102", 10, 2, [2]},
      {2, "sku_102", 20, 2, [1]}
    ]

    comb_resource = RustBridge.compile_combinatorial_rules(combinatorial_rules)

    registry_resource = RustBridge.create_registry()

    {:ok,
     rules: rules,
     rules_resource: rules_resource,
     comb_rules: combinatorial_rules,
     comb_resource: comb_resource,
     registry_resource: registry_resource}
  end

  test "correctly evaluates standard prices without active discounts", %{
    rules_resource: resource,
    rules: raw_rules
  } do
    cart = [
      {"sku_102", 1, 150.0},
      {"sku_509", 2, 100.0}
    ]

    expected = 1 * 150.0 + 2 * 100.0

    assert expected == RustBridge.evaluate_cart(cart, resource)
    assert expected == ElixirValuation.evaluate(cart, raw_rules)
  end

  test "correctly applies discounts when quantities meet requirements", %{
    rules_resource: resource,
    rules: raw_rules
  } do
    cart = [
      {"sku_102", 2, 150.0},
      {"sku_509", 5, 100.0}
    ]

    expected = 2 * 150.0 * 0.85 + 5 * 100.0 * 0.90

    assert expected == RustBridge.evaluate_cart(cart, resource)
    assert expected == ElixirValuation.evaluate(cart, raw_rules)
  end

  test "combinatorial search chooses the best discount and avoids conflicts", %{
    comb_resource: resource,
    comb_rules: raw_rules
  } do
    cart = [
      {"sku_102", 2, 100.0}
    ]

    expected = 2 * 100.0 * 0.80

    assert expected == RustBridge.evaluate_combinatorial_cart(cart, resource)
    assert expected == ElixirCombinatorial.evaluate(cart, raw_rules)
  end

  test "shared cart registry successfully updates and evaluates bypass reads", %{
    registry_resource: registry,
    rules_resource: rules
  } do
    cart_id = "test_cart_1"

    cart = [
      {"sku_102", 2, 150.0},
      {"sku_509", 5, 100.0}
    ]

    assert true == RustBridge.update_cart(registry, cart_id, cart)

    expected = 2 * 150.0 * 0.85 + 5 * 100.0 * 0.90
    assert expected == RustBridge.evaluate_shared_cart(registry, cart_id, rules)
  end

  test "CartServer syncs state and handles mailbox calculations and bypasses", %{
    registry_resource: registry,
    rules_resource: rules
  } do
    cart_id = "test_cart_server_9"

    {:ok, pid} = CartEngine.CartServer.start_link({cart_id, registry})
    assert is_pid(pid)

    cart = [
      {"sku_102", 2, 150.0},
      {"sku_509", 5, 100.0}
    ]

    assert :ok == CartEngine.CartServer.update_cart(cart_id, cart)

    expected = 2 * 150.0 * 0.85 + 5 * 100.0 * 0.90

    assert expected == GenServer.call(pid, {:calculate_cost, rules})
    assert expected == RustBridge.evaluate_shared_cart(registry, cart_id, rules)
  end

  test "DistributedRouter successfully starts, updates, and evaluates using raw rules", %{
    rules: raw_rules
  } do
    cart_id = "test_router_cart"

    assert :ok == CartEngine.DistributedRouter.start_cart(cart_id)

    cart = [
      {"sku_102", 2, 150.0},
      {"sku_509", 5, 100.0}
    ]

    assert :ok == CartEngine.DistributedRouter.update_cart(cart_id, cart)

    expected = 2 * 150.0 * 0.85 + 5 * 100.0 * 0.90
    assert expected == CartEngine.DistributedRouter.evaluate_cart(cart_id, raw_rules)
  end
end
