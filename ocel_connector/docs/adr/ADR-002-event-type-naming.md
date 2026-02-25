# ADR-002: Event Type Naming

## Status
Accepted

## Context
OCEL 2.0 requires event types to have names. Debezium CDC events contain operation codes (c/u/d/r) and table names. We need a convention for naming event types.

## Decision
Use `{operation}-{table}` format for event type names.

Operation mapping:
- `c` (create) or `r` (read/snapshot) → `create-{table}`
- `u` (update) → `update-{table}`
- `d` (delete) → `delete-{table}`

Examples:
- `create-sagastate`
- `update-sagastate`
- `delete-customers`

## Consequences

### Positive
- Clear semantic meaning
- Maps directly to database operations
- Enables filtering by operation type in process mining tools
- Human-readable

### Negative
- Requires parsing operation from Debezium event
- Flattened events (with ExtractNewRecordState) may not have operation info

## Alternatives Considered

1. **`{table}-{operation}`**: Less natural English reading
2. **`{table}_changed`**: Loses operation detail
3. **Debezium operation codes directly**: `c-sagastate` - less readable
