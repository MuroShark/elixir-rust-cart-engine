# Makefile в корне проекта
.PHONY: setup compile test lint format ci help

# Команда по умолчанию
help:
	@echo "Доступные команды:"
	@echo "  make setup     - Установка зависимостей Elixir"
	@echo "  make compile   - Компиляция Elixir-приложения и Rust NIF"
	@echo "  make test      - Запуск тестов для Elixir и Rust"
	@echo "  make lint      - Статический анализ кода (Credo и Clippy)"
	@echo "  make format    - Форматирование кода (Elixir и Rust)"
	@echo "  make ci        - Полный цикл проверок (форматирование, линтинг, тесты)"

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

# Цель для CI-пайплайна (строгие проверки с падением при любой ошибке)
ci:
	mix format --check-formatted
	cd native && cargo fmt --all -- --check
	mix credo --strict
	cd native && cargo clippy --all-targets -- -D warnings
	mix test
	cd native && cargo test
