defmodule MailboxBottleneckBench do
  @moduledoc false

  def run do
    # Create a native lock-free DashMap registry
    registry_resource = CartEngine.RustBridge.create_registry()

    # Populate the cart (150 items)
    large_cart = List.duplicate({"sku_509", 10, 89.90}, 150)

    # Start 10 independent cart servers for each parallel worker
    Enum.each(1..10, fn i ->
      cart_id = "cart_user_#{i}"
      {:ok, _pid} = CartEngine.CartServer.start_link({cart_id, registry_resource})
      CartEngine.CartServer.update_cart(cart_id, large_cart)
    end)

    # Compile rules on the Rust side
    raw_rules = [
      {"sku_102", 15, 2},
      {"sku_509", 10, 5}
    ]

    rules_resource = CartEngine.RustBridge.compile_rules(raw_rules)

    Benchee.run(
      %{
        "genserver_serialized_reads" => fn ->
          # Simulate a concurrent storm: randomly hit one of the 10 GenServer mailboxes
          i = :rand.uniform(10)
          cart_id = "cart_user_#{i}"
          GenServer.call({:via, Horde.Registry, {CartEngine.DistributedRegistry, cart_id}}, {:calculate_cost, rules_resource})
        end,
        "dashmap_concurrent_reads" => fn ->
          # Bypass mailbox completely: parallel read from DashMap directly without locks
          i = :rand.uniform(10)
          cart_id = "cart_user_#{i}"
          CartEngine.RustBridge.evaluate_shared_cart(registry_resource, cart_id, rules_resource)
        end
      },
      warmup: 2,
      time: 5,
      memory_time: 2,
      parallel: 10, # Start parallel Erlang processes to create concurrency
      print: [fast_warning: false]
    )
  end
end

MailboxBottleneckBench.run()
