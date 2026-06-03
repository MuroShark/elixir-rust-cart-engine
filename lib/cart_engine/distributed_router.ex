defmodule CartEngine.DistributedRouter do
  @moduledoc """
  Distributed router for the CQRS pattern.
  Routes writes to the GenServer owner node, and reads via native RPC.
  """

  @spec start_cart(String.t()) :: :ok | {:error, any()}
  def start_cart(cart_id) do
    child_spec = {CartEngine.CartServer, cart_id}

    case Horde.DynamicSupervisor.start_child(CartEngine.DistributedSupervisor, child_spec) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> error
    end
  end

  @spec update_cart(String.t(), list()) :: :ok | {:error, any()}
  def update_cart(cart_id, new_items) do
    case lookup_pid(cart_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:update, new_items})

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Concurrent cart valuation: accepts a raw list of rules to ensure network compatibility.
  """
  @spec evaluate_cart(String.t(), list({String.t(), integer(), integer()})) ::
          float() | {:error, any()}
  def evaluate_cart(cart_id, raw_rules) do
    case lookup_pid(cart_id) do
      {:ok, pid} ->
        target_node = node(pid)

        if target_node == Node.self() do
          CartEngine.evaluate_local(cart_id, raw_rules)
        else
          # Transmit raw_rules over the network, compilation happens locally on the target node
          :rpc.call(target_node, CartEngine, :evaluate_local, [cart_id, raw_rules])
        end

      {:error, _} = error ->
        error
    end
  end

  defp lookup_pid(cart_id) do
    case Horde.Registry.lookup(CartEngine.DistributedRegistry, cart_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
