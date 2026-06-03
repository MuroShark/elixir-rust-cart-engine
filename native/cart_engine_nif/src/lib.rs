// native/cart_engine_nif/src/lib.rs
use dashmap::DashMap;
use rustler::{Error, ListIterator, NifTuple, Resource, ResourceArc, Term};
use std::collections::HashMap;

// =========================================================================
// SCENARIO I: BASE VALUATION STRUCTURES
// =========================================================================

#[derive(NifTuple, Clone)]
struct Item<'a> {
    item_id: &'a str,
    qty: i32,
    price: f64,
}

#[derive(Clone)]
struct OwnedItem {
    item_id: String,
    qty: i32,
    price: f64,
}

#[derive(NifTuple, Clone)]
struct Rule {
    item_id: String,
    discount_pct: i32,
    min_qty: i32,
}

struct PromotionRules {
    rules: HashMap<String, Rule>,
}

#[rustler::resource_impl]
impl Resource for PromotionRules {}

// =========================================================================
// SCENARIO III: SHARED CART REGISTRY STRUCTURES
// =========================================================================

struct SharedCartRegistry {
    carts: DashMap<String, Vec<OwnedItem>>,
}

#[rustler::resource_impl]
impl Resource for SharedCartRegistry {}

// Manual implementation of safety marker traits to cross the catch_unwind boundary in Rustler [9]
impl std::panic::RefUnwindSafe for SharedCartRegistry {}
impl std::panic::UnwindSafe for SharedCartRegistry {}

// =========================================================================
// SCENARIO II: COMBINATORIAL SEARCH STRUCTURES
// =========================================================================

#[derive(NifTuple, Clone)]
struct CombinatorialRule {
    rule_id: i32,
    item_id: String,
    discount_pct: i32,
    min_qty: i32,
    conflicting_rules: Vec<i32>,
}

struct CombinatorialRules {
    rules: Vec<CombinatorialRule>,
}

#[rustler::resource_impl]
impl Resource for CombinatorialRules {}

struct ActiveRule {
    rule_id: i32,
    discount_value: f64,
    conflict_mask: u64,
}

// =========================================================================
// NIF FUNCTIONS: SCENARIO III (SHARED REGISTRY)
// =========================================================================

#[rustler::nif]
fn create_registry() -> ResourceArc<SharedCartRegistry> {
    ResourceArc::new(SharedCartRegistry {
        carts: DashMap::new(),
    })
}

#[rustler::nif]
fn update_cart<'a>(
    resource: ResourceArc<SharedCartRegistry>,
    cart_id: String,
    cart: Vec<Item<'a>>,
) -> Result<bool, Error> {
    let owned_cart: Vec<OwnedItem> = cart
        .iter()
        .map(|item| OwnedItem {
            item_id: item.item_id.to_string(),
            qty: item.qty,
            price: item.price,
        })
        .collect();

    resource.carts.insert(cart_id, owned_cart);
    Ok(true)
}

#[rustler::nif]
fn evaluate_shared_cart(
    registry: ResourceArc<SharedCartRegistry>,
    cart_id: String,
    rules_resource: ResourceArc<PromotionRules>,
) -> Result<f64, Error> {
    let mut total = 0.0;

    if let Some(cart_ref) = registry.carts.get(&cart_id) {
        let cart = cart_ref.value();

        for item in cart {
            let matched_rule = rules_resource.rules.get(&item.item_id);

            if let Some(rule) = matched_rule {
                if item.qty >= rule.min_qty {
                    let discount = f64::from(rule.discount_pct) / 100.0;
                    let discounted_price = item.price * (1.0 - discount);
                    total += discounted_price * f64::from(item.qty);
                } else {
                    total += item.price * f64::from(item.qty);
                }
            } else {
                total += item.price * f64::from(item.qty);
            }
        }
    }

    Ok(total)
}

// =========================================================================
// NIF FUNCTIONS: SCENARIO I (STANDARD VALUATION)
// =========================================================================

#[rustler::nif]
fn compile_rules(rules: Vec<Rule>) -> ResourceArc<PromotionRules> {
    let mut rules_map = HashMap::with_capacity(rules.len());
    for rule in rules {
        rules_map.insert(rule.item_id.clone(), rule);
    }
    ResourceArc::new(PromotionRules { rules: rules_map })
}

#[rustler::nif]
fn evaluate_cart<'a>(
    cart_term: Term<'a>,
    resource: ResourceArc<PromotionRules>,
) -> Result<f64, Error> {
    let mut total = 0.0;
    let list_iterator = cart_term.decode::<ListIterator<'a>>()?;

    for term in list_iterator {
        let item = term.decode::<Item<'a>>()?;
        let matched_rule = resource.rules.get(item.item_id);

        if let Some(rule) = matched_rule {
            if item.qty >= rule.min_qty {
                let discount = f64::from(rule.discount_pct) / 100.0;
                let discounted_price = item.price * (1.0 - discount);
                total += discounted_price * f64::from(item.qty);
            } else {
                total += item.price * f64::from(item.qty);
            }
        } else {
            total += item.price * f64::from(item.qty);
        }
    }

    Ok(total)
}

// =========================================================================
// NIF FUNCTIONS: SCENARIO II (ULTRA-OPTIMIZED COMBINATORIAL)
// =========================================================================

#[rustler::nif]
fn compile_combinatorial_rules(rules: Vec<CombinatorialRule>) -> ResourceArc<CombinatorialRules> {
    ResourceArc::new(CombinatorialRules { rules })
}

#[rustler::nif(schedule = "DirtyCpu")]
fn evaluate_combinatorial_cart<'a>(
    cart_term: Term<'a>,
    resource: ResourceArc<CombinatorialRules>,
) -> Result<f64, Error> {
    let list_iterator = cart_term.decode::<ListIterator<'a>>()?;
    let mut cart = Vec::new();
    for term in list_iterator {
        cart.push(term.decode::<Item<'a>>()?);
    }

    let mut applicable_rules = Vec::new();
    for rule in &resource.rules {
        let applies = cart
            .iter()
            .any(|item| item.item_id == rule.item_id && item.qty >= rule.min_qty);
        if applies {
            applicable_rules.push(rule.clone());
        }
    }

    let mut active_rules = Vec::with_capacity(applicable_rules.len());
    for rule in &applicable_rules {
        let matched_item = cart.iter().find(|item| item.item_id == rule.item_id);
        if let Some(item) = matched_item {
            let discount = f64::from(rule.discount_pct) / 100.0;
            let discount_value = item.price * discount * f64::from(item.qty);
            active_rules.push(ActiveRule {
                rule_id: rule.rule_id,
                discount_value,
                conflict_mask: 0,
            });
        }
    }

    let n = active_rules.len();
    for i in 0..n {
        let mut mask = 0u64;
        if let Some(orig_rule) = applicable_rules.get(i) {
            for j in 0..n {
                if i != j {
                    if let (Some(other_active), Some(other_orig)) =
                        (active_rules.get(j), applicable_rules.get(j))
                    {
                        if orig_rule.conflicting_rules.contains(&other_active.rule_id)
                            || orig_rule.item_id == other_orig.item_id
                        {
                            mask |= 1 << j;
                        }
                    }
                }
            }
        }
        if let Some(active) = active_rules.get_mut(i) {
            active.conflict_mask = mask;
        }
    }

    let mut remaining_discounts = vec![0.0; n + 1];
    let mut accum = 0.0;
    for i in (0..n).rev() {
        if let Some(active) = active_rules.get(i) {
            accum += active.discount_value;
        }
        if let Some(val) = remaining_discounts.get_mut(i) {
            *val = accum;
        }
    }

    let mut best_discount = 0.0;
    find_max_discount(
        0,
        0,
        0.0,
        &active_rules,
        &remaining_discounts,
        &mut best_discount,
    );

    let base_cost: f64 = cart
        .iter()
        .map(|item| item.price * f64::from(item.qty))
        .sum();
    Ok(base_cost - best_discount)
}

fn find_max_discount(
    step: usize,
    selected_mask: u64,
    current_discount: f64,
    active_rules: &[ActiveRule],
    remaining_discounts: &[f64],
    best_discount: &mut f64,
) {
    if let (Some(&rem_val), Some(best_val)) = (remaining_discounts.get(step), Some(*best_discount))
    {
        if current_discount + rem_val <= best_val {
            return;
        }
    }

    if step == active_rules.len() {
        if current_discount > *best_discount {
            *best_discount = current_discount;
        }
        return;
    }

    if let Some(rule) = active_rules.get(step) {
        let has_conflict = (selected_mask & rule.conflict_mask) != 0;

        if !has_conflict {
            let next_mask = selected_mask | (1 << step);
            find_max_discount(
                step + 1,
                next_mask,
                current_discount + rule.discount_value,
                active_rules,
                remaining_discounts,
                best_discount,
            );
        }

        find_max_discount(
            step + 1,
            selected_mask,
            current_discount,
            active_rules,
            remaining_discounts,
            best_discount,
        );
    }
}

rustler::init!("Elixir.CartEngine.RustBridge");
