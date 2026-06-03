defmodule CartEngine.ClusterConnector do
  @moduledoc """
  Background process tracking cluster topology and synchronizing Horde members.
  """
  use GenServer

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl GenServer
  def init(_) do
    :net_kernel.monitor_nodes(true)
    {:ok, nil, {:continue, :sync}}
  end

  @impl GenServer
  def handle_continue(:sync, state) do
    sync_hordes()
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:nodeup, _node}, state) do
    sync_hordes()
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:nodedown, _node}, state) do
    sync_hordes()
    {:noreply, state}
  end

  defp sync_hordes() do
    nodes = [Node.self() | Node.list()]

    Horde.Cluster.set_members(
      CartEngine.DistributedRegistry,
      Enum.map(nodes, &{CartEngine.DistributedRegistry, &1})
    )

    Horde.Cluster.set_members(
      CartEngine.DistributedSupervisor,
      Enum.map(nodes, &{CartEngine.DistributedSupervisor, &1})
    )
  end
end
