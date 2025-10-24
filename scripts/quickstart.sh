#!/bin/bash

# Quick start script for HR CDC Pipeline
set -e

# Get the project root directory (parent of scripts directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║  HR Event Publisher - CDC Pipeline     ║"
echo "║  Quick Start Script                    ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Step 1: Start services
echo -e "${YELLOW}Step 1: Starting Docker services...${NC}"
cd "$PROJECT_ROOT"
docker-compose up -d

echo ""
echo -e "${YELLOW}Waiting for services to be healthy (30 seconds)...${NC}"
sleep 30

# Step 2: Check service health
echo ""
echo -e "${YELLOW}Step 2: Checking service health...${NC}"

echo -n "  MariaDB: "
if docker exec hr-mariadb mysql -uroot -prootpass -e "SELECT 1" &>/dev/null; then
    echo -e "${GREEN}✓ Healthy${NC}"
else
    echo -e "✗ Not ready"
    exit 1
fi

echo -n "  NATS: "
if curl -s http://localhost:8222/healthz &>/dev/null; then
    echo -e "${GREEN}✓ Healthy${NC}"
else
    echo -e "✗ Not ready"
    exit 1
fi

echo -n "  Debezium: "
if docker ps | grep -q hr-debezium; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "✗ Not running"
    exit 1
fi

# Step 3: Configure NATS stream
echo ""
echo -e "${YELLOW}Step 3: Configuring NATS stream...${NC}"
docker run --rm \
  --network bizeventhub-p2_hr-network \
  -v "$PROJECT_ROOT/config/nats:/config" \
  natsio/nats-box:latest \
  nats stream add --config /config/stream.json --server nats://hr-nats:4222
echo -e "${GREEN}✓ NATS stream configured${NC}"

# Step 4: Initialize database
echo ""
echo -e "${YELLOW}Step 4: Initializing HR database schema...${NC}"
docker exec -i hr-mariadb mysql -uroot -prootpass hrdb < "$PROJECT_ROOT/sql/init-db.sql"
echo -e "${GREEN}✓ Database initialized with sample data${NC}"

# Step 5: Verify binlog
echo ""
echo -e "${YELLOW}Step 5: Verifying binlog configuration...${NC}"
BINLOG_STATUS=$(docker exec hr-mariadb mysql -uroot -prootpass -sN -e "SHOW VARIABLES LIKE 'log_bin';" | awk '{print $2}')
if [ "$BINLOG_STATUS" == "ON" ]; then
    echo -e "${GREEN}✓ Binlog is enabled${NC}"
else
    echo -e "✗ Binlog is not enabled"
    exit 1
fi

# Step 6: Show access information
echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗"
echo "║  Setup Complete!                       ║"
echo "╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Services are running:${NC}"
echo ""
echo "  MariaDB:"
echo "    Host: localhost:3306"
echo "    Database: hrdb"
echo "    User: hruser / hrpass"
echo "    Root: root / rootpass"
echo ""
echo "  NATS:"
echo "    Client: localhost:4222"
echo "    Monitoring: http://localhost:8222"
echo ""
echo "  Debezium:"
echo "    CDC Events: cdc.hr.{tableName}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "  1. Test CDC pipeline:"
echo "     ./scripts/test-cdc.sh"
echo ""
echo "  2. Monitor CDC events (requires NATS CLI):"
echo "     nats sub 'HCM.CDC.HR.>'"
echo ""
echo "  3. View service logs:"
echo "     docker logs hr-debezium"
echo "     docker logs hr-mariadb"
echo "     docker logs hr-nats"
echo ""
echo "  4. Connect to MariaDB:"
echo "     docker exec -it hr-mariadb mysql -uhruser -phrpass hrdb"
echo ""
echo "  5. Check NATS JetStream:"
echo "     curl http://localhost:8222/jsz"
echo ""
echo -e "${GREEN}For more information, see docs/cdc-guide.md${NC}"
echo ""
