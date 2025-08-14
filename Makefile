SHELL := /usr/bin/bash

COMPOSE_FILE := docker-compose.yaml
ELECTRIC_SHAPE_URL ?= http://localhost:3000/v1/shape

.PHONY: compose up down logs wait sql-init seed test-integration itest

up:
	@docker compose -f $(COMPOSE_FILE) up -d --wait

down:
	@docker compose -f $(COMPOSE_FILE) down -v

logs:
	@docker compose -f $(COMPOSE_FILE) logs -f | cat

sql-init:
	@echo "Initializing database schema..."
	@docker compose -f $(COMPOSE_FILE) exec -T postgres psql -U postgres -d postgres -c "CREATE TABLE IF NOT EXISTS widgets (id SERIAL PRIMARY KEY, name TEXT NOT NULL, priority INT NOT NULL DEFAULT 10);"
	@docker compose -f $(COMPOSE_FILE) exec -T postgres psql -U postgres -d postgres -c "ALTER TABLE widgets ADD COLUMN IF NOT EXISTS priority INT NOT NULL DEFAULT 10;"

seed:
	@echo "Seeding initial data..."
	@docker compose -f $(COMPOSE_FILE) exec -T postgres psql -U postgres -d postgres -c "INSERT INTO widgets (name) VALUES ('alpha') ON CONFLICT DO NOTHING;"

itest:
	@echo "Running integration tests..."
	@ELECTRIC_SHAPE_URL=$(ELECTRIC_SHAPE_URL) flutter test -r expanded test/integration | cat

test-integration: up sql-init seed itest
	@echo "Integration tests finished."


