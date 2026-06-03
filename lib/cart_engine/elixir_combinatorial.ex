defmodule CartEngine.ElixirCombinatorial do
  @moduledoc """
  Pure recursive Elixir implementation for finding the optimal discount combination.
  """

  @spec evaluate(
          list({String.t(), integer(), float()}),
          list({integer(), String.t(), integer(), integer(), list(integer())})
        ) :: float()
  def evaluate(cart, rules) do
    # Filter rules applicable to the cart items
    applicable_rules =
      Enum.filter(rules, fn {_, item_id, _, min_qty, _} ->
        Enum.any?(cart, fn {c_id, qty, _} -> c_id == item_id and qty >= min_qty end)
      end)

    find_min_cost(0, [], applicable_rules, cart, 999_999_999.0)
  end

  defp find_min_cost(step, selected_rules, applicable_rules, cart, current_best) do
    if step == length(applicable_rules) do
      cost = calculate_cost(cart, selected_rules)
      min(cost, current_best)
    else
      rule = Enum.at(applicable_rules, step)
      {rule_id, _, _, _, conflicting_rules} = rule

      # Check for conflicts with selected rules
      has_conflict =
        Enum.any?(selected_rules, fn {s_id, _, _, _, s_conflicts} ->
          s_id in conflicting_rules or rule_id in s_conflicts
        end)

      # Compute the best cost using the current rule if no conflicts exist
      best_with_rule =
        if has_conflict do
          current_best
        else
          find_min_cost(step + 1, [rule | selected_rules], applicable_rules, cart, current_best)
        end

      find_min_cost(step + 1, selected_rules, applicable_rules, cart, best_with_rule)
    end
  end

  defp calculate_cost(cart, rules) do
    Enum.reduce(cart, 0.0, fn {item_id, qty, price}, total ->
      rule = Enum.find(rules, fn {_, r_id, _, _, _} -> r_id == item_id end)

      item_total =
        if rule do
          {_, _, discount_pct, _, _} = rule
          discount = discount_pct / 100.0
          price * (1.0 - discount) * qty
        else
          price * qty
        end

      total + item_total
    end)
  end
end
