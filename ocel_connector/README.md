# Debezium OCEL Sink Connector

A minimal Kafka Connect sink connector that transforms Change Data Capture (CDC) events from Debezium into [OCEL 2.0](https://www.ocel-standard.org/) JSON format for process mining analysis.

## Overview

This connector consumes Debezium CDC events from Kafka topics and produces OCEL 2.0 compliant JSON files. Each database change becomes an OCEL event linked to an OCEL object representing the affected row.

### Features

- Transforms Debezium CDC events to OCEL 2.0 format
- Supports both envelope and flattened event formats (ExtractNewRecordState SMT)
- Maps CDC operations to event types: `create`, `update`, `delete`
- Generates unique object IDs from table name and primary key
- Outputs valid OCEL 2.0 JSON on each Kafka Connect flush

## OCEL 2.0 Output Format

```json
{
  "eventTypes": [
    {"name": "create-orders", "attributes": []},
    {"name": "update-orders", "attributes": []}
  ],
  "objectTypes": [
    {"name": "orders", "attributes": []}
  ],
  "events": [
    {
      "id": "e1",
      "type": "create-orders",
      "time": "2024-01-15T10:30:00Z",
      "relationships": [
        {"objectId": "orders_123", "qualifier": "subject"}
      ]
    }
  ],
  "objects": [
    {"id": "orders_123", "type": "orders"}
  ]
}
```

## Requirements

- Java 17+
- Apache Kafka 3.x
- Kafka Connect
- Debezium 2.x (source connector)

## Building

```bash
mvn clean package
```

This produces `target/debezium-connector-ocel-1.0.0-SNAPSHOT.jar`.

## Installation

1. Create a plugin directory in your Kafka Connect installation:
   ```bash
   mkdir -p /path/to/connect-plugins/ocel-connector
   ```

2. Copy the connector JAR and dependencies:
   ```bash
   cp target/debezium-connector-ocel-1.0.0-SNAPSHOT.jar /path/to/connect-plugins/ocel-connector/
   cp ~/.m2/repository/com/fasterxml/jackson/core/jackson-core/2.15.0/jackson-core-2.15.0.jar /path/to/connect-plugins/ocel-connector/
   cp ~/.m2/repository/com/fasterxml/jackson/core/jackson-databind/2.15.0/jackson-databind-2.15.0.jar /path/to/connect-plugins/ocel-connector/
   cp ~/.m2/repository/com/fasterxml/jackson/core/jackson-annotations/2.15.0/jackson-annotations-2.15.0.jar /path/to/connect-plugins/ocel-connector/
   ```

3. Ensure the plugin path is configured in your Kafka Connect worker:
   ```properties
   plugin.path=/path/to/connect-plugins
   ```

## Configuration

### Connector Properties

| Property | Required | Description |
|----------|----------|-------------|
| `connector.class` | Yes | `io.debezium.connector.ocel.OcelSinkConnector` |
| `topics` | Yes | Comma-separated list of Kafka topics to consume |
| `ocel.output.file.path` | Yes | Path to write OCEL JSON output file |
| `tasks.max` | No | Maximum number of tasks (default: 1) |

### Example Configuration

```json
{
  "name": "ocel-sink",
  "config": {
    "connector.class": "io.debezium.connector.ocel.OcelSinkConnector",
    "tasks.max": "1",
    "topics": "dbserver1.public.orders",
    "ocel.output.file.path": "/data/ocel/orders.json"
  }
}
```

### Register via REST API

```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @config/ocel-connector.json
```

## Design Decisions

Design choices are documented as Architecture Decision Records (ADRs):

| ADR | Decision |
|-----|----------|
| [ADR-001](docs/adr/ADR-001-object-id-strategy.md) | Object ID: `{table}_{primary_key}` |
| [ADR-002](docs/adr/ADR-002-event-type-naming.md) | Event Type: `{operation}-{table}` |
| [ADR-003](docs/adr/ADR-003-output-strategy.md) | Single JSON file output |
| [ADR-004](docs/adr/ADR-004-build-system.md) | Java 17 + Maven |

## Topic Naming Convention

The connector extracts the table name from the Kafka topic name. Debezium topics follow the pattern:

```
{server.name}.{schema}.{table}
```

The connector uses the last segment as the table/object type name.

## Event Type Mapping

| Debezium Operation | OCEL Event Type |
|--------------------|-----------------|
| `c` (create) | `create-{table}` |
| `r` (read/snapshot) | `create-{table}` |
| `u` (update) | `update-{table}` |
| `d` (delete) | `delete-{table}` |
| Flattened (no op) | `update-{table}` |

## Testing

### Unit Tests

```bash
mvn test
```

### Validate OCEL Output

```bash
./scripts/validate-ocel.sh /path/to/output.json
```

## Demo

See [DEMO.md](DEMO.md) for a complete walkthrough using the Debezium SAGA example.

## Project Structure

```
.
├── pom.xml                          # Maven build configuration
├── src/
│   ├── main/java/.../ocel/
│   │   ├── OcelSinkConnector.java   # Kafka Connect entry point
│   │   ├── OcelSinkTask.java        # Event transformation logic
│   │   └── OcelLog.java             # OCEL 2.0 data model
│   └── test/java/.../ocel/
│       ├── OcelLogTest.java         # Model unit tests
│       └── OcelSinkTaskTest.java    # Task integration tests
├── config/
│   └── ocel-saga-connector.json     # Example configuration
├── scripts/
│   ├── run-integration-test.sh      # Integration test setup
│   └── validate-ocel.sh             # OCEL validation script
└── docs/
    └── adr/                         # Architecture Decision Records
```

## Limitations

- Single output file (overwrites on each flush)
- No attribute extraction (only object references)
- Single object relationship per event
- No schema evolution handling
