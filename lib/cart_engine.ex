defmodule CartEngine do
  @moduledoc """
  Main public orchestration interface for the distributed Dynamic Cart Valuation Engine.
  """

  @spec get_local_registry() :: reference()
  def get_local_registry() do
    Application.get_env(:cart_engine, :registry_resource)
  end

  @doc """
  End-to-end evaluation of a local cart: takes a raw list of rules, compiles it locally, and evaluates.
  """
  @spec evaluate_local(String.t(), list({String.t(), integer(), integer()})) :: float()
  def evaluate_local(cart_id, raw_rules) do
    compiled_rules = CartEngine.RustBridge.compile_rules(raw_rules)
    CartEngine.RustBridge.evaluate_shared_cart(get_local_registry(), cart_id, compiled_rules)
  end

  @spec evaluate(list({String.t(), integer(), float()}), reference()) :: float()
  def evaluate(cart, rules_resource) do
    CartEngine.RustBridge.evaluate_cart(cart, rules_resource)
  end

  @spec evaluate_combinatorial(list({String.t(), integer(), float()}), reference()) :: float()
  def evaluate_combinatorial(cart, rules_resource) do
    CartEngine.RustBridge.evaluate_combinatorial_cart(cart, rules_resource)
  end
end
