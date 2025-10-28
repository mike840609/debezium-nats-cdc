# HR CDC Service - Simple Change Data Capture

A simple Change Data Capture (CDC) service for HR systems using Spring Boot with embedded Debezium and MariaDB.

## 📋 Overview

This project implements a streamlined CDC pipeline that captures database changes from MariaDB and processes them in real-time using Spring Boot with embedded Debezium. No external message brokers needed!

## 🏗️ Architecture

**Simple & Direct:**
```
MariaDB (Binlog) → Spring Boot (Embedded Debezium) → Your Business Logic
```

**Components:**
- **MariaDB** - Source database with HR data (employees, departments, positions, etc.)
- **Spring Boot + Debezium** - CDC service that captures and processes changes in real-time
- **Docker Compose** - Infrastructure orchestration

## 📁 Project Structure

```
.
├── Makefile                    # Common operations (start, stop, test, clean)
├── docker-compose.yml          # Service definitions
├── hr-cdc-service/             # Spring Boot CDC application
│   ├── pom.xml                # Maven dependencies
│   ├── Dockerfile             # Container build
│   └── src/main/
│       ├── java/com/hr/cdc/
│       │   ├── HrCdcApplication.java       # Main application
│       │   ├── config/
│       │   │   └── DebeziumConfig.java     # Debezium configuration
│       │   ├── handler/
│       │   │   └── CdcEventHandler.java    # CDC event processing
│       │   └── controller/
│       │       └── HealthController.java   # Health checks
│       └── resources/
│           └── application.properties      # Configuration
├── config/
│   └── mariadb/
│       └── my.cnf             # MariaDB configuration
├── scripts/
│   └── test-cdc.sh            # CDC pipeline test script
├── sql/
│   └── init-db.sql            # Database schema and sample data
└── docs/                       # Documentation
```

## 🚀 Quick Start

### Prerequisites

- Docker & Docker Compose
- 2GB RAM minimum
- 5GB disk space

### Start the Services

```bash
# Build and start all services
docker-compose up -d --build

# Check service status
docker-compose ps

# View CDC service logs
docker-compose logs -f hr-cdc-service
```

### Test the CDC Pipeline

```bash
# Run the test script
./scripts/test-cdc.sh

# Watch the CDC service logs to see events being processed
docker-compose logs -f hr-cdc-service
```

### Stop Services

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (clean slate)
docker-compose down -v
```

## 📊 Service Endpoints

| Service       | Endpoint                    | Description            |
|---------------|-----------------------------|------------------------|
| MariaDB       | `localhost:3306`            | Database server        |
| CDC Service   | `localhost:8080`            | Spring Boot application|
| Health Check  | `http://localhost:8080/health` | Service health status |

## 🔧 Configuration

### Database Configuration

Database connection settings are in `hr-cdc-service/src/main/resources/application.properties`:

```properties
debezium.database.hostname=mariadb
debezium.database.port=3306
debezium.database.user=hruser
debezium.database.password=hrpass
debezium.database.dbname=hrdb
```

### Tables Being Monitored

The service monitors these HR tables:
- `employees` - Employee master data
- `departments` - Organizational structure
- `positions` - Job positions
- `salary_changes` - Salary history
- `leave_requests` - Leave/PTO management
- `attendance_records` - Daily attendance

### Snapshot Mode

On first start, Debezium takes a snapshot of existing data:
```properties
debezium.snapshot.mode=initial
```

Change to `schema_only` to skip initial data snapshot.

## 📝 How It Works

### 1. Debezium Captures Changes

The embedded Debezium engine reads MariaDB's binary log (binlog) and captures:
- **INSERT** operations (op: 'c' for create)
- **UPDATE** operations (op: 'u' for update)
- **DELETE** operations (op: 'd' for delete)

### 2. Events Are Processed

Each change event is routed to specific handlers in `CdcEventHandler.java`:

```java
// Example: Employee change detection
private void handleEmployeeChange(String operation, Map before, Map after) {
    if (operation.equals("c")) {
        log.info("New employee created: {}", after);
        // TODO: Publish EmployeeHired event
    }
    else if (operation.equals("u")) {
        // Detect promotion, transfer, status changes
        detectEmployeeUpdates(before, after);
    }
}
```

### 3. Business Logic (TODO)

The handlers include placeholders for your business logic:
- Detect promotions (position changes)
- Detect transfers (department changes)
- Publish domain events
- Trigger workflows
- Update external systems

## 🧪 Testing

### Manual Testing

```bash
# Connect to MariaDB
docker exec -it hr-mariadb mysql -uhruser -phrpass hrdb

# Insert a test employee
INSERT INTO employees (employee_id, first_name, last_name, email, department_id, position_id, hire_date, status)
VALUES ('TEST001', 'John', 'Doe', 'john.doe@example.com', 1, 1, '2024-01-15', 'ACTIVE');

# Update the employee
UPDATE employees SET position_id = 2 WHERE employee_id = 'TEST001';

# Delete the employee
DELETE FROM employees WHERE employee_id = 'TEST001';
```

Watch the CDC service logs to see events being captured:
```bash
docker-compose logs -f hr-cdc-service
```

### Automated Testing

```bash
./scripts/test-cdc.sh
```

This script performs CRUD operations and you can verify events in the logs.

## 🛠️ Development

### Local Development (without Docker)

1. Start MariaDB:
   ```bash
   docker-compose up -d mariadb
   ```

2. Build the Spring Boot app:
   ```bash
   cd hr-cdc-service
   mvn clean package
   ```

3. Run locally:
   ```bash
   java -jar target/hr-cdc-service-1.0.0.jar
   ```

### Adding Custom Business Logic

Edit `hr-cdc-service/src/main/java/com/hr/cdc/handler/CdcEventHandler.java`:

```java
private void handleEmployeeChange(String operation, Map before, Map after) {
    // Add your custom logic here
    if (operation.equals("u")) {
        // Detect specific changes
        if (!equals(before.get("salary"), after.get("salary"))) {
            // Handle salary change
            publishSalaryChangeEvent(before, after);
        }
    }
}
```

### Rebuilding

```bash
# Rebuild the CDC service
docker-compose up -d --build hr-cdc-service

# View updated logs
docker-compose logs -f hr-cdc-service
```

## 📈 Monitoring

### Health Check

```bash
curl http://localhost:8080/health
```

Response:
```json
{
  "status": "UP",
  "service": "hr-cdc-service",
  "timestamp": 1234567890
}
```

### Service Logs

```bash
# All services
docker-compose logs

# CDC service only
docker-compose logs hr-cdc-service

# Follow logs
docker-compose logs -f hr-cdc-service
```

### Database Binlog Status

```bash
docker exec -it hr-mariadb mysql -uroot -prootpass -e "SHOW BINARY LOGS;"
docker exec -it hr-mariadb mysql -uroot -prootpass -e "SHOW MASTER STATUS;"
```

## 🐛 Troubleshooting

### CDC Service Not Starting

Check if MariaDB is healthy:
```bash
docker-compose ps
```

View CDC service logs:
```bash
docker-compose logs hr-cdc-service
```

### No Events Being Captured

Verify binlog is enabled:
```bash
docker exec -it hr-mariadb mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'log_bin';"
```

Should show `log_bin = ON`

### Offset/Schema History Issues

Remove and restart:
```bash
docker-compose down -v
docker-compose up -d --build
```

## 🔒 Security Notes

**This is a development setup!** For production:
- Use environment variables for credentials
- Enable TLS for database connections
- Implement proper authentication
- Use secrets management (Vault, AWS Secrets Manager, etc.)
- Limit database user permissions

## 📚 Documentation

- [Design Document](docs/design.md) - High-level design decisions
- [System Design](docs/system-design.md) - Detailed architecture
- [CDC Guide](docs/cdc-guide.md) - Debezium implementation details

## 🎯 Next Steps

1. **Implement Business Logic**: Add event publishing, notifications, or workflow triggers
2. **Add Event Storage**: Integrate with ClickHouse, Kafka, or other sinks
3. **Add Monitoring**: Prometheus metrics, Grafana dashboards
4. **Add Tests**: Unit and integration tests
5. **Productionize**: Environment configs, secrets management, HA setup

## 📄 License

MIT License - feel free to use and modify as needed.

## 🤝 Contributing

This is a simple reference implementation. Customize it for your needs!

---

**Simplified Architecture = Easier to Understand and Maintain**
