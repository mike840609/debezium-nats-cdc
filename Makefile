.PHONY: help start stop restart clean test logs status build

# Default target
help:
	@echo "HR CDC Service - Simple Change Data Capture"
	@echo ""
	@echo "Available commands:"
	@echo "  make start      - Build and start all services"
	@echo "  make stop       - Stop all services"
	@echo "  make restart    - Restart all services"
	@echo "  make clean      - Stop services and remove volumes"
	@echo "  make test       - Run CDC pipeline tests"
	@echo "  make logs       - Show logs from all services"
	@echo "  make logs-cdc   - Show logs from CDC service only"
	@echo "  make status     - Check status of all services"
	@echo "  make build      - Build the CDC service"
	@echo ""

# Build and start all services
start:
	@echo "Building and starting all services..."
	@docker-compose up -d --build
	@echo ""
	@echo "Services started! Waiting for health checks..."
	@sleep 10
	@echo ""
	@docker-compose ps
	@echo ""
	@echo "CDC Service endpoint: http://localhost:8080"
	@echo "Health check: curl http://localhost:8080/health"
	@echo ""
	@echo "View CDC logs: make logs-cdc"
	@echo "Run tests: make test"

# Stop all services
stop:
	@echo "Stopping all services..."
	@docker-compose down

# Restart all services
restart: stop start

# Clean up everything (including volumes)
clean:
	@echo "Stopping services and removing volumes..."
	@docker-compose down -v
	@echo "Cleanup complete!"

# Build the CDC service
build:
	@echo "Building CDC service..."
	@docker-compose build hr-cdc-service

# Run CDC tests
test:
	@echo "Running CDC pipeline tests..."
	@echo "Watch the CDC service logs in another terminal: make logs-cdc"
	@sleep 2
	@./scripts/test-cdc.sh

# Show logs from all services
logs:
	@docker-compose logs -f

# Show logs from CDC service only
logs-cdc:
	@docker-compose logs -f hr-cdc-service

# Check service status
status:
	@echo "Service Status:"
	@echo ""
	@docker-compose ps
