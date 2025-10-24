.PHONY: help start stop restart clean test logs status init

# Default target
help:
	@echo "HR Event Publisher - CDC Pipeline"
	@echo ""
	@echo "Available commands:"
	@echo "  make start      - Start all services with full initialization"
	@echo "  make stop       - Stop all services"
	@echo "  make restart    - Restart all services"
	@echo "  make clean      - Stop services and remove volumes"
	@echo "  make test       - Run CDC pipeline tests"
	@echo "  make logs       - Show logs from all services"
	@echo "  make status     - Check status of all services"
	@echo "  make init       - Initialize database and NATS stream only"
	@echo ""

# Start all services using quickstart script
start:
	@./scripts/quickstart.sh

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

# Run CDC tests
test:
	@./scripts/test-cdc.sh

# Show logs from all services
logs:
	@docker-compose logs -f

# Check service status
status:
	@echo "Service Status:"
	@echo ""
	@docker-compose ps

# Initialize database and NATS stream (when services are already running)
init:
	@echo "Initializing NATS stream..."
	@docker run --rm \
		--network bizeventhub-p2_hr-network \
		-v "$$(pwd)/config/nats:/config" \
		natsio/nats-box:latest \
		nats stream add --config /config/stream.json --server nats://hr-nats:4222
	@echo "Initializing database..."
	@docker exec -i hr-mariadb mysql -uroot -prootpass hrdb < sql/init-db.sql
	@echo "Initialization complete!"
