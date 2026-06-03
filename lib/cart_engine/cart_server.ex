defmodule CartEngine.CartServer do
  @moduledoc """
  Mutator process (GenServer) managing cart state writes
  and synchronizing native data to DashMap.
  """
  use GenServer
  alias CartEngine.RustBridge

  # --- PUBLIC API ---

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(args) do
    # Extract cart ID depending on the arguments provided
    cart_id =
      case args do
        {id, _} -> id
        id -> id
      end

    GenServer.start_link(__MODULE__, args, name: via_tuple(cart_id))
  end

  @spec update_cart(String.t(), list({String.t(), integer(), float()})) :: :ok
  def update_cart(cart_id, new_items) do
    GenServer.call(via_tuple(cart_id), {:update, new_items})
  end

  # Use distributed registry Horde.Registry
  defp via_tuple(cart_id) do
    {:via, Horde.Registry, {CartEngine.DistributedRegistry, cart_id}}
  end

  # --- GENSERVER CALLBACKS ---

  # Support for local initialization (e.g., for mix test)
  @impl GenServer
  def init({cart_id, registry_resource}) do
    RustBridge.update_cart(registry_resource, cart_id, [])
    {:ok, %{cart_id: cart_id, registry: registry_resource, items: []}}
  end

  # Support for distributed initialization (for cluster usage without passing references over the network)
  def init(cart_id) when is_binary(cart_id) do
    registry_resource = CartEngine.get_local_registry()
    RustBridge.update_cart(registry_resource, cart_id, [])
    {:ok, %{cart_id: cart_id, registry: registry_resource, items: []}}
  end

  @impl GenServer
  def handle_call({:update, new_items}, _from, state) do
    # Synchronize native state on the local node
    RustBridge.update_cart(state.registry, state.cart_id, new_items)
    {:reply, :ok, %{state | items: new_items}}
  end

  @impl GenServer
  def handle_call({:calculate_cost, rules_resource}, _from, state) do
    cost = RustBridge.evaluate_shared_cart(state.registry, state.cart_id, rules_resource)
    {:reply, cost, state}
  end
end
