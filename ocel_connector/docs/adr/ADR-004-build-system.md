# ADR-004: Build System

## Status
Accepted

## Context
Need to choose build system and Java version for the Kafka Connect sink connector.

## Decision
Use Java 17 with Maven.

Dependencies (minimal):
- `org.apache.kafka:connect-api:3.6.0` (provided - runtime supplies this)
- `com.fasterxml.jackson.core:jackson-databind:2.15.0` (JSON serialization)
- `org.junit.jupiter:junit-jupiter:5.10.0` (testing)

## Consequences

### Positive
- Standard Kafka Connect ecosystem tooling
- Simple dependency management
- Wide IDE support
- Java 17 LTS with modern features (switch expressions, text blocks)

### Negative
- Maven verbose compared to Gradle
- No fat JAR by default (dependencies must be deployed separately)

## Alternatives Considered

1. **Gradle**: More concise but less common in Kafka ecosystem
2. **Java 11**: Misses useful Java 17 features
3. **Kotlin**: Learning curve, not standard in Kafka Connect

## Deployment Notes

The connector JAR must be deployed to Kafka Connect's plugin path along with:
- jackson-databind
- jackson-core
- jackson-annotations
