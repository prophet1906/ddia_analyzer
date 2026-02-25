# ADR-001: Object ID Strategy

## Status
Accepted

## Context
OCEL 2.0 requires unique object identifiers. Debezium CDC events contain table names and primary keys. We need a strategy to construct globally unique object IDs from this information.

## Decision
Use `{table}_{primary_key}` format for object IDs.

Examples:
- `sagastate_550e8400-e29b-41d4-a716-446655440000`
- `customers_1001`

## Consequences

### Positive
- Simple and predictable
- Human-readable
- Guarantees uniqueness across tables
- Primary key is preserved and visible

### Negative
- Assumes primary keys don't contain underscores (rare edge case)
- Longer IDs than using PK alone

## Alternatives Considered

1. **PK only**: Simpler but risks collisions across tables
2. **UUID generation**: Requires mapping table, loses traceability
3. **Hash-based**: Less readable, harder to debug
