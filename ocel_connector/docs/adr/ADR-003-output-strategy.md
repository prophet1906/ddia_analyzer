# ADR-003: Output Strategy

## Status
Accepted

## Context
The connector needs to persist OCEL 2.0 data to storage. Options include:
- Single JSON file
- Rolling files (by time or size)
- Database storage
- Streaming output (JSONL)

## Decision
Use a single JSON file with flush on Kafka Connect commit.

The connector:
1. Accumulates events in memory
2. Writes complete OCEL JSON on flush() calls
3. Overwrites the file atomically

## Consequences

### Positive
- Simple implementation
- Complete valid OCEL file at all times
- Leverages Kafka Connect offset management
- Easy to validate and process

### Negative
- Memory usage grows with event count
- File size can become large over time
- Not suitable for infinite streams (requires periodic rotation externally)

### Mitigations
- For production, implement external log rotation
- Consider adding `ocel.max.events` config in future

## Alternatives Considered

1. **Rolling files**: More complex, requires file naming strategy
2. **JSONL streaming**: Not valid OCEL 2.0 format
3. **Database**: Over-engineered for this use case
