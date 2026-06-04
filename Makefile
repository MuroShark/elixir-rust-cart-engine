# Makefile for CartEngine orchestration

.PHONY: setup compile test lint format ci help

# Default target
help:
	@echo "Available commands:"
	@echo "  make setup     - Install Elixir dependencies"
	@echo "  make compile   - Compile Elixir application and Rust NIF"
	@echo "  make test      - Run Elixir and Rust unit tests"
	@echo "  make lint      - Perform static analysis (Credo and Clippy)"
	@echo "  make format    - Format Elixir and Rust source code"
	@echo "  make ci        - Run full CI pipeline (format, lint, and test checks)"

setup:
	mix deps.get

compile:
	mix compile

test:
	mix test
	cd native && cargo test

lint:
	mix credo --strict
	cd native && cargo clippy --all-targets -- -D warnings

format:
	mix format
	cd native && cargo fmt

# Target for Continuous Integration (CI) pipeline
ci:
	mix format --check-formatted
	cd native && cargo fmt --all -- --check
	mix credo --strict
	cd native && cargo clippy --all-targets -- -D warnings
	mix test
	cd native && cargo test
