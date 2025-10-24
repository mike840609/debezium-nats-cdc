# HR Event Publisher System - Design Document

## 1. System Overview

This system is designed to capture HR-related data changes and publish business-level domain events to NATS message broker for internal company consumption. It replaces Kafka with NATS and focuses on delivering meaningful business events rather than raw database changes.

### Key Objectives
- Capture data changes from MariaDB using CDC (Debezium)
- Consume external events from upstream NATS subjects
- Transform low-level changes into high-level business domain events
- Publish events to NATS for downstream consumers
- Store events in ClickHouse for analytics and audit trails

---

## 2. Architecture Components

### 2.1 Data Sources Layer

#### MariaDB 10.6.19
- **Role**: Primary HR database storing transactional data
- **Tables**: 
  - `employees` (employee master data)
  - `departments` (organizational structure)
  - `positions` (job positions)
  - `salary_changes` (compensation history)
  - `attendance_records` (time tracking)
  - `leave_requests` (PTO management)
- **Configuration**: Binary logging enabled for CDC

#### Upstream NATS Subjects
- **Role**: Receive events from external systems (payroll, time tracking, etc.)
- **Subjects**:
  - `hr.external.payroll.*`
  - `hr.external.timeclock.*`
  - `hr.external.benefits.*`

### 2.2 CDC Layer

#### Debezium Server
- **Version**: Latest stable (3.3.1.Final)
- **Connector**: MySQL Connector for MariaDB
- **Configuration**:
```properties
debezium.sink.type=nats-jetstream
debezium.sink.nats.url=nats://nats-server:4222
debezium.sink.nats.subject=cdc.hr.{tableName}

debezium.source.connector.class=io.debezium.connector.mysql.MySqlConnector
debezium.source.offset.storage=file
debezium.source.database.hostname=mariadb
debezium.source.database.port=3306
debezium.source.database.user=debezium_user
debezium.source.database.password=${DEBEZIUM_PASSWORD}
debezium.source.database.include.list=hr_db
debezium.source.table.include.list=hr_db.employees

# Transforms
debezium.transforms=unwrap
debezium.transforms.unwrap.type=io.debezium.transforms.ExtractNewRecordState
debezium.transforms.unwrap.drop.tombstones=false
```

**Output**: Publishes CDC events to NATS subjects:
- `cdc.hr.employees`
- `cdc.hr.departments`
- `cdc.hr.positions`
- `cdc.hr.salary_changes`
- `cdc.hr.attendance_records`
- `cdc.hr.leave_requests`

### 2.3 Message Broker Layer

#### NATS Server
- **Version**: Latest stable (2.10+)
- **Features Used**:
  - JetStream for guaranteed delivery
  - Subject-based routing
  - Consumer groups for scaling
  
**Subject Hierarchy**:
```
Input Subjects:
├── cdc.hr.*                    # CDC events from Debezium
│   ├── cdc.hr.employees
│   ├── cdc.hr.departments
│   └── cdc.hr.salary_changes
└── hr.external.*               # External system events
    ├── hr.external.payroll.*
    └── hr.external.timeclock.*

Output Subjects:
└── events.hr.*                 # Business domain events
    ├── events.hr.employee.*
    │   ├── events.hr.employee.hired
    │   ├── events.hr.employee.promoted
    │   ├── events.hr.employee.terminated
    │   ├── events.hr.employee.transferred
    │   └── events.hr.employee.updated
    ├── events.hr.org.*
    │   ├── events.hr.org.department.created
    │   ├── events.hr.org.department.restructured
    │   └── events.hr.org.manager.assigned
    ├── events.hr.compensation.*
    │   ├── events.hr.compensation.salary.adjusted
    │   └── events.hr.compensation.bonus.awarded
    └── events.hr.attendance.*
        ├── events.hr.attendance.leave.requested
        ├── events.hr.attendance.leave.approved
        └── events.hr.attendance.marked
```

### 2.4 Event Processing Layer

#### Spring Boot Event Publisher Service
**Technology Stack**:
- Java 17+
- Spring Boot 3.2+
- Spring Cloud Stream with NATS Binder
- Spring Data JPA (for auxiliary queries if needed)

**Key Components**:

##### Event Listener Module
```java
@Component
public class CdcEventListener {
    
    @StreamListener("cdc.hr.employees")
    public void handleEmployeeChange(CdcEvent event) {
        // Transform CDC event to domain event
    }
    
    @StreamListener("hr.external.payroll.salary-update")
    public void handleExternalSalaryUpdate(ExternalEvent event) {
        // Process external event
    }
}
```

##### Event Transformation Service
Converts low-level CDC events into high-level business events:
- **Pattern Matching**: Identifies business operations from data changes
- **Enrichment**: Adds contextual information
- **Aggregation**: Combines related changes into single business event
- **Validation**: Ensures data integrity and business rules

##### Domain Event Publisher
```java
@Service
public class DomainEventPublisher {
    
    private final NatsTemplate natsTemplate;
    
    public void publishEmployeeHired(EmployeeHiredEvent event) {
        natsTemplate.convertAndSend("events.hr.employee.hired", event);
        // Also store in ClickHouse
        clickHouseRepository.save(event);
    }
}
```

### 2.5 Storage Layer

#### ClickHouse 24.10
**Purpose**: Store all events for analytics, audit trails, and compliance

**Schema**:
```sql
CREATE TABLE hr_events (
    event_id UUID DEFAULT generateUUIDv4(),
    event_type String,
    event_timestamp DateTime64(3),
    aggregate_id String,
    aggregate_type String,
    event_version String,
    payload String,  -- JSON payload
    metadata String, -- JSON metadata
    source_system String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_timestamp)
ORDER BY (event_type, event_timestamp, aggregate_id);

CREATE TABLE audit_trail (
    audit_id UUID DEFAULT generateUUIDv4(),
    entity_type String,
    entity_id String,
    operation String,
    changed_by String,
    changed_at DateTime64(3),
    old_value String,
    new_value String,
    event_id UUID
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(changed_at)
ORDER BY (entity_type, changed_at, entity_id);
```

---

## 3. Event Granularity Design

### 3.1 Business Domain Events vs CDC Events

**CDC Event** (Low-level):
```json
{
  "op": "u",
  "before": {"id": 123, "salary": 50000, "updated_at": "2025-10-15"},
  "after": {"id": 123, "salary": 60000, "updated_at": "2025-10-22"},
  "source": {"table": "employees", "ts_ms": 1729584000000}
}
```

**Domain Event** (High-level):
```json
{
  "eventType": "EmployeePromoted",
  "eventId": "evt_abc123",
  "timestamp": "2025-10-22T10:30:00Z",
  "aggregateId": "emp_123",
  "aggregateType": "Employee",
  "version": "1.0",
  "payload": {
    "employeeId": "emp_123",
    "employeeName": "John Doe",
    "previousPosition": "Senior Engineer",
    "newPosition": "Staff Engineer",
    "previousSalary": 50000,
    "newSalary": 60000,
    "effectiveDate": "2025-11-01",
    "promotedBy": "manager_456",
    "department": "Engineering",
    "reason": "Performance Excellence"
  },
  "metadata": {
    "source": "hr-event-publisher",
    "causationId": "cdc_xyz789",
    "correlationId": "promotion_process_999"
  }
}
```

### 3.2 Event Categories

#### Employee Lifecycle Events
| Event Type | Trigger | Business Meaning |
|------------|---------|------------------|
| `EmployeeHired` | INSERT into employees | New employee onboarding |
| `EmployeePromoted` | UPDATE position + salary | Career advancement |
| `EmployeeTerminated` | UPDATE status = 'terminated' | Employment ended |
| `EmployeeTransferred` | UPDATE department_id | Department change |
| `EmployeeDataUpdated` | Other UPDATE operations | Profile changes |

#### Organizational Events
| Event Type | Trigger | Business Meaning |
|------------|---------|------------------|
| `DepartmentCreated` | INSERT into departments | New org unit |
| `DepartmentRestructured` | UPDATE parent_dept_id | Org hierarchy change |
| `ManagerAssigned` | UPDATE manager_id | Leadership change |
| `TeamCompositionChanged` | Multiple employee transfers | Team reorganization |

#### Compensation Events
| Event Type | Trigger | Business Meaning |
|------------|---------|------------------|
| `SalaryAdjusted` | INSERT into salary_changes | Compensation change |
| `BonusAwarded` | INSERT into bonuses | Performance bonus |
| `StockGranted` | INSERT into stock_grants | Equity compensation |

#### Attendance Events
| Event Type | Trigger | Business Meaning |
|------------|---------|------------------|
| `LeaveRequested` | INSERT into leave_requests | PTO request |
| `LeaveApproved` | UPDATE status = 'approved' | PTO approval |
| `AttendanceMarked` | INSERT into attendance_records | Daily attendance |

### 3.3 Event Transformation Rules

**Rule 1: Promotion Detection**
```java
@Component
public class PromotionDetector implements EventTransformer {
    
    public Optional<DomainEvent> transform(CdcEvent cdcEvent) {
        if (cdcEvent.getTable().equals("employees") && 
            cdcEvent.getOperation().equals("UPDATE")) {
            
            Employee before = cdcEvent.getBefore();
            Employee after = cdcEvent.getAfter();
            
            if (positionChanged(before, after) && salaryIncreased(before, after)) {
                return Optional.of(createPromotionEvent(before, after));
            }
        }
        return Optional.empty();
    }
    
    private boolean positionChanged(Employee before, Employee after) {
        return !before.getPositionId().equals(after.getPositionId());
    }
    
    private boolean salaryIncreased(Employee before, Employee after) {
        return after.getSalary() > before.getSalary();
    }
}
```

**Rule 2: Termination Detection**
```java
@Component
public class TerminationDetector implements EventTransformer {
    
    public Optional<DomainEvent> transform(CdcEvent cdcEvent) {
        if (cdcEvent.getOperation().equals("UPDATE") &&
            "terminated".equals(cdcEvent.getAfter().getStatus())) {
            return Optional.of(createTerminationEvent(cdcEvent));
        }
        return Optional.empty();
    }
}
```

---

## 4. Implementation Details

### 4.1 Spring Boot Application Structure

```
hr-event-publisher/
├── src/main/java/com/company/hr/events/
│   ├── HrEventPublisherApplication.java
│   ├── config/
│   │   ├── NatsConfiguration.java
│   │   ├── ClickHouseConfiguration.java
│   │   └── StreamBindings.java
│   ├── listener/
│   │   ├── CdcEventListener.java
│   │   └── ExternalEventListener.java
│   ├── transformer/
│   │   ├── EventTransformer.java
│   │   ├── PromotionDetector.java
│   │   ├── TerminationDetector.java
│   │   └── TransferDetector.java
│   ├── publisher/
│   │   └── DomainEventPublisher.java
│   ├── service/
│   │   ├── EventEnrichmentService.java
│   │   └── EventValidationService.java
│   ├── repository/
│   │   ├── ClickHouseEventRepository.java
│   │   └── MariaDBReadRepository.java
│   ├── model/
│   │   ├── cdc/
│   │   │   └── CdcEvent.java
│   │   └── domain/
│   │       ├── EmployeeHiredEvent.java
│   │       ├── EmployeePromotedEvent.java
│   │       └── ...
│   └── util/
│       └── EventIdGenerator.java
├── src/main/resources/
│   ├── application.yml
│   └── logback-spring.xml
└── pom.xml
```

### 4.2 Maven Dependencies (pom.xml)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.2.0</version>
    </parent>
    
    <groupId>com.company.hr</groupId>
    <artifactId>hr-event-publisher</artifactId>
    <version>1.0.0</version>
    
    <properties>
        <java.version>17</java.version>
        <spring-cloud.version>2023.0.0</spring-cloud.version>
    </properties>
    
    <dependencies>
        <!-- Spring Boot -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        
        <!-- Spring Cloud Stream -->
        <dependency>
            <groupId>org.springframework.cloud</groupId>
            <artifactId>spring-cloud-stream</artifactId>
        </dependency>
        
        <!-- NATS -->
        <dependency>
            <groupId>io.nats</groupId>
            <artifactId>jnats</artifactId>
            <version>2.17.0</version>
        </dependency>
        <dependency>
            <groupId>io.nats</groupId>
            <artifactId>spring-nats</artifactId>
            <version>0.5.0</version>
        </dependency>
        
        <!-- ClickHouse -->
        <dependency>
            <groupId>com.clickhouse</groupId>
            <artifactId>clickhouse-jdbc</artifactId>
            <version>0.6.0</version>
        </dependency>
        
        <!-- MariaDB (for read queries if needed) -->
        <dependency>
            <groupId>org.mariadb.jdbc</groupId>
            <artifactId>mariadb-java-client</artifactId>
        </dependency>
        
        <!-- Jackson for JSON -->
        <dependency>
            <groupId>com.fasterxml.jackson.core</groupId>
            <artifactId>jackson-databind</artifactId>
        </dependency>
        
        <!-- Lombok -->
        <dependency>
            <groupId>org.projectlombok</groupId>
            <artifactId>lombok</artifactId>
            <optional>true</optional>
        </dependency>
        
        <!-- Monitoring -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <dependency>
            <groupId>io.micrometer</groupId>
            <artifactId>micrometer-registry-prometheus</artifactId>
        </dependency>
        
        <!-- Testing -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
```

### 4.3 Application Configuration (application.yml)

```yaml
spring:
  application:
    name: hr-event-publisher
  
  # NATS Configuration
  nats:
    server: nats://nats-server:4222
    connection-name: hr-event-publisher
    max-reconnects: 10
    reconnect-wait: 2s
    
  # ClickHouse Configuration
  datasource:
    clickhouse:
      url: jdbc:clickhouse://clickhouse:8123/hr_events
      username: ${CLICKHOUSE_USER}
      password: ${CLICKHOUSE_PASSWORD}
      driver-class-name: com.clickhouse.jdbc.ClickHouseDriver
  
  # Cloud Stream Bindings
  cloud:
    stream:
      bindings:
        # Input bindings
        cdc-employees-input:
          destination: cdc.hr.employees
          group: hr-event-publisher-group
          consumer:
            max-attempts: 3
        
        cdc-departments-input:
          destination: cdc.hr.departments
          group: hr-event-publisher-group
        
        cdc-salary-changes-input:
          destination: cdc.hr.salary_changes
          group: hr-event-publisher-group
        
        external-payroll-input:
          destination: hr.external.payroll.*
          group: hr-event-publisher-group
        
        # Output bindings
        domain-events-output:
          destination: events.hr.{eventType}
          producer:
            partition-key-expression: headers['aggregateId']

# Event Publisher Configuration
event-publisher:
  enable-enrichment: true
  enable-validation: true
  store-in-clickhouse: true
  
  # Transformation rules
  transformers:
    - type: promotion
      enabled: true
    - type: termination
      enabled: true
    - type: transfer
      enabled: true
    - type: hire
      enabled: true

# Monitoring
management:
  endpoints:
    web:
      exposure:
        include: health,prometheus,metrics
  metrics:
    export:
      prometheus:
        enabled: true
        
logging:
  level:
    com.company.hr.events: INFO
    io.nats: WARN
```

### 4.4 Core Service Implementation

#### Domain Event Publisher
```java
@Service
@Slf4j
public class DomainEventPublisher {
    
    private final NatsTemplate natsTemplate;
    private final ClickHouseEventRepository clickHouseRepository;
    private final MeterRegistry meterRegistry;
    
    @Autowired
    public DomainEventPublisher(
            NatsTemplate natsTemplate,
            ClickHouseEventRepository clickHouseRepository,
            MeterRegistry meterRegistry) {
        this.natsTemplate = natsTemplate;
        this.clickHouseRepository = clickHouseRepository;
        this.meterRegistry = meterRegistry;
    }
    
    @Transactional
    public void publish(DomainEvent event) {
        try {
            // Store in ClickHouse first
            clickHouseRepository.save(event);
            
            // Publish to NATS
            String subject = buildSubject(event);
            natsTemplate.convertAndSend(subject, event, headers -> {
                headers.set("eventId", event.getEventId());
                headers.set("eventType", event.getEventType());
                headers.set("aggregateId", event.getAggregateId());
                headers.set("version", event.getVersion());
                return headers;
            });
            
            log.info("Published event: {} for aggregate: {}", 
                    event.getEventType(), event.getAggregateId());
            
            // Metrics
            meterRegistry.counter("events.published", 
                    "type", event.getEventType()).increment();
            
        } catch (Exception e) {
            log.error("Failed to publish event: {}", event.getEventId(), e);
            meterRegistry.counter("events.failed", 
                    "type", event.getEventType()).increment();
            throw new EventPublishingException("Failed to publish event", e);
        }
    }
    
    private String buildSubject(DomainEvent event) {
        return String.format("events.hr.%s.%s", 
                event.getCategory().toLowerCase(), 
                event.getEventType().toLowerCase());
    }
}
```

#### Event Transformation Service
```java
@Service
@Slf4j
public class EventTransformationService {
    
    private final List<EventTransformer> transformers;
    private final EventEnrichmentService enrichmentService;
    private final EventValidationService validationService;
    
    @Autowired
    public EventTransformationService(
            List<EventTransformer> transformers,
            EventEnrichmentService enrichmentService,
            EventValidationService validationService) {
        this.transformers = transformers;
        this.enrichmentService = enrichmentService;
        this.validationService = validationService;
    }
    
    public List<DomainEvent> transform(CdcEvent cdcEvent) {
        List<DomainEvent> domainEvents = new ArrayList<>();
        
        for (EventTransformer transformer : transformers) {
            Optional<DomainEvent> eventOpt = transformer.transform(cdcEvent);
            
            if (eventOpt.isPresent()) {
                DomainEvent event = eventOpt.get();
                
                // Enrich
                event = enrichmentService.enrich(event);
                
                // Validate
                validationService.validate(event);
                
                domainEvents.add(event);
                log.debug("Transformed CDC event to: {}", event.getEventType());
            }
        }
        
        return domainEvents;
    }
}
```

#### Employee Promotion Transformer
```java
@Component
@Slf4j
public class PromotionTransformer implements EventTransformer {
    
    private final MariaDBReadRepository readRepository;
    
    @Override
    public Optional<DomainEvent> transform(CdcEvent cdcEvent) {
        if (!isPromotionEvent(cdcEvent)) {
            return Optional.empty();
        }
        
        Employee before = cdcEvent.getBefore(Employee.class);
        Employee after = cdcEvent.getAfter(Employee.class);
        
        // Fetch additional context
        Position previousPos = readRepository.findPositionById(before.getPositionId());
        Position newPos = readRepository.findPositionById(after.getPositionId());
        
        EmployeePromotedEvent event = EmployeePromotedEvent.builder()
                .eventId(UUID.randomUUID().toString())
                .timestamp(Instant.now())
                .aggregateId(after.getId())
                .aggregateType("Employee")
                .version("1.0")
                .employeeId(after.getId())
                .employeeName(after.getFullName())
                .previousPosition(previousPos.getTitle())
                .newPosition(newPos.getTitle())
                .previousSalary(before.getSalary())
                .newSalary(after.getSalary())
                .effectiveDate(after.getUpdatedAt().toLocalDate())
                .department(after.getDepartmentName())
                .build();
        
        return Optional.of(event);
    }
    
    private boolean isPromotionEvent(CdcEvent cdcEvent) {
        if (!cdcEvent.getTable().equals("employees") || 
            !cdcEvent.getOperation().equals("UPDATE")) {
            return false;
        }
        
        Employee before = cdcEvent.getBefore(Employee.class);
        Employee after = cdcEvent.getAfter(Employee.class);
        
        return !before.getPositionId().equals(after.getPositionId()) &&
               after.getSalary() > before.getSalary();
    }
}
```

---

## 5. Deployment Architecture

### 5.1 Docker Compose Setup

```yaml
version: '3.8'

services:
  mariadb:
    image: mariadb:10.6.19
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: hr_db
    volumes:
      - mariadb-data:/var/lib/mysql
      - ./init-scripts:/docker-entrypoint-initdb.d
    ports:
      - "3306:3306"
    command: --log-bin --binlog-format=ROW --server-id=1

  debezium:
    image: debezium/server:2.7
    depends_on:
      - mariadb
      - nats
    environment:
      DEBEZIUM_SINK_TYPE: nats
      DEBEZIUM_SINK_NATS_URL: nats://nats:4222
      DEBEZIUM_SOURCE_CONNECTOR_CLASS: io.debezium.connector.mysql.MySqlConnector
      DEBEZIUM_SOURCE_DATABASE_HOSTNAME: mariadb
      DEBEZIUM_SOURCE_DATABASE_PORT: 3306
      DEBEZIUM_SOURCE_DATABASE_USER: debezium
      DEBEZIUM_SOURCE_DATABASE_PASSWORD: ${DEBEZIUM_PASSWORD}
    volumes:
      - ./debezium-config:/debezium/conf
      - debezium-data:/debezium/data

  nats:
    image: nats:2.10-alpine
    ports:
      - "4222:4222"
      - "8222:8222"
    command: 
      - "--jetstream"
      - "--store_dir=/data"
      - "--http_port=8222"
    volumes:
      - nats-data:/data

  hr-event-publisher:
    build: .
    depends_on:
      - nats
      - clickhouse
      - mariadb
    environment:
      SPRING_PROFILES_ACTIVE: production
      NATS_SERVER: nats://nats:4222
      CLICKHOUSE_URL: jdbc:clickhouse://clickhouse:8123/hr_events
      MARIADB_URL: jdbc:mariadb://mariadb:3306/hr_db
    ports:
      - "8080:8080"
    volumes:
      - ./logs:/app/logs

  clickhouse:
    image: clickhouse/clickhouse-server:24.10
    ports:
      - "8123:8123"
      - "9000:9000"
    volumes:
      - clickhouse-data:/var/lib/clickhouse
      - ./clickhouse-init:/docker-entrypoint-initdb.d
    environment:
      CLICKHOUSE_DB: hr_events
      CLICKHOUSE_USER: ${CLICKHOUSE_USER}
      CLICKHOUSE_PASSWORD: ${CLICKHOUSE_PASSWORD}

volumes:
  mariadb-data:
  debezium-data:
  nats-data:
  clickhouse-data:
```

### 5.2 Kubernetes Deployment (Optional)

For production environments, deploy using Kubernetes with:
- Horizontal Pod Autoscaling for the Spring Boot service
- StatefulSets for NATS JetStream, MariaDB, ClickHouse
- ConfigMaps for configuration
- Secrets for sensitive data
- Prometheus + Grafana for monitoring

---

## 6. Monitoring & Observability

### 6.1 Metrics

**Application Metrics**:
- `events.published.total` - Counter of published events by type
- `events.failed.total` - Counter of failed events by type
- `events.transformation.duration` - Histogram of transformation time
- `events.enrichment.duration` - Histogram of enrichment time
- `nats.publish.duration` - Histogram of publish latency
- `clickhouse.write.duration` - Histogram of storage latency

**NATS Metrics**:
- Message throughput
- Consumer lag
- Connection status

**Debezium Metrics**:
- Binlog position
- CDC lag
- Snapshot progress

### 6.2 Health Checks

```java
@Component
public class NatsHealthIndicator implements HealthIndicator {
    
    private final Connection natsConnection;
    
    @Override
    public Health health() {
        if (natsConnection.getStatus() == Connection.Status.CONNECTED) {
            return Health.up()
                    .withDetail("server", natsConnection.getConnectedUrl())
                    .build();
        }
        return Health.down()
                .withDetail("status", natsConnection.getStatus())
                .build();
    }
}
```

### 6.3 Logging

Use structured logging with correlation IDs:
```java
MDC.put("eventId", event.getEventId());
MDC.put("aggregateId", event.getAggregateId());
log.info("Processing event: {}", event.getEventType());
```

---

## 7. Testing Strategy

### 7.1 Unit Tests
- Test each transformer independently
- Mock CDC events
- Verify domain event structure

### 7.2 Integration Tests
- Test NATS pub/sub
- Test ClickHouse writes
- Test end-to-end flow

### 7.3 Contract Tests
- Define event schemas
- Validate against schema registry
- Test consumer compatibility

---

## 8. Security Considerations

1. **Authentication**: Use NATS authentication tokens
2. **Encryption**: Enable TLS for NATS connections
3. **Data Masking**: Mask PII in events (SSN, etc.)
4. **Audit Trail**: Log all event publications
5. **Access Control**: Limit who can subscribe to sensitive subjects

---

## 9. Scalability & Performance

### 9.1 Scaling Strategies
- **Horizontal Scaling**: Run multiple instances of Spring Boot service
- **Consumer Groups**: Use NATS consumer groups for load distribution
- **Partitioning**: Partition by employee ID or department

### 9.2 Performance Optimization
- **Batch Processing**: Accumulate events and publish in batches
- **Async Processing**: Use @Async for non-critical operations
- **Connection Pooling**: Pool database and NATS connections
- **Caching**: Cache frequently accessed reference data

---

## 10. Migration Plan

### Phase 1: Setup Infrastructure
1. Deploy MariaDB with binlog enabled
2. Deploy NATS server
3. Deploy Debezium Server
4. Deploy ClickHouse

### Phase 2: Deploy Publisher Service
1. Deploy with limited transformers (hire, termination only)
2. Monitor for 1 week
3. Validate event quality

### Phase 3: Add Consumers
1. Onboard first consumer (notification service)
2. Monitor event delivery
3. Tune performance

### Phase 4: Full Rollout
1. Enable all transformers
2. Onboard remaining consumers
3. Decommission Kafka (if applicable)

---

## 11. References

- [Debezium Documentation](https://debezium.io/documentation/)
- [NATS JetStream](https://docs.nats.io/nats-concepts/jetstream)
- [Spring Cloud Stream](https://spring.io/projects/spring-cloud-stream)
- [ClickHouse Documentation](https://clickhouse.com/docs)
- [DingTalk Event Subscription](https://open.dingtalk.com/document/development/event-subscription-overview)

---

## Appendix A: Event Schema Examples

### A.1 EmployeeHiredEvent Schema
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "eventId": {"type": "string", "format": "uuid"},
    "eventType": {"type": "string", "const": "EmployeeHired"},
    "timestamp": {"type": "string", "format": "date-time"},
    "aggregateId": {"type": "string"},
    "aggregateType": {"type": "string", "const": "Employee"},
    "version": {"type": "string"},
    "payload": {
      "type": "object",
      "properties": {
        "employeeId": {"type": "string"},
        "firstName": {"type": "string"},
        "lastName": {"type": "string"},
        "email": {"type": "string", "format": "email"},
        "hireDate": {"type": "string", "format": "date"},
        "position": {"type": "string"},
        "department": {"type": "string"},
        "salary": {"type": "number"},
        "manager": {"type": "string"}
      },
      "required": ["employeeId", "firstName", "lastName", "email", "hireDate"]
    }
  },
  "required": ["eventId", "eventType", "timestamp", "aggregateId", "payload"]
}
```

---

## Document Version
- Version: 1.0
- Last Updated: 2025-10-22
- Author: System Design Team
