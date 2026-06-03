defmodule CartEngine.RustBridge do
  @moduledoc """
  Interface for calling compiled Rust valuation functions.
  """
  use Rustler, otp_app: :cart_engine, crate: "cart_engine_nif"

  # --- Standard Valuation ---
  @spec compile_rules(list({String.t(), integer(), integer()})) :: reference()
  def compile_rules(_rules), do: :erlang.nif_error(:nif_not_loaded)

  @spec evaluate_cart(list({String.t(), integer(), float()}), reference()) :: float()
  def evaluate_cart(_cart, _rules_resource), do: :erlang.nif_error(:nif_not_loaded)

  # --- Combinatorial Valuation (Scenario II) ---
  @spec compile_combinatorial_rules(
          list({integer(), String.t(), integer(), integer(), list(integer())})
        ) :: reference()
  def compile_combinatorial_rules(_rules), do: :erlang.nif_error(:nif_not_loaded)

  @spec evaluate_combinatorial_cart(list({String.t(), integer(), float()}), reference()) ::
          float()
  def evaluate_combinatorial_cart(_cart, _rules_resource), do: :erlang.nif_error(:nif_not_loaded)

  # --- Global Shared Cart Registry (Scenario III) ---
  @spec create_registry() :: reference()
  def create_registry(), do: :erlang.nif_error(:nif_not_loaded)

  @spec update_cart(reference(), String.t(), list({String.t(), integer(), float()})) :: boolean()
  def update_cart(_registry, _cart_id, _cart), do: :erlang.nif_error(:nif_not_loaded)

  @spec evaluate_shared_cart(reference(), String.t(), reference()) :: float()
  def evaluate_shared_cart(_registry, _cart_id, _rules_resource),
    do: :erlang.nif_error(:nif_not_loaded)
end
