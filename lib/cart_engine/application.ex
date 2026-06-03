defmodule CartEngine.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Initialize the native DashMap store for this node
    registry_resource = CartEngine.RustBridge.create_registry()
    Application.put_env(:cart_engine, :registry_resource, registry_resource)

    # Idiomatic environment parsing using a classic case block
    hosts =
      case System.get_env("CLUSTER_HOSTS") do
        nil ->
          [:"node1@127.0.0.1", :"node2@127.0.0.1", :"node3@127.0.0.1"]

        hosts_str ->
          hosts_str
          |> String.split(",")
          |> Enum.map(&String.to_atom/1)
      end

    topologies = [
      cart_cluster: [
        strategy: Cluster.Strategy.Epmd,
        config: [hosts: hosts]
      ]
    ]

    children = [
      {Cluster.Supervisor, [topologies, [name: CartEngine.ClusterSupervisor]]},
      {Horde.Registry, [name: CartEngine.DistributedRegistry, keys: :unique]},
      {Horde.DynamicSupervisor, [name: CartEngine.DistributedSupervisor, strategy: :one_for_one]},
      CartEngine.ClusterConnector
    ]

    opts = [strategy: :one_for_one, name: CartEngine.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
