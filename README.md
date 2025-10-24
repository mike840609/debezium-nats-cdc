# HR Event Publisher - CDC Pipeline

A Change Data Capture (CDC) pipeline for HR systems using Debezium, NATS JetStream, and MariaDB.

## 📋 Overview

This project implements a CDC pipeline that captures database changes from MariaDB and publishes them as events to NATS JetStream. It's designed for HR event tracking and can be extended with business logic processors.

## 🏗️ Architecture

- **MariaDB** - Source database with HR data (employees, departments, positions, etc.)
- **Debezium** - CDC connector that reads MariaDB binlog
- **NATS JetStream** - Event streaming platform for distributing CDC events
- **Docker Compose** - Infrastructure orchestration

## 📁 Project Structure

```
.
├── Makefile                    # Common operations (start, stop, test, clean)
├── docker-compose.yml          # Service definitions
├── config/                     # All configurations
│   ├── mariadb/
│   │   └── my.cnf             # MariaDB configuration
│   ├── debezium/
│   │   └── application.properties  # Debezium connector config
│   └── nats/
│       └── stream.json        # NATS JetStream configuration
├── scripts/                    # Executable scripts
│   ├── quickstart.sh          # Quick start script
│   └── test-cdc.sh            # CDC pipeline test script
├── sql/                        # SQL scripts
│   └── init-db.sql            # Database schema and sample data
└── docs/                       # Documentation
    ├── architecture.svg        # Architecture diagram
    ├── sequence-diagrams.svg   # Sequence diagrams
    ├── design.md              # Design document
    ├── system-design.md       # System design details
    └── cdc-guide.md           # CDC implementation guide
```

## 🚀 Quick Start

### Prerequisites

- Docker & Docker Compose
- 4GB RAM minimum
- 10GB disk space

### Option 1: Using Makefile (Recommended)

```bash
# Start all services with full initialization
make start

# Run CDC tests
make test

# Check service status
make status

# View logs
make logs

# Stop services
make stop

# Clean up everything (including volumes)
make clean
```

### Option 2: Using Scripts Directly

```bash
# Start services and initialize
./scripts/quickstart.sh

# Test the CDC pipeline
./scripts/test-cdc.sh
```

### Option 3: Manual Setup

```bash
# Start services
docker-compose up -d

# Wait for services to be healthy
sleep 30

# Initialize NATS stream and database
make init
```

## 📊 Service Endpoints

| Service  | Endpoint                    | Description            |
|----------|-----------------------------|------------------------|
| MariaDB  | `localhost:3306`            | Database server        |
| NATS     | `localhost:4222`            | NATS client port       |
| NATS UI  | `http://localhost:8222`     | NATS monitoring        |

### Database Access

```bash
# Connect to MariaDB
docker exec -it hr-mariadb mysql -uhruser -phrpass hrdb

# Credentials
# - Database: hrdb
# - User: hruser / hrpass
# - Root: root / rootpass
```

### NATS Event Topics

Events are published to NATS with the pattern: `HCM.CDC.HR.<database>.<table>`

Examples:
- `HCM.CDC.HR.hrdb.employees` - Employee changes
- `HCM.CDC.HR.hrdb.departments` - Department changes
- `HCM.CDC.HR.hrdb.salary_changes` - Salary change records

## 🧪 Testing

The test script performs CRUD operations and verifies CDC events:

```bash
# Run tests
make test
# or
./scripts/test-cdc.sh
```

Test operations:
1. Insert employee (EMP999 - Test User)
2. Update salary (90000 → 95000)
3. Record salary change
4. Create leave request
5. Delete test data

### Monitor Events

Using NATS CLI:
```bash
# Subscribe to all HR events
nats sub 'HCM.CDC.HR.>' --server localhost:4222

# Subscribe to specific table
nats sub 'HCM.CDC.HR.hrdb.employees' --server localhost:4222
```

Using Docker:
```bash
docker run --rm -it --network bizeventhub-p2_hr-network \
  natsio/nats-box:latest \
  nats sub 'HCM.CDC.HR.>' --server nats://hr-nats:4222
```

## 📖 Database Schema

Tables included:
- `employees` - Employee master data
- `departments` - Department hierarchy
- `positions` - Job positions and levels
- `salary_changes` - Salary change history
- `leave_requests` - Leave request tracking
- `attendance_records` - Daily attendance

See `sql/init-db.sql` for complete schema.

## 🔧 Configuration

### Debezium Configuration

Edit `config/debezium/application.properties`:
- Database connection settings
- Topic prefix: `HCM.CDC.HR`
- NATS JetStream URL

### NATS Stream Configuration

Edit `config/nats/stream.json`:
- Stream name
- Subject patterns
- Retention policy
- Storage type

### MariaDB Configuration

Edit `config/mariadb/my.cnf`:
- Binlog settings (required for CDC)
- Performance tuning

## 🐛 Troubleshooting

### Check Service Health

```bash
make status
# or
docker-compose ps
```

### View Logs

```bash
# All services
make logs

# Specific service
docker logs hr-debezium
docker logs hr-mariadb
docker logs hr-nats
```

### Verify Binlog is Enabled

```bash
docker exec hr-mariadb mysql -uroot -prootpass \
  -e "SHOW VARIABLES LIKE 'log_bin';"
```

### Check NATS JetStream

```bash
curl http://localhost:8222/jsz
```

### Reset Everything

```bash
make clean
make start
```

## 📚 Documentation

- [Architecture Diagram](docs/architecture.svg)
- [Sequence Diagrams](docs/sequence-diagrams.svg)
- [Design Document](docs/design.md)
- [System Design](docs/system-design.md)
- [CDC Implementation Guide](docs/cdc-guide.md)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📝 License

This project is provided as-is for educational and development purposes.

## 🔗 Related Resources

- [Debezium Documentation](https://debezium.io/documentation/)
- [NATS JetStream](https://docs.nats.io/nats-concepts/jetstream)
- [MariaDB Binlog](https://mariadb.com/kb/en/binary-log/)
