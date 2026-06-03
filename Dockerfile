# =========================
# Stage 1: Builder
# =========================
FROM elixir:1.19 AS builder

# Install C/C++ build tools and dependencies
RUN apt-get update && apt-get install -y curl build-essential git && \
    rm -rf /var/lib/apt/lists/*

# Install Rust toolchain for Rustler NIFs
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

# Install Elixir dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy application source code
COPY native native/
COPY lib lib/
COPY config config/

# Compile Elixir codebase and Rust NIFs
RUN mix compile

# Generate the OTP release
RUN mix release

# =========================
# Stage 2: Runner
# =========================
# Lightweight runtime ensuring GLIBC, OpenSSL, and NCURSES compatibility
FROM elixir:1.19-slim AS runner

WORKDIR /app

# Copy the compiled release from the builder stage
COPY --from=builder /app/_build/prod/rel/cart_engine ./

ENV MIX_ENV=prod

# Start the application node
CMD ["bin/cart_engine", "start"]
