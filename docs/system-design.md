# HR Event Publisher System - System Design Document

**Version:** 1.0  
**Date:** October 22, 2025  
**Status:** Design Phase

---

## 1. Executive Summary

### 1.1 Purpose
Design an event-driven system that captures HR data changes and publishes business-level domain events to internal consumers using NATS message broker, replacing Kafka infrastructure.

### 1.2 Key Objectives
- Capture real-time data changes from MariaDB using CDC (Debezium)
- Transform low-level database changes into meaningful business events
- Support dual input sources: CDC and external NATS subjects
- Provide reliable event delivery through NATS
- Enable historical analytics via ClickHouse storage
- Use only open-source components

### 1.3 Scope
**In Scope:**
- CDC from MariaDB HR database
- Event transformation to business domain events
- NATS-based event distribution
- Event persistence in ClickHouse
- Monitoring and observability

**Out of Scope:**
- Consumer applications (notification, analytics services)
- User interface or management console
- Historical data migration
- Authentication/authorization system

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Data Sources Layer                        │
├─────────────────────┬───────────────────────────────────────────┤
│  MariaDB 10.6.19    │     Upstream NATS Subjects                │
│  (HR Database)      │     (External HR Systems)                 │
└──────────┬──────────┴────────────────┬──────────────────────────┘
           │                           │
           │ Binlog                    │ External Events
           │                           │
           ▼                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                         CDC Layer                                │
│                    Debezium Server 3.0                           │
│            (MySQL Connector → NATS Sink)                         │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               │ CDC Events
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Message Broker Layer                          │
│                      NATS with JetStream                         │
│  Subjects: cdc.hr.*, hr.external.*, events.hr.*                 │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               │ Subscribe
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Event Processing Layer                         │
│              Spring Boot Event Publisher Service                 │
│  • CDC Event Listeners                                           │
│  • Business Rule Transformers                                    │
│  • Event Enrichment & Validation                                 │
│  • Domain Event Publishing                                       │
└──────────────┬───────────────────────────────┬──────────────────┘
               │                               │
               │ Store                         │ Publish
               ▼                               ▼
┌──────────────────────────┐    ┌─────────────────────────────────┐
│   Storage Layer          │    │    Output Layer                 │
│  ClickHouse 24.10        │    │    NATS Subjects                │
│  • Event Log             │    │    • events.hr.employee.*       │
│  • Audit Trail           │    │    • events.hr.org.*            │
│  • Analytics Tables      │    │    • events.hr.compensation.*   │
└──────────────────────────┘    └────────────┬────────────────────┘
                                             │
                                             │ Subscribe
                                             ▼
                                ┌──────────────────────────┐
                                │   Consumer Services      │
                                │   • Notification         │
                                │   • Analytics            │
                                │   • Integration          │
                                │   • Audit                │
                                └──────────────────────────┘
```

### 2.2 Component Descriptions

#### 2.2.1 Data Sources
**MariaDB 10.6.19**
- Primary HR transactional database
- Tables: employees, departments, positions, salary_changes, leave_requests, attendance_records
- Binary logging enabled for CDC capture

**Upstream NATS Subjects**
- Receives events from external HR systems (payroll, time tracking, benefits)
- Subjects: `hr.external.payroll.*`, `hr.external.timeclock.*`

#### 2.2.2 CDC Layer - Debezium Server
- Captures MariaDB binlog changes in real-time
- Uses MySQL connector for MariaDB compatibility
- Outputs directly to NATS (no Kafka dependency)
- Publishes to subjects: `cdc.hr.{tableName}`

#### 2.2.3 Message Broker - NATS
- Lightweight, high-performance message broker
- JetStream for persistence and guaranteed delivery
- Subject-based routing with wildcards
- Consumer groups for horizontal scaling

#### 2.2.4 Event Processing - Spring Boot Service
- Subscribes to CDC and external event subjects
- Applies business logic to identify domain events
- Enriches events with contextual data
- Validates and publishes to output subjects
- Persists events to ClickHouse

#### 2.2.5 Storage - ClickHouse
- Columnar database optimized for analytics
- Stores complete event history
- Provides audit trail and compliance reporting
- Materialized views for real-time aggregations

---

## 3. Event Design

### 3.1 Event Granularity Strategy

**Philosophy:** Publish business-meaningful events, not raw database changes.

**Transformation Example:**
```
CDC Event (Low-level):
- Table: employees
- Operation: UPDATE
- Changes: position_id: IC3 → IC5, salary: 120000 → 180000

Domain Event (Business-level):
- Event: EmployeePromoted
- Semantics: Employee advanced from Senior to Staff Engineer
- Context: Includes promotion reason, approver, effective date
```

### 3.2 Event Categories

#### Employee Lifecycle Events
| Event Type | Business Trigger | Subject |
|------------|------------------|---------|
| EmployeeHired | New employee record | events.hr.employee.hired |
| EmployeePromoted | Position + salary increase | events.hr.employee.promoted |
| EmployeeTerminated | Status changed to terminated | events.hr.employee.terminated |
| EmployeeTransferred | Department change | events.hr.employee.transferred |

#### Organizational Events
| Event Type | Business Trigger | Subject |
|------------|------------------|---------|
| DepartmentCreated | New department | events.hr.org.department.created |
| DepartmentRestructured | Hierarchy change | events.hr.org.department.restructured |
| ManagerAssigned | Manager relationship change | events.hr.org.manager.assigned |

#### Compensation Events
| Event Type | Business Trigger | Subject |
|------------|------------------|---------|
| SalaryAdjusted | Salary change | events.hr.compensation.salary.adjusted |
| BonusAwarded | Bonus record | events.hr.compensation.bonus.awarded |

#### Attendance Events
| Event Type | Business Trigger | Subject |
|------------|------------------|---------|
| LeaveRequested | Leave request submitted | events.hr.attendance.leave.requested |
| LeaveApproved | Leave status approved | events.hr.attendance.leave.approved |
| AttendanceMarked | Daily attendance record | events.hr.attendance.marked |

### 3.3 Event Structure

**Standard Event Envelope:**
```json
{
  "eventId": "uuid",
  "eventType": "EmployeePromoted",
  "eventCategory": "employee",
  "timestamp": "ISO-8601",
  "aggregateId": "employee-id",
  "aggregateType": "Employee",
  "version": "1.0",
  "payload": {
    // Event-specific business data
  },
  "metadata": {
    "source": "hr-event-publisher",
    "causationId": "upstream-event-id",
    "correlationId": "business-process-id",
    "userId": "acting-user-id"
  }
}
```

### 3.4 Event Transformation Rules

**Rule: Promotion Detection**
- **Triggers:** position_id changes AND salary increases AND status = 'active'
- **Enrichment:** Fetch position titles, department names, manager info
- **Output:** EmployeePromoted event

**Rule: Termination Detection**
- **Triggers:** status changes from 'active' to 'terminated'
- **Enrichment:** Calculate tenure, fetch termination details
- **Output:** EmployeeTerminated event

**Rule: Transfer Detection**
- **Triggers:** department_id changes AND position_id unchanged
- **Enrichment:** Fetch department names, calculate org distance
- **Output:** EmployeeTransferred event

---

## 4. Data Flow

### 4.1 Primary Flow (CDC-Driven)

1. **Change Occurs:** DBA or application updates MariaDB
2. **Binlog Capture:** Debezium reads binlog entry
3. **CDC Event:** Debezium publishes to `cdc.hr.employees`
4. **Event Receipt:** Spring Boot service receives CDC event
5. **Transformation:** Service applies business rules, detects EmployeePromoted
6. **Enrichment:** Service queries additional context from MariaDB
7. **Validation:** Service validates event structure and business rules
8. **Persistence:** Service stores event in ClickHouse
9. **Publishing:** Service publishes to `events.hr.employee.promoted`
10. **Consumption:** Downstream services receive and process event

### 4.2 Secondary Flow (External Events)

1. **External System:** Payroll system publishes salary update
2. **NATS Subject:** Event arrives at `hr.external.payroll.salary-update`
3. **Event Receipt:** Spring Boot service receives external event
4. **Transformation:** Service converts to internal domain event
5. **Publishing:** Service publishes to appropriate subject

### 4.3 Message Routing

**NATS Subject Hierarchy:**
```
Input Subjects:
├── cdc.hr.employees
├── cdc.hr.departments
├── cdc.hr.salary_changes
├── hr.external.payroll.*
└── hr.external.timeclock.*

Output Subjects:
├── events.hr.employee.*
│   ├── events.hr.employee.hired
│   ├── events.hr.employee.promoted
│   └── events.hr.employee.terminated
├── events.hr.org.*
│   ├── events.hr.org.department.created
│   └── events.hr.org.manager.assigned
└── events.hr.compensation.*
    ├── events.hr.compensation.salary.adjusted
    └── events.hr.compensation.bonus.awarded
```

---

## 5. Technology Stack

### 5.1 Component Selection Rationale

| Component | Version | Purpose | Why Selected |
|-----------|---------|---------|--------------|
| MariaDB | 10.6.19 | Source database | Given requirement, MySQL-compatible |
| Debezium Server | 3.3+ | CDC capture | Industry standard, NATS sink support |
| NATS | 2.10+ | Message broker | Lightweight, high-performance, replaces Kafka |
| Spring Boot | 3.2+ | Event processor | Mature ecosystem, enterprise-ready |
| ClickHouse | 24.10 | Analytics store | Columnar storage, excellent for time-series |

**All components are open-source** ✓

### 5.2 NATS vs Kafka Comparison

| Feature | NATS | Kafka | Decision |
|---------|------|-------|----------|
| Complexity | Low | High | NATS simpler to operate |
| Latency | Sub-ms | 5-10ms | NATS faster for real-time |
| Persistence | JetStream | Native | Both adequate |
| Resource usage | Minimal | Heavy | NATS more efficient |
| Subject routing | Native | Topic-based | NATS more flexible |
| Operational cost | Low | High | NATS reduces overhead |

**Decision:** NATS provides sufficient capabilities with significantly lower operational complexity.

---

## 6. Scalability & Performance

### 6.1 Scalability Strategy

**Horizontal Scaling:**
- Spring Boot service: Scale to N instances behind NATS consumer groups
- NATS: Clustered deployment for high availability
- ClickHouse: Sharding by event date or department

**Vertical Scaling:**
- Debezium: Tune connector parallelism
- NATS: Increase connection limits
- ClickHouse: Optimize query performance with indexes

### 6.2 Performance Targets

| Metric | Target | Rationale |
|--------|--------|-----------|
| CDC Lag | < 1 second | Near real-time event delivery |
| Event Processing | < 100ms | Fast business logic execution |
| End-to-end Latency | < 2 seconds | From DB change to consumer receipt |
| Throughput | 10,000 events/sec | Peak HR activity (payroll runs) |
| Event Storage | 5 years retention | Compliance requirements |

### 6.3 Capacity Planning

**Estimated Event Volume:**
- Daily employee changes: ~1,000 events
- Attendance records: ~50,000 events (if tracked per employee)
- Leave requests: ~500 events
- Organizational changes: ~100 events

**Storage Requirements:**
- ClickHouse: ~10GB/month (compressed)
- NATS JetStream: ~1GB (7-day retention)
- Debezium offsets: Negligible

---

## 7. Reliability & Fault Tolerance

### 7.1 Failure Scenarios

**Scenario 1: Debezium Failure**
- Impact: CDC events stop flowing
- Detection: Monitor binlog position lag
- Recovery: Debezium resumes from last checkpoint
- Data Loss: None (binlog retention ensures recovery)

**Scenario 2: NATS Outage**
- Impact: Event delivery paused
- Detection: Health check failures
- Recovery: Automatic reconnection, JetStream replay
- Data Loss: None (JetStream persistence)

**Scenario 3: Spring Boot Crash**
- Impact: Processing temporarily halted
- Detection: Kubernetes liveness probe
- Recovery: Auto-restart, consumer resubscription
- Data Loss: At-most-once semantics (events reprocessed on restart)

**Scenario 4: ClickHouse Unavailable**
- Impact: Event storage fails, publishing continues
- Detection: Write failures logged
- Recovery: Retry mechanism with exponential backoff
- Data Loss: Potential (implement dead-letter queue)

### 7.2 Reliability Mechanisms

**CDC Reliability:**
- Debezium tracks binlog position persistently
- Exactly-once semantics from database to NATS

**Message Delivery:**
- NATS JetStream provides at-least-once delivery
- Consumer acknowledgments prevent message loss

**Processing Guarantees:**
- Idempotency keys in events (eventId)
- Consumers implement idempotent processing

**Data Durability:**
- ClickHouse replication (3 replicas recommended)
- Regular snapshots and backups

### 7.3 Monitoring & Alerting

**Key Metrics:**
- CDC lag: Alert if > 10 seconds
- Event processing rate: Alert if drops > 50%
- NATS connection status: Alert on disconnect
- ClickHouse write latency: Alert if > 1 second
- Dead letter queue depth: Alert if > 100 messages

**Health Checks:**
- Debezium: Binlog position advancing
- NATS: Connection status and subject availability
- Spring Boot: Actuator health endpoint
- ClickHouse: Query response time

---

## 8. Security Considerations

### 8.1 Data Protection

**At Rest:**
- ClickHouse: Encryption-at-rest for sensitive columns
- Debezium offsets: File system permissions

**In Transit:**
- NATS: TLS encryption for production
- ClickHouse: SSL/TLS connections
- MariaDB: Encrypted binlog connections

**Data Masking:**
- PII fields (SSN, bank accounts) masked in events
- Salary information restricted by subject ACL

### 8.2 Access Control

**NATS Subject ACLs:**
- Publishers: Only event-publisher service can publish to `events.hr.*`
- Subscribers: Role-based access to event categories
- Example: HR systems access all, managers access only their department

**Database Access:**
- Debezium: Read-only binlog access
- Spring Boot: Read-only access for enrichment queries
- ClickHouse: Write access for event-publisher, read for analytics

### 8.3 Audit & Compliance

**Audit Trail:**
- All events stored with metadata (userId, timestamp)
- ClickHouse audit_trail table tracks field-level changes
- Event replay capability for compliance investigations

**Data Retention:**
- Events: 5 years (legal requirement)
- CDC logs: 7 days (operational)
- Audit trail: 7 years (compliance)

---

## 9. Deployment Architecture

### 9.1 Infrastructure Topology

**Development Environment:**
- Docker Compose on single host
- All services co-located
- Shared networks

**Production Environment:**
```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
├──────────────────┬──────────────────┬───────────────────┤
│   Namespace:     │   Namespace:     │   Namespace:      │
│   hr-data        │   hr-messaging   │   hr-processing   │
├──────────────────┼──────────────────┼───────────────────┤
│ • MariaDB        │ • NATS Cluster   │ • Event Publisher │
│   (StatefulSet)  │   (StatefulSet)  │   (Deployment)    │
│                  │   - 3 nodes      │   - 3+ replicas   │
│ • Debezium       │                  │                   │
│   (Deployment)   │                  │                   │
├──────────────────┴──────────────────┴───────────────────┤
│                    Namespace: hr-analytics               │
│                  • ClickHouse Cluster                    │
│                    (StatefulSet - 3 replicas)            │
└──────────────────────────────────────────────────────────┘
```

### 9.2 High Availability Configuration

**MariaDB:**
- Primary-replica setup with automatic failover
- Binlog replication to standby

**NATS:**
- 3-node cluster with JetStream
- Raft consensus for stream leadership

**Spring Boot:**
- 3+ instances behind service load balancer
- Consumer groups distribute load

**ClickHouse:**
- 3-replica cluster with distributed tables
- ZooKeeper for coordination

### 9.3 Disaster Recovery

**Backup Strategy:**
- MariaDB: Daily full backups, continuous binlog shipping
- ClickHouse: Daily snapshots to object storage
- NATS: JetStream backups for critical streams

**Recovery Time Objective (RTO):** 1 hour  
**Recovery Point Objective (RPO):** 5 minutes

**Failover Procedures:**
1. Detect primary failure (automated monitoring)
2. Promote replica to primary
3. Update DNS/service endpoints
4. Resume event processing from last checkpoint

---

## 10. Testing Strategy

### 10.1 Test Levels

**Unit Tests:**
- Transformer logic (promotion detection, etc.)
- Event validation rules
- Data enrichment functions

**Integration Tests:**
- CDC pipeline: MariaDB → Debezium → NATS
- Event processing: NATS → Spring Boot → ClickHouse
- End-to-end: Database change → Consumer receipt

**Performance Tests:**
- Load testing: 10,000 events/sec sustained
- Latency testing: End-to-end < 2 seconds
- Stress testing: Recovery from backlog

**Chaos Tests:**
- Kill Debezium during processing
- Network partition between NATS and consumers
- ClickHouse unavailability

### 10.2 Test Scenarios

**Scenario 1: Employee Promotion**
- Input: Update position_id and salary
- Expected: EmployeePromoted event published
- Verification: Event in ClickHouse, NATS subject

**Scenario 2: Bulk Salary Adjustment**
- Input: 1,000 salary updates
- Expected: 1,000 SalaryAdjusted events
- Verification: All events delivered, no duplicates

**Scenario 3: System Recovery**
- Input: Kill Spring Boot during processing
- Expected: Events reprocessed on restart
- Verification: Idempotent handling, no data loss

---

## 11. Migration & Rollout Plan

### 11.1 Phase 1: Infrastructure Setup (Week 1-2)
- Deploy MariaDB with binlog enabled
- Deploy NATS cluster
- Deploy Debezium Server
- Deploy ClickHouse cluster
- Verify connectivity and health checks

### 11.2 Phase 2: Event Publisher Deployment (Week 3-4)
- Deploy Spring Boot service with basic transformers
- Enable only critical events: EmployeeHired, EmployeeTerminated
- Monitor for 1 week
- Validate event quality and completeness

### 11.3 Phase 3: Consumer Onboarding (Week 5-6)
- Onboard first consumer: Notification service
- Monitor event delivery and processing
- Tune performance based on actual load
- Collect feedback from consumer teams

### 11.4 Phase 4: Full Rollout (Week 7-8)
- Enable all event transformers
- Onboard remaining consumers
- Migrate from Kafka (if applicable)
- Declare production-ready

### 11.5 Rollback Plan
- Maintain Kafka infrastructure during migration (if applicable)
- Feature flags to disable specific transformers
- Database snapshots before schema changes
- NATS subject versioning for breaking changes

---

## 12. Operations & Maintenance

### 12.1 Operational Runbooks

**Daily Operations:**
- Monitor CDC lag dashboard
- Check event processing metrics
- Review error logs for anomalies

**Weekly Operations:**
- Analyze event volume trends
- Review consumer feedback
- Optimize slow transformers

**Monthly Operations:**
- ClickHouse table optimization
- Review and adjust retention policies
- Capacity planning review

### 12.2 Common Incidents

**Incident: High CDC Lag**
- Cause: Large batch updates in MariaDB
- Resolution: Increase Debezium parallelism
- Prevention: Schedule batch updates during off-hours

**Incident: Event Processing Backlog**
- Cause: Slow ClickHouse writes
- Resolution: Scale Spring Boot replicas, optimize queries
- Prevention: Pre-warm ClickHouse caches

**Incident: Duplicate Events**
- Cause: Consumer restart without checkpoint
- Resolution: Consumers implement idempotency
- Prevention: Regular consumer health checks

### 12.3 Upgrade Strategy

**Zero-Downtime Upgrades:**
- Rolling updates for Spring Boot (blue-green deployment)
- NATS cluster rolling restart
- ClickHouse replica upgrades one at a time

**Schema Evolution:**
- Event versioning (v1.0, v1.1, v2.0)
- Backward-compatible changes first
- Consumer coordination for breaking changes

---

## 13. Cost Analysis

### 13.1 Infrastructure Costs (Monthly Estimate)

| Component | Resources | Estimated Cost |
|-----------|-----------|----------------|
| MariaDB | 16 vCPU, 64GB RAM | $400 |
| NATS Cluster | 12 vCPU, 24GB RAM | $250 |
| Spring Boot (3x) | 12 vCPU, 24GB RAM | $250 |
| ClickHouse (3x) | 24 vCPU, 96GB RAM | $800 |
| Storage | 1TB SSD | $100 |
| Networking | Data transfer | $50 |
| **Total** | | **~$1,850/month** |

### 13.2 Operational Costs

- Personnel: 1 DevOps engineer (20% time) = $30k/year
- Monitoring tools: $100/month
- Backup storage: $50/month

### 13.3 Cost Optimization

- Use spot instances for non-critical environments
- Implement data lifecycle policies (archive old events)
- Right-size based on actual usage metrics

---

## 14. Success Metrics

### 14.1 Technical KPIs

- **Event Delivery Latency:** < 2 seconds (P95)
- **System Availability:** 99.9% uptime
- **Data Loss:** 0 events lost
- **Processing Throughput:** 10,000 events/sec sustained

### 14.2 Business KPIs

- **Consumer Adoption:** 5+ internal services integrated
- **Event Coverage:** 100% of critical HR processes
- **Audit Compliance:** 100% event traceability
- **Operational Efficiency:** 50% reduction in manual data sync

### 14.3 Success Criteria

**Go-Live Criteria:**
- All health checks passing for 7 consecutive days
- Zero data loss in production testing
- At least 2 consumers successfully integrated
- Runbooks documented and validated

**Post-Launch (30 days):**
- Average latency < 2 seconds maintained
- No critical incidents
- Positive feedback from consumer teams
- Performance within capacity projections

---

## 15. Future Enhancements

### 15.1 Short-term (3-6 months)

- **Event Replay:** UI for replaying events for consumers
- **Schema Registry:** Centralized event schema management
- **Advanced Monitoring:** Custom Grafana dashboards
- **Multi-region:** Geo-replicated NATS and ClickHouse

### 15.2 Long-term (6-12 months)

- **ML Integration:** Anomaly detection on event patterns
- **Event Sourcing:** Complete state reconstruction from events
- **API Gateway:** REST/GraphQL interface for event queries
- **Data Mesh:** Federated event domains across organization

### 15.3 Scalability Roadmap

- **Current:** Single datacenter, 10k events/sec
- **Phase 2:** Multi-region, 50k events/sec
- **Phase 3:** Global deployment, 100k+ events/sec

---

## 16. Appendices

### 16.1 Glossary

- **CDC:** Change Data Capture - technique to track database changes
- **Domain Event:** Business-meaningful event (vs. technical database change)
- **JetStream:** NATS persistence layer for guaranteed delivery
- **Aggregate:** Business entity (e.g., Employee, Department)
- **Transformer:** Component that converts CDC to domain events

### 16.2 References

- [Debezium Documentation](https://debezium.io/documentation/)
- [NATS JetStream](https://docs.nats.io/nats-concepts/jetstream)
- [Event-Driven Architecture Patterns](https://martinfowler.com/articles/201701-event-driven.html)
- [Domain-Driven Design](https://www.domainlanguage.com/ddd/)

### 16.3 Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-10-22 | Use NATS instead of Kafka | Simpler operations, lower cost |
| 2025-10-22 | Business-level event granularity | Better consumer experience |
| 2025-10-22 | ClickHouse for analytics | Optimized for time-series queries |
| 2025-10-22 | Spring Boot for processing | Team expertise, mature ecosystem |

---

**Document Control**
- **Author:** System Architecture Team
- **Reviewers:** Engineering, DevOps, Security teams
- **Approval:** CTO
- **Next Review:** Q1 2026
