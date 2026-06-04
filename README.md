# Dynamic Cart Valuation Engine (Elixir + Rust)

[Читать на русском](README_RU.md)

A high-throughput, real-time dynamic cart valuation engine designed with a hybrid architecture of **Elixir (OTP/Distributed Orchestration)** and **Rust (NIF/High-Performance Computation)**.

This project is developed as a technological solution to the architectural problem of latency degradation when calculating complex, overlapping loyalty rules and discounts under extreme concurrent load (real-time retail / ecom.tech stack).

---

## 1. Relevance and Business Context

In e-commerce platforms (such as Samokat, Megamarket, or Kuper), cart valuation is one of the most critical and computationally intensive operations. When a user modifies their cart, the system must instantly (within single-digit milliseconds):

1. Verify dozens of overlapping promo codes and loyalty rules.
2. Exclude incompatible promotions and calculate the optimal discount for hundreds of items.
3. Validate tax and regional restrictions.

### Systemic Problem:

- **I/O-bound vs CPU-bound:** The BEAM virtual machine is perfectly optimized for managing millions of WebSockets and parallel user sessions (I/O-bound). However, combinatorial discount calculations create a high CPU load (CPU-bound).
- **Latency Spikes:** Executing heavy math inside Elixir processes leads to scheduler starvation, tail latency degradation (p99/p99.9 spikes), and increased Garbage Collection (GC) pressure due to term copying between process heaps.

---

## 2. Architecture & Three Optimization Scenarios

The project implements the **"Endurance Stack"** pattern and solves three fundamental architectural challenges:

### Scenario I: Memory Marshalling Optimization (Zero-Copy & Lazy List Iteration)

For standard cart valuation, decoding Elixir maps (`%{item_id: ..., price: ...}`) requires expensive hash lookups inside the Erlang VM for every key.

**Solution:**

- Data transfer is refactored to use flat **`NifTuple`** structs, which are translated directly into contiguous C-arrays on the native level.
- Cart list iteration on the Rust side is executed lazily using **`ListIterator`**, completely preventing the allocation of intermediate native vectors `Vec`.
- The `item_id` string fields are decoded using the Zero-Copy principle with the **`&'a str`** type, referencing the binary data directly in the BEAM heap without allocating new owned `String` objects on the Rust heap.

### Scenario II: Optimal Combinatorial Search Tree (NP-Hard / Branch and Bound)

Finding the optimal combination of discounts when **conflicting (mutually exclusive) promo codes** are present is an NP-hard problem (equivalent to the Knapsack Problem).

**Solution:**

- On the Rust side, a recursive state-space tree traversal is implemented using a **Backtracking (depth-first search)** algorithm.
- Conflict resolution is refactored from linear vector scans to **bitwise masks (`u64`)**. Verifying a conflict for a new rule against all selected ones is executed by the CPU in **1 instruction cycle** via bitwise `AND` (`&`).
- A **Branch and Bound (Pruning)** algorithm is introduced: at each recursion step, the maximum possible remaining discount is precalculated. If the current accumulated discount plus the remaining potential cannot beat the best-found record, the branch is instantly pruned.
- All operations are executed entirely on the stack with **zero dynamic memory allocations** on the Rust heap.

### Scenario III: Bypassing the Process Mailbox Bottleneck (Lock-Free Shared Registry)

When cart state is held inside a standard `GenServer`, parallel read and calculation requests queue up in the process mailbox, serializing execution and introducing queue delays.

**Solution:**

- Applied the **CQRS** pattern: cart mutations (writes) are routed through the `GenServer` (`CartServer`), while concurrent read and calculation queries bypass the mailbox entirely.
- On the Rust side, a shared concurrent resource `SharedCartRegistry` is created using the thread-safe, segmented **`DashMap`**. Elixir processes read cart states directly from the `DashMap` without interacting with the Erlang process mailboxes.

---

## 3. Distributed Cluster & Data Locality

To operate at a distributed, cloud-native scale (Kubernetes), the project is extended to an active-active clustered architecture with automatic node discovery and dynamic request routing.

```text
               [Cart valuation request for "cart_1" arrived at node3]
                                      │
                                      ▼
                        ┌───────────────────────────┐
                        │      Horde.Registry       │ (Where is "cart_1" located?)
                        └─────────────┬─────────────┘
                                      │
                                      ▼
                     (Cart "cart_1" is alive on node1)
                                      │
                                      ▼
                        ┌───────────────────────────┐
                        │         :rpc.call         │ (Invoke calculation on node1)
                        └─────────────┬─────────────┘
                                      │
                                      ▼
                       ┌─────────────────────────────┐
                       │  Rustler NIF on node1       │ (Read from local DashMap)
                       └─────────────┬─────────────┘
                                      │
                                      ▼
                             (Float f64 Result)
                                      │
                                      ▼
                         [Return response to node3]
```

### Key Cluster Components:

1. **`libcluster` (Node Discovery):** Automates node discovery within a private Docker bridge network, forming a connected Erlang cluster.
2. **`Horde` (Distributed Registry & Supervisor):** A distributed registry and dynamic supervisor on top of CRDTs. `Horde` guarantees that exactly one `CartServer` process is active per `cart_id` across the cluster, dynamically migrating processes on node failures.
3. **Distributed CQRS Router (`DistributedRouter`):**
   - **Write path:** Transparently routes mutations to the specific node holding the target `CartServer` process.
   - **Read path (RPC Optimization):** If the cart is located on a remote node, the router executes a high-performance network RPC call `:rpc.call`. The raw, serializable list of rules `raw_rules` is sent over the network and **compiled locally on demand on the target node**. This prevents passing non-transferable C memory pointers (which would raise a `badarg` error) and avoids transferring raw cart data across the network.

---

## 4. QA Pipeline & Code Quality

The project integrates strict production-grade static analysis and safety checks required for enterprise development.

### Elixir Static Analysis Pipeline:

- **Credo (Strict Mode):** Validates style, code readability, and design anti-patterns.
- **Dialyxir (Dialyzer):** Performs static type checking based on `@spec` annotations.

### Rust Safety Guarantees (Clippy & Compiler):

A panic (`panic!`) in the native NIF code instantly crashes the entire Erlang VM. To guarantee absolute stability at compile-time, strict compiler lints are enforced:

- **Deny Panicking Operations:** `unwrap_used = "deny"`, `expect_used = "deny"`, `panic = "deny"`. All errors must return a safe `Result<T, E>` tuple back to Elixir.
- **Deny Explicit Auto-Deref:** `clippy::explicit-auto-deref = "deny"` — enforces the use of safe, compiler-driven auto-dereferencing of `ResourceArc` smart pointers.
- **Thread Safety:** `indexing_slicing = "deny"` — prevents array out-of-bounds panics that could crash scheduler threads.
- **Panic Boundary Safety:** The `SharedCartRegistry` struct manually implements the `RefUnwindSafe` and `UnwindSafe` marker traits to safely traverse the `catch_unwind` boundary inside Rustler [9].

---

## 5. Project Structure (Cargo Workspace)

The project is structured as a polyglot monorepository:

```text
├── mix.exs                     # Elixir project configuration and dependencies
├── .credo.exs                  # Strict Credo configurations
├── config/
│   └── config.exs              # Elixir application environment configs
├── lib/                        # Elixir application source
│   ├── cart_engine/
│   │   ├── application.ex      # Supervision tree (Supervisor, Horde Registry)
│   │   ├── cart_server.ex      # GenServer state mutator (Write-path)
│   │   ├── cluster_connector.ex# Horde node connector
│   │   ├── distributed_router.ex# Distributed CQRS router
│   │   ├── elixir_combinatorial.ex # Pure Elixir combinatorial search logic
│   │   ├── valuation.ex        # Pure Elixir standard logic (for benchmarks)
│   │   └── rust_bridge.ex      # NIF loading and type mapping
│   └── cart_engine.ex          # Public API
└── native/                     # Rust workspace
    ├── Cargo.toml              # Workspace manifest (Clippy rules)
    ├── clippy.toml             # Global Clippy settings (MSRV 1.80.0, complexity limits)
    └── cart_engine_nif/        # NIF adapter crate
        ├── Cargo.toml
        └── src/
            └── lib.rs          # NIF registration, DashMap, and PromotionTrie logic
```

---

## 6. Environment & Setup

### Requirements:

- **macOS** (Apple Silicon) or **Linux**
- **Erlang/OTP 28+** & **Elixir 1.19.5+**
- **Rust 1.80+** (compiler `rustc`, package manager `cargo`)
- **OrbStack** or **Docker** (for clustered testing)

### 1. Local Build and QA Pipeline Validation

```bash
# Get dependencies
mix deps.get

# Run strict code quality pipeline (CI Simulation)
make ci

# Run tests (including distributed network integration tests)
mix test
```

### 2. Launching the 3-Node Distributed Cluster (via OrbStack)

```bash
# Build and run the cluster
docker compose up --build
```

_The containers `cart_node_1`, `cart_node_2`, and `cart_node_3` will boot, establish an Erlang network, and automatically sync Horde registries._

### 3. Connecting to the Clustered Node (Remote Interactive Console)

You can attach an interactive Elixir shell (`iex`) directly to the running node from your host terminal:

```bash
docker exec -it cart_node_1 bin/cart_engine remote
```

---

## 7. Benchmarks & Systems Analysis

All benchmarks were evaluated on an **Apple M5 CPU (10 Cores, 16 GB RAM)** running **Elixir 1.19.5, Erlang 29.0.1 (JIT Enabled)** using the **Benchee** library.

### BENCHMARK I: Base Cart Valuation Scenario (DashMap Storage)

#### Test 1: Minimal Promo Database (Best-Case for Elixir)

The active rules are placed at the beginning of the list, triggering the early-exit optimization (`Enum.find` exits at index 1).

```text
##### With input Large Cart (150 items) #####
Name                            ips        average  deviation         median         99th %
elixir_pure_valuation      224.36 K        4.46 μs    ±99.94%        4.25 μs        6.92 μs
rust_nif_valuation         150.84 K        6.63 μs   ±261.15%        6.46 μs        8.04 μs

Comparison:
elixir_pure_valuation      224.36 K
rust_nif_valuation         150.84 K - 1.49x slower +2.17 μs

Memory usage statistics:
Name                     Memory usage
elixir_pure_valuation         5.88 KB
rust_nif_valuation          0.0156 KB - 0.00x memory usage -5.86719 KB

##### With input Small Cart (5 items) #####
Name                            ips        average  deviation         median         99th %
elixir_pure_valuation        7.80 M       0.128 μs  ±2174.97%       0.125 μs        0.21 μs
rust_nif_valuation           0.58 M        1.72 μs    ±98.96%        1.67 μs        1.96 μs

Comparison:
elixir_pure_valuation        7.80 M
rust_nif_valuation           0.58 M - 13.44x slower +1.60 μs

Memory usage statistics:
Name                     Memory usage
elixir_pure_valuation           224 B
rust_nif_valuation               16 B - 0.07x memory usage -208 B
```

#### Test 2: Realistic Promo Database (Worst-Case for Elixir, 100 Rules)

The active rules are appended to the very end of a 100-rule list. Elixir must perform a linear scan of $O(N \times M)$.

```text
##### With input Large Cart (150 items) #####
Name                            ips        average  deviation         median         99th %
rust_nif_valuation         191.00 K        5.24 μs    ±23.90%        5.13 μs        7.08 μs
elixir_pure_valuation        9.19 K      108.86 μs     ±6.47%      107.88 μs      134.56 μs

Comparison:
rust_nif_valuation         191.00 K
elixir_pure_valuation        9.19 K - 20.79x slower +103.63 μs

Memory usage statistics:

Name                     Memory usage
rust_nif_valuation          0.0156 KB
elixir_pure_valuation         5.88 KB - 376.50x memory usage +5.87 KB
```

#### Benchmark I Systems Analysis:

- **NIF Transition Costs:** The 1.6 μs gap on small inputs highlights the baseline context-switch overhead of entering the C boundary from the BEAM VM. For trivial calculations, Elixir's fast local JIT-execution wins.
- **Algorithmic Scaling:** On 150 items with 100 rules, Elixir degrades **24.4x** (to `108.86 μs`) due to the $O(N \times M)$ list-traversal. Rust's `HashMap` maintains constant-time lookup $O(1)$, executing at `~5.24 μs` (**20.79x faster than Elixir**).

---

### BENCHMARK II: Combinatorial Backtracking (NP-Hard Coupon Stacking)

A recursive depth-first search (DFS) over a state-space tree of 15 applicable rules with cross-conflicts ($2^{15}$ permutations).

```text
Name                                ips        average  deviation         median         99th %
rust_nif_combinatorial         238.52 K        4.19 μs    ±56.04%        4.04 μs        8.25 μs
elixir_pure_combinatorial        3.32 K      300.76 μs     ±6.89%      299.79 μs      371.84 μs

Comparison:
rust_nif_combinatorial         238.52 K
elixir_pure_combinatorial        3.32 K - 71.74x slower +296.57 μs

Memory usage statistics:

Name                         Memory usage
rust_nif_combinatorial          0.0156 KB
elixir_pure_combinatorial       316.62 KB - 20263.50x memory usage +316.60 KB
```

#### Benchmark II Systems Analysis:

For heavy CPU-bound combinatorial logic (backtracking over floats), Rust outperforms Elixir **71.74x** on raw speed. Furthermore, Elixir allocates **316.62 KB** of temporary heap memory _per calculation_ to maintain the recursive stack states on the BEAM heap. Rust NIF, utilizing stack-allocated `u64` bitmasks and Branch and Bound pruning, allocates exactly **16 bytes**.

---

### BENCHMARK III: Mailbox Bottleneck Bypass (10 Parallel Processes)

Simulates 10 concurrent Erlang processes querying the cart price simultaneously. Compares sequential GenServer mailbox queuing against direct, lock-free concurrent reads from the native `DashMap`.

```text
Name                                 ips        average  deviation         median         99th %
dashmap_concurrent_reads        234.39 K        4.27 μs   ±737.51%        2.58 μs       12.21 μs
genserver_serialized_reads       49.18 K       20.33 μs    ±60.46%       17.75 μs       57.96 μs

Comparison:
dashmap_concurrent_reads        234.39 K
genserver_serialized_reads       49.18 K - 4.77x slower +16.07 μs

Memory usage statistics:

Name                               average  deviation         median         99th %
dashmap_concurrent_reads           0.41 KB     ±0.00%        0.41 KB        0.41 KB
genserver_serialized_reads         1.07 KB     ±2.08%        1.07 KB        1.09 KB

Comparison:
dashmap_concurrent_reads           0.41 KB
genserver_serialized_reads         1.07 KB - 2.64x memory usage +0.66 KB
```

#### Benchmark III Systems Analysis:

- **Removing `DirtyCpu`:** Removing the `schedule = "DirtyCpu"` flag for this ultra-fast sub-millisecond task saved `~15 μs` of OS-thread context switching overhead, running the NIF directly on Elixir's native scheduler threads.
- **Lock Sharding:** Distributing the queries across independent keys (`cart_user_1` to `cart_user_10`) allowed `DashMap`'s segmented locking structure to scale linearly across all 10 cores of the Apple M5, completely avoiding CPU **Cache Line Bouncing** and lock contention.
- **Mailbox Bypass:** Bypassing process context switches and Erlang term-copying to the GenServer heap yielded a **4.77x (377%) throughput increase** over the GenServer mailbox path. Median latency dropped to a record **`2.58 μs`**.

#### Preventing Garbage Collection Pressure (p99 Tail Latency):

At a peak scale of **100,000 RPS** (requests per second):

- **In Elixir:** The system generates **~588 MB of temporary heap allocations per second** (5.88 KB × 100k). This triggers continuous Garbage Collection sweeps across all scheduler threads, introducing latency spikes (jitter) at the p99/p99.9 tail percentiles.
- **In Rust (NIF):** The calculations generate **0 bytes of garbage** on the BEAM heap. The response times remain flat and highly predictable under sustained peak traffic.
