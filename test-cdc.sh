#!/bin/bash

# CDC Pipeline Test Script
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║  HR Event Publisher - CDC Test         ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Check if services are running
echo -e "${YELLOW}Checking services...${NC}"
if ! docker ps | grep -q hr-mariadb; then
    echo -e "✗ MariaDB is not running. Please run ./quickstart.sh first"
    exit 1
fi

if ! docker ps | grep -q hr-nats; then
    echo -e "✗ NATS is not running. Please run ./quickstart.sh first"
    exit 1
fi

if ! docker ps | grep -q hr-debezium; then
    echo -e "✗ Debezium is not running. Please run ./quickstart.sh first"
    exit 1
fi

echo -e "${GREEN}✓ All services are running${NC}"
echo ""

# Test 1: Insert a new employee
echo -e "${CYAN}Test 1: Creating a new employee${NC}"
echo "Running SQL: INSERT INTO employees..."

docker exec hr-mariadb mysql -uhruser -phrpass hrdb -e "
INSERT INTO employees (employee_number, first_name, last_name, email, position_id, department_id, salary, hire_date, status)
VALUES ('EMP999', 'Test', 'User', 'test.user@company.com', 'IC2', 1, 90000, CURDATE(), 'active');
"

echo -e "${GREEN}✓ Employee created: EMP999 - Test User${NC}"
echo ""

# Test 2: Update employee salary
echo -e "${CYAN}Test 2: Updating employee salary${NC}"
echo "Running SQL: UPDATE employees SET salary..."

docker exec hr-mariadb mysql -uhruser -phrpass hrdb -e "
UPDATE employees
SET salary = 95000
WHERE employee_number = 'EMP999';
"

echo -e "${GREEN}✓ Salary updated from 90000 to 95000${NC}"
echo ""

# Test 3: Create a salary change record
echo -e "${CYAN}Test 3: Recording salary change${NC}"
echo "Running SQL: INSERT INTO salary_changes..."

docker exec hr-mariadb mysql -uhruser -phrpass hrdb -e "
INSERT INTO salary_changes (employee_id, old_salary, new_salary, reason, effective_date)
SELECT id, 90000, 95000, 'Performance review', CURDATE()
FROM employees WHERE employee_number = 'EMP999';
"

echo -e "${GREEN}✓ Salary change recorded${NC}"
echo ""

# Test 4: Create a leave request
echo -e "${CYAN}Test 4: Creating leave request${NC}"
echo "Running SQL: INSERT INTO leave_requests..."

docker exec hr-mariadb mysql -uhruser -phrpass hrdb -e "
INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, status, reason)
SELECT id, 'vacation', DATE_ADD(CURDATE(), INTERVAL 7 DAY), DATE_ADD(CURDATE(), INTERVAL 14 DAY), 'pending', 'Summer vacation'
FROM employees WHERE employee_number = 'EMP999';
"

echo -e "${GREEN}✓ Leave request created${NC}"
echo ""

# Test 5: Delete child records first (to avoid foreign key constraint errors)
echo -e "${CYAN}Test 5: Cleaning up test data${NC}"
echo "Running SQL: DELETE FROM leave_requests..."

docker exec hr-mariadb mysql -uhruser -phrpass hrdb -e "
DELETE FROM leave_requests
WHERE employee_id = (SELECT id FROM employees WHERE employee_number = 'EMP999');
"

echo -e "${GREEN}✓ Leave requests deleted${NC}"

echo "Running SQL: DELETE FROM salary_changes..."

docker exec hr-mariadb mysql -uhruser -phrpass hrdb -e "
DELETE FROM salary_changes
WHERE employee_id = (SELECT id FROM employees WHERE employee_number = 'EMP999');
"

echo -e "${GREEN}✓ Salary changes deleted${NC}"

echo "Running SQL: DELETE FROM employees..."

docker exec hr-mariadb mysql -uhruser -phrpass hrdb -e "
DELETE FROM employees WHERE employee_number = 'EMP999';
"

echo -e "${GREEN}✓ Test employee deleted${NC}"
echo ""

# Show summary
echo -e "${BLUE}╔════════════════════════════════════════╗"
echo "║  CDC Tests Completed!                  ║"
echo "╚════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}CDC events should now be available in NATS.${NC}"
echo ""
echo "To verify CDC events are being published, you can:"
echo ""
echo "  1. Check NATS JetStream streams:"
echo "     curl http://localhost:8222/jsz?streams=true"
echo ""
echo "  2. Subscribe to CDC events (requires NATS CLI):"
echo "     nats sub 'HCM.CDC.HR.>' --server localhost:4222"
echo ""
echo "  3. Or use nats-box container:"
echo "     docker run --rm -it --network bizeventhub-p2_hr-network \\"
echo "       natsio/nats-box:latest \\"
echo "       nats sub 'HCM.CDC.HR.>' --server nats://hr-nats:4222"
echo ""
echo "  4. View specific table events:"
echo "     docker run --rm -it --network bizeventhub-p2_hr-network \\"
echo "       natsio/nats-box:latest \\"
echo "       nats sub 'HCM.CDC.HR.hrdb.employees' --server nats://hr-nats:4222"
echo ""
echo "  5. Check Debezium logs:"
echo "     docker logs hr-debezium | tail -50"
echo ""
echo -e "${GREEN}Expected events on topics:${NC}"
echo "  - HCM.CDC.HR.hrdb.employees - 1 INSERT, 1 UPDATE, 1 DELETE"
echo "  - HCM.CDC.HR.hrdb.salary_changes - 1 INSERT, 1 DELETE"
echo "  - HCM.CDC.HR.hrdb.leave_requests - 1 INSERT, 1 DELETE"
echo ""
