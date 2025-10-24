# HR Event Publisher System - Implementation Guide

## 📁 Files Overview

This package contains a complete implementation of the HR Event Publisher System with the following files:

### Documentation
- **hr-event-publisher-architecture.svg** - System architecture diagram
- **hr-event-publisher-design.md** - Comprehensive design document
- **README.md** - This file

### Infrastructure
- **docker-compose.yml** - Complete Docker Compose setup for all services
- **init-mariadb.sql** - MariaDB schema and sample data
- **init-clickhouse.sql** - ClickHouse event store schema

### Java Implementation
- **EmployeePromotedEvent.java** - Domain event model example
- **CdcEventListener.java** - NATS listener for CDC events
- **PromotionTransformer.java** - Business logic to detect promotions
- **TerminationTransformer.java** - Business logic to detect terminations

---

## 🚀 Quick Start

### Prerequisites
- Docker & Docker Compose
- Java 17+ and Maven (for building the Spring Boot app)
- 8GB RAM minimum
- 20GB disk space

### Step 1: Setup Infrastructure

1. **Create project directory structure:**
```bash
mkdir -p hr-event-publisher
cd hr-event-publisher

mkdir -p init-scripts/mariadb
mkdir -p init-scripts/clickhouse
mkdir -p logs
mkdir -p src/main/java/com/company/hr/events
```

2. **Copy initialization scripts:**
```bash
# Copy MariaDB init script
cp init-mariadb.sql init-scripts/mariadb/01-init.sql

# Copy ClickHouse init script
cp init-clickhouse.sql init-scripts/clickhouse/01-init.sql
```

3. **Copy docker-compose.yml to project root:**
```bash
cp docker-compose.yml .
```

### Step 2: Start Infrastructure Services

```bash
# Start MariaDB, NATS, Debezium, and ClickHouse
docker-compose up -d mariadb nats clickhouse debezium

# Check logs
docker-compose logs -f debezium
```

**Wait for services to be healthy** (check with `docker-compose ps`)

### Step 3: Build Spring Boot Application

1. **Create Maven project structure:**
```bash
cd src/main/java/com/company/hr/events

# Create package directories
mkdir -p {config,listener,transformer,publisher,service,repository,model/{cdc,domain},util}
```

2. **Copy implementation files:**
```bash
cp EmployeePromotedEvent.java model/domain/
cp CdcEventListener.java listener/
cp PromotionTransformer.java transformer/
cp TerminationTransformer.java transformer/
```

3. **Create pom.xml** (see design document for complete Maven dependencies)

4. **Build the application:**
```bash
mvn clean package -DskipTests
```

### Step 4: Run the Event Publisher

```bash
# Start the Spring Boot service
docker-compose up -d hr-event-publisher

# Check logs
docker-compose logs -f hr-event-publisher
```

### Step 5: Verify the System

1. **Check NATS subjects:**
```bash
# Install NATS CLI
# brew install nats-io/nats-tools/nats (macOS)
# or download from https://github.com/nats-io/natscli

# Monitor CDC events
nats sub "cdc.hr.>"

# Monitor domain events
nats sub "events.hr.>"
```

2. **Test with sample data:**
```bash
# Connect to MariaDB
docker exec -it hr-mariadb mysql -u root -prootpassword hr_db

# Simulate a promotion
UPDATE employees 
SET position_id = 'pos-003', salary = 165000 
WHERE id = 'emp-001';

# Simulate a termination
UPDATE employees 
SET status = 'terminated', 
    termination_date = CURDATE(),
    termination_type = 'resignation',
    termination_reason = 'New opportunity'
WHERE id = 'emp-002';
```

3. **Verify events in ClickHouse:**
```bash
# Connect to ClickHouse
docker exec -it hr-clickhouse clickhouse-client

# Query events
SELECT event_type, aggregate_id, event_timestamp, payload 
FROM hr_events.event_log 
ORDER BY event_timestamp DESC 
LIMIT 10;

# Check statistics
SELECT event_type, count() as count 
FROM hr_events.event_log 
GROUP BY event_type;
```

---

## 🔧 Configuration

### Environment Variables

Create a `.env` file in the project root:

```env
# MariaDB
MYSQL_ROOT_PASSWORD=rootpassword
MYSQL_DATABASE=hr_db
MYSQL_USER=hr_user
MYSQL_PASSWORD=hr_password

# Debezium
DEBEZIUM_PASSWORD=debezium_password

# ClickHouse
CLICKHOUSE_USER=clickhouse_user
CLICKHOUSE_PASSWORD=clickhouse_password

# NATS
NATS_URL=nats://nats:4222
```

### Spring Boot Configuration

Create `application.yml` in `src/main/resources/`:

```yaml
spring:
  application:
    name: hr-event-publisher
  
  nats:
    server: ${NATS_URL:nats://localhost:4222}
  
  datasource:
    clickhouse:
      url: ${CLICKHOUSE_URL:jdbc:clickhouse://localhost:8123/hr_events}
      username: ${CLICKHOUSE_USER:clickhouse_user}
      password: ${CLICKHOUSE_PASSWORD:clickhouse_password}

event-publisher:
  enable-enrichment: true
  enable-validation: true
  store-in-clickhouse: true
```

---

## 📊 Monitoring

### Health Checks

```bash
# Check service health
curl http://localhost:8080/actuator/health

# Check NATS
curl http://localhost:8222/healthz

# Check ClickHouse
curl http://localhost:8123/ping
```

### Metrics

```bash
# Prometheus metrics
curl http://localhost:8080/actuator/prometheus

# NATS monitoring
open http://localhost:8222
```

### Logs

```bash
# Application logs
docker-compose logs -f hr-event-publisher

# Debezium logs
docker-compose logs -f debezium

# All services
docker-compose logs -f
```

---

## 🧪 Testing

### Manual Testing Scenarios

#### Scenario 1: Employee Promotion
```sql
-- Connect to MariaDB
USE hr_db;

-- Promote employee with salary increase
UPDATE employees 
SET position_id = 'pos-003', 
    salary = 180000,
    updated_at = NOW()
WHERE id = 'emp-001';

-- Expected: EmployeePromotedEvent published to events.hr.employee.promoted
```

#### Scenario 2: Employee Termination
```sql
-- Terminate employee
UPDATE employees 
SET status = 'terminated',
    termination_date = CURDATE(),
    termination_type = 'voluntary',
    termination_reason = 'Relocated to another city',
    terminated_by_user_id = 'emp-003',
    updated_at = NOW()
WHERE id = 'emp-002';

-- Expected: EmployeeTerminatedEvent published to events.hr.employee.terminated
```

#### Scenario 3: Department Transfer
```sql
-- Transfer employee to different department
UPDATE employees 
SET department_id = 'dept-006',
    updated_at = NOW()
WHERE id = 'emp-001';

-- Expected: EmployeeTransferredEvent published to events.hr.employee.transferred
```

### Verify Events

```bash
# Subscribe to all HR events
nats sub "events.hr.>" --count=10

# Or use ClickHouse
docker exec -it hr-clickhouse clickhouse-client --query "
SELECT 
    event_type,
    aggregate_id,
    toDateTime(event_timestamp) as timestamp,
    JSONExtractString(payload, 'employeeName') as employee_name
FROM hr_events.event_log
WHERE event_timestamp > now() - INTERVAL 1 HOUR
ORDER BY event_timestamp DESC
FORMAT Pretty"
```

---

## 🔌 Integration with Consumers

### Subscribe to Events (NATS)

**Node.js Example:**
```javascript
const { connect, JSONCodec } = require('nats');

async function subscribeToHREvents() {
  const nc = await connect({ servers: 'nats://localhost:4222' });
  const jc = JSONCodec();
  
  const sub = nc.subscribe('events.hr.employee.*');
  
  for await (const msg of sub) {
    const event = jc.decode(msg.data);
    console.log(`Received ${event.eventType}:`, event);
    
    // Process the event
    if (event.eventType === 'EmployeeHired') {
      // Send welcome email
    }
  }
}

subscribeToHREvents();
```

**Python Example:**
```python
import asyncio
from nats.aio.client import Client as NATS
import json

async def subscribe_hr_events():
    nc = NATS()
    await nc.connect("nats://localhost:4222")
    
    async def message_handler(msg):
        event = json.loads(msg.data.decode())
        print(f"Received {event['eventType']}: {event}")
        
        # Process the event
        if event['eventType'] == 'EmployeeTerminated':
            # Revoke access, update systems, etc.
            pass
    
    await nc.subscribe("events.hr.employee.*", cb=message_handler)
    
    # Keep the connection alive
    while True:
        await asyncio.sleep(1)

asyncio.run(subscribe_hr_events())
```

---

## 📈 Scaling

### Horizontal Scaling

Scale the Spring Boot application:

```bash
# Scale to 3 instances
docker-compose up -d --scale hr-event-publisher=3
```

NATS consumer groups ensure events are distributed across instances.

### NATS JetStream

For guaranteed delivery, enable JetStream:

```yaml
# In docker-compose.yml, NATS configuration already includes JetStream
# Configure durable consumers in your application
```

---

## 🛠️ Troubleshooting

### Issue: Debezium not capturing changes

**Solution:**
```bash
# Check binlog is enabled
docker exec hr-mariadb mysql -u root -prootpassword -e "SHOW VARIABLES LIKE 'log_bin';"

# Check Debezium user permissions
docker exec hr-mariadb mysql -u root -prootpassword -e "SHOW GRANTS FOR 'debezium_user'@'%';"

# Check Debezium logs
docker-compose logs debezium | grep ERROR
```

### Issue: Events not appearing in ClickHouse

**Solution:**
```bash
# Check ClickHouse connection
docker exec hr-event-publisher curl http://clickhouse:8123/ping

# Check application logs
docker-compose logs hr-event-publisher | grep ClickHouse

# Verify table exists
docker exec hr-clickhouse clickhouse-client --query "SHOW TABLES FROM hr_events"
```

### Issue: NATS connection refused

**Solution:**
```bash
# Check NATS is running
docker-compose ps nats

# Test NATS connection
docker exec hr-event-publisher nc -zv nats 4222

# Check NATS logs
docker-compose logs nats
```

---

## 🔐 Security

### Production Recommendations

1. **Use TLS for NATS:**
```yaml
nats:
  command:
    - "--tls"
    - "--tlscert=/certs/server-cert.pem"
    - "--tlskey=/certs/server-key.pem"
```

2. **Enable Authentication:**
```yaml
nats:
  command:
    - "--user=admin"
    - "--pass=${NATS_PASSWORD}"
```

3. **Mask Sensitive Data:**
```java
// In event transformers
if (field.isSensitive()) {
    payload.put(field.getName(), "***MASKED***");
}
```

4. **Enable SSL for ClickHouse:**
```yaml
clickhouse:
  environment:
    CLICKHOUSE_SSL: 1
```

---

## 📚 Additional Resources

- [Debezium Documentation](https://debezium.io/documentation/)
- [NATS Documentation](https://docs.nats.io/)
- [Spring Cloud Stream](https://spring.io/projects/spring-cloud-stream)
- [ClickHouse Documentation](https://clickhouse.com/docs)
- [Event-Driven Architecture Patterns](https://martinfowler.com/articles/201701-event-driven.html)

---

## 📝 Next Steps

1. ✅ Complete the transformer implementations for all event types
2. ✅ Add integration tests
3. ✅ Implement event schema validation
4. ✅ Set up monitoring dashboards (Grafana)
5. ✅ Add circuit breakers for fault tolerance
6. ✅ Implement event replay mechanism
7. ✅ Add OpenAPI documentation
8. ✅ Set up CI/CD pipeline

---

## 📞 Support

For issues or questions:
- Check the design document for detailed explanations
- Review the troubleshooting section
- Check Docker logs: `docker-compose logs -f`

---

## 📄 License

All components used are open-source:
- MariaDB: GPL v2
- Debezium: Apache 2.0
- NATS: Apache 2.0
- ClickHouse: Apache 2.0
- Spring Boot: Apache 2.0

---

**Version:** 1.0  
**Last Updated:** 2025-10-22
