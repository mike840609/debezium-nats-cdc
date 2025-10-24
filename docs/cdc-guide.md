# HR Event Publisher - CDC Setup (Simple)

This docker-compose setup provides MariaDB with binlog and NATS JetStream for the HR CDC pipeline.

## Architecture

```
MariaDB (binlog) → Debezium Server → HTTP → [Your Spring Boot App] → NATS JetStream
```

## Current Status

✅ **Working:**
- MariaDB 10.6.19 with binlog enabled
- NATS JetStream running and healthy
- Debezium Server configured to capture MariaDB changes

⚠️ **Requires Implementation:**
- **Spring Boot HTTP endpoint** to receive CDC events from Debezium and publish to NATS

## Components

1. **MariaDB 10.6.19**
   - Database: `hrdb`
   - User: `hruser` / `hrpass`
   - Root: `root` / `rootpass`
   - Binlog enabled with ROW format
   - Port: 3306

2. **NATS with JetStream**
   - Client port: 4222
   - Monitoring: http://localhost:8222
   - JetStream enabled for persistence

3. **Debezium Server 3.0.0.Final**
   - Captures MariaDB binlog changes
   - Configured to POST CDC events via HTTP
   - **Note:** Debezium will send events to `http://localhost:8080/cdc`

## Quick Start

### 1. Start the infrastructure

```bash
docker-compose up -d
```

### 2. Verify services are running

```bash
docker ps
```

You should see:
- `hr-mariadb` (healthy)
- `hr-nats` (healthy)
- `hr-debezium` (may restart until Spring Boot endpoint is ready)

### 3. Check NATS JetStream

```bash
curl http://localhost:8222/jsz
```

### 4. Initialize the database (if not already done)

```bash
docker exec -i hr-mariadb mysql -uroot -prootpass hrdb < init-db.sql
```

## Next Steps: Implement the Bridge Service

You need to create a Spring Boot application with an HTTP endpoint that:

1. Receives CDC events from Debezium via POST to `/cdc`
2. Transforms the events as needed
3. Publishes to NATS JetStream

### Example Spring Boot Controller

```java
@RestController
@RequestMapping("/cdc")
public class DebeziumCdcController {

    @Autowired
    private NatsPublisher natsPublisher;

    @PostMapping
    public ResponseEntity<Void> handleCdcEvent(@RequestBody String cdcEvent) {
        try {
            // Parse Debezium CDC event
            JsonNode event = objectMapper.readTree(cdcEvent);

            // Extract table name and operation
            String table = event.path("payload").path("source").path("table").asText();
            String operation = event.path("payload").path("op").asText(); // c=create, u=update, d=delete

            // Publish to NATS subject based on table
            String subject = "cdc.hr." + table;
            natsPublisher.publish(subject, cdcEvent);

            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("Error processing CDC event", e);
            return ResponseEntity.status(500).build();
        }
    }
}
```

### Alternative: Direct MariaDB Binlog Reader

If you prefer to avoid Debezium Server entirely, you can:

1. Use [Maxwell's Daemon](https://maxwells-daemon.io/) - simpler, lighter weight
2. Use [mysql-binlog-connector-java](https://github.com/shyiko/mysql-binlog-connector-java) directly in Spring Boot
3. Use [go-mysql](https://github.com/go-mysql-org/go-mysql) for a Go-based solution

## Database Schema

The `init-db.sql` script creates:
- `employees` - Employee master data
- `departments` - Organizational structure
- `positions` - Job positions and levels
- `salary_changes` - Salary adjustment history
- `leave_requests` - Leave management
- `attendance_records` - Daily attendance tracking

## Debezium CDC Event Format

Debezium sends events in this format:

```json
{
  "payload": {
    "before": { ... },  // State before change (null for inserts)
    "after": { ... },   // State after change (null for deletes)
    "source": {
      "version": "3.0.0.Final",
      "connector": "mysql",
      "name": "cdc.hr",
      "ts_ms": 1634567890123,
      "db": "hrdb",
      "table": "employees"
    },
    "op": "c",  // c=create, u=update, d=delete, r=read (snapshot)
    "ts_ms": 1634567890123
  }
}
```

## Troubleshooting

### Debezium keeps restarting

This is expected until you implement the HTTP endpoint at `http://localhost:8080/cdc`. Debezium will retry connecting to the endpoint.

**Options:**
1. Implement the Spring Boot endpoint
2. Stop Debezium until ready: `docker-compose stop debezium`
3. Use a stub endpoint for testing

### Check Debezium logs

```bash
docker logs hr-debezium -f
```

### Verify binlog is enabled

```bash
docker exec hr-mariadb mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'log_bin';"
docker exec hr-mariadb mysql -uroot -prootpass -e "SHOW BINARY LOGS;"
```

### Test database changes

```bash
# Connect to MariaDB
docker exec -it hr-mariadb mysql -uhruser -phrpass hrdb

# Make a change
UPDATE employees SET salary = 125000 WHERE employee_number = 'EMP001';
```

This change will be captured by Debezium and sent to your HTTP endpoint.

## Simplified Alternative

If Debezium is too complex for your needs, consider this simpler stack:

```
MariaDB → Maxwell's Daemon → NATS JetStream
```

Maxwell is easier to configure and can publish directly to various sinks. See [Maxwell's NATS Producer](https://maxwells-daemon.io/producers/).

## Production Considerations

1. **Security**
   - Use TLS for NATS
   - Secure MariaDB binlog access
   - Authenticate HTTP endpoint

2. **Monitoring**
   - Monitor Debezium lag
   - Track NATS JetStream metrics
   - Alert on CDC failures

3. **Scalability**
   - Run multiple Spring Boot instances
   - Use NATS consumer groups
   - Partition by department/table

## References

- [Debezium Documentation](https://debezium.io/documentation/reference/stable/operations/debezium-server.html)
- [NATS JetStream](https://docs.nats.io/nats-concepts/jetstream)
- [Design Document](./hr-event-publisher-system-design.md)
