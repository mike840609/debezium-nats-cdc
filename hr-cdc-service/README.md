# HR CDC Service

Spring Boot application with embedded Debezium for Change Data Capture (CDC) from MariaDB.

## Structure

```
src/main/java/com/hr/cdc/
├── HrCdcApplication.java           # Main Spring Boot application
├── config/
│   └── DebeziumConfig.java         # Debezium embedded engine configuration
├── handler/
│   └── CdcEventHandler.java        # CDC event processing logic
└── controller/
    └── HealthController.java       # Health check endpoints
```

## Key Components

### DebeziumConfig.java
- Configures the embedded Debezium engine
- Sets up connection to MariaDB
- Defines which tables to monitor
- Manages offset and schema history storage

### CdcEventHandler.java
- Processes CDC events from Debezium
- Routes events to specific table handlers
- Detects business-level changes (promotions, transfers, etc.)
- **TODO**: Implement actual event publishing logic

### Health Check
- `GET /health` - Returns service health status
- `GET /` - Returns service information

## Configuration

Edit `src/main/resources/application.properties`:

```properties
# Database connection
debezium.database.hostname=mariadb
debezium.database.user=hruser
debezium.database.password=hrpass

# Tables to monitor
debezium.table.include.list=hrdb.employees,hrdb.departments,...

# Snapshot mode
debezium.snapshot.mode=initial  # or 'schema_only'
```

## Building

```bash
# Using Maven
mvn clean package

# Using Docker
docker build -t hr-cdc-service .
```

## Running

### Local (requires MariaDB running)
```bash
java -jar target/hr-cdc-service-1.0.0.jar
```

### Docker
```bash
docker run -p 8080:8080 hr-cdc-service
```

## Extending

### Add Custom Event Handlers

Edit `CdcEventHandler.java` and implement your business logic:

```java
private void handleEmployeeChange(String operation, Map before, Map after) {
    // Your custom logic here
    if (isPromotion(before, after)) {
        publishPromotionEvent(before, after);
    }
}
```

### Add Event Publishers

Create new classes to publish events to:
- Message queues (Kafka, RabbitMQ)
- REST APIs
- Webhooks
- Cloud services

## Dependencies

- Spring Boot 3.2.0
- Debezium 2.5.0.Final (Embedded + MySQL Connector)
- Lombok (for cleaner code)
- Jackson (for JSON processing)
