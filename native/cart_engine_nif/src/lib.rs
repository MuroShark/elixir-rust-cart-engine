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

// Simplifies mapping from Item to OwnedItem via the From trait
impl<'a> From<&Item<'a>> for OwnedItem {
    fn from(item: &Item<'a>) -> Self {
        OwnedItem {
            item_id: item.item_id.to_string(),
            qty: item.qty,
            price: item.price,
        }
    }
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

// Holds a reference to the original rule instead of cloning it
struct ActiveRule<'a> {
    rule: &'a CombinatorialRule,
    discount_value: f64,
    conflict_mask: u64,
}

// =========================================================================
// HELPERS
// =========================================================================

// Unified helper to calculate discounted item price
fn calculate_item_price(qty: i32, price: f64, rule: Option<&Rule>) -> f64 {
    let discount_pct = rule
        .filter(|r| qty >= r.min_qty)
        .map(|r| r.discount_pct)
        .unwrap_or(0);
    let discount = f64::from(discount_pct) / 100.0;
    price * f64::from(qty) * (1.0 - discount)
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
    let owned_cart = cart.iter().map(OwnedItem::from).collect();
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
        for item in cart_ref.value() {
            let rule = rules_resource.rules.get(&item.item_id);
            total += calculate_item_price(item.qty, item.price, rule);
        }
    }
    Ok(total)
}

// =========================================================================
// NIF FUNCTIONS: SCENARIO I (STANDARD VALUATION)
// =========================================================================

#[rustler::nif]
fn compile_rules(rules: Vec<Rule>) -> ResourceArc<PromotionRules> {
    let rules = rules.into_iter().map(|r| (r.item_id.clone(), r)).collect();
    ResourceArc::new(PromotionRules { rules })
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
        let rule = resource.rules.get(item.item_id);
        total += calculate_item_price(item.qty, item.price, rule);
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
    let cart: Vec<Item<'a>> = list_iterator
        .map(|term| term.decode())
        .collect::<Result<_, _>>()?;

    // Find rules and calculate discount values in a single pass without cloning
    let mut active_rules = Vec::new();
    for rule in &resource.rules {
        if let Some(item) = cart
            .iter()
            .find(|item| item.item_id == rule.item_id && item.qty >= rule.min_qty)
        {
            let discount = f64::from(rule.discount_pct) / 100.0;
            let discount_value = item.price * discount * f64::from(item.qty);
            active_rules.push(ActiveRule {
                rule,
                discount_value,
                conflict_mask: 0,
            });
        }
    }

    // Construct conflict masks without redundant Option checks
    let n = active_rules.len();
    for i in 0..n {
        let mut mask = 0u64;
        let active_i = &active_rules[i];
        for (j, active_j) in active_rules.iter().enumerate() {
            if i != j
                && (active_i
                    .rule
                    .conflicting_rules
                    .contains(&active_j.rule.rule_id)
                    || active_i.rule.item_id == active_j.rule.item_id)
            {
                mask |= 1 << j;
            }
        }
        active_rules[i].conflict_mask = mask;
    }

    let mut remaining_discounts = vec![0.0; n + 1];
    let mut accum = 0.0;
    for i in (0..n).rev() {
        accum += active_rules[i].discount_value;
        remaining_discounts[i] = accum;
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
    active_rules: &[ActiveRule<'_>],
    remaining_discounts: &[f64],
    best_discount: &mut f64,
) {
    // Safe access without Option checks
    if current_discount + remaining_discounts[step] <= *best_discount {
        return;
    }

    if step == active_rules.len() {
        if current_discount > *best_discount {
            *best_discount = current_discount;
        }
        return;
    }

    let rule = &active_rules[step];
    if (selected_mask & rule.conflict_mask) == 0 {
        find_max_discount(
            step + 1,
            selected_mask | (1 << step),
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

rustler::init!("Elixir.CartEngine.RustBridge");
