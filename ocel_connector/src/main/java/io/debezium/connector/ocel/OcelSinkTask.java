package io.debezium.connector.ocel;

import org.apache.kafka.connect.data.Struct;
import org.apache.kafka.connect.sink.SinkRecord;
import org.apache.kafka.connect.sink.SinkTask;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Collection;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Kafka Connect Sink Task that transforms Debezium events to OCEL 2.0 format.
 */
public class OcelSinkTask extends SinkTask {

    private static final DateTimeFormatter ISO_FORMATTER = 
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC);

    private OcelLog ocelLog;
    private Path outputPath;
    private final AtomicLong eventCounter = new AtomicLong(0);

    @Override
    public String version() {
        return "1.0.0";
    }

    @Override
    public void start(Map<String, String> props) {
        this.ocelLog = new OcelLog();
        this.outputPath = Path.of(props.get(OcelSinkConnector.OUTPUT_FILE_PATH_CONFIG));
    }

    @Override
    public void put(Collection<SinkRecord> records) {
        for (SinkRecord record : records) {
            if (record.value() == null) {
                continue; // Skip tombstones
            }
            processRecord(record);
        }
    }

    private void processRecord(SinkRecord record) {
        // Extract table name from topic (format: prefix.schema.table)
        String topic = record.topic();
        String tableName = extractTableName(topic);
        
        // Extract primary key from record key
        String primaryKey = extractPrimaryKey(record);
        if (primaryKey == null) {
            return; // Can't process without a key
        }
        
        // Extract business type from payload (e.g., "order-placement") or fall back to table name
        String objectType = extractObjectType(record, tableName);
        
        // Build IDs per ADR-001: {type}_{pk}
        String objectId = objectType + "_" + primaryKey;
        
        // Extract dynamic event type from payload fields (sagastatus, status, etc.)
        String eventType = extractEventType(record, objectType);
        
        // Get timestamp
        String timestamp = extractTimestamp(record);
        
        // Generate event ID
        String eventId = "e" + eventCounter.incrementAndGet();
        
        // Register types and add event/object
        ocelLog.addEventType(eventType);
        ocelLog.addObjectType(objectType);
        ocelLog.addObject(objectId, objectType);
        ocelLog.addEvent(eventId, eventType, timestamp, objectId);
    }

    private String extractTableName(String topic) {
        // Topic format: prefix.schema.table or prefix.table
        String[] parts = topic.split("\\.");
        return parts[parts.length - 1]; // Last part is table name
    }

    /**
     * Extracts business object type from record payload.
     * Looks for a "type" field in the value which contains a business saga type (e.g., "order-placement").
     * Only uses the type field if it looks like a saga type (contains a dash).
     * Falls back to table name for regular tables like payment, customer, purchaseorder.
     */
    @SuppressWarnings("unchecked")
    private String extractObjectType(SinkRecord record, String fallback) {
        Object value = record.value();
        
        if (value instanceof Struct) {
            Struct valueStruct = (Struct) value;
            // Check for "type" field in Struct
            if (valueStruct.schema().field("type") != null) {
                String type = valueStruct.getString("type");
                // Only use type if it looks like a saga business type (contains dash)
                // This avoids using "REQUEST"/"CANCEL" from payment table as object type
                if (type != null && !type.isBlank() && isSagaType(type)) {
                    return type;
                }
            }
        }
        
        if (value instanceof Map) {
            // Handle JsonConverter without schemas (returns Map)
            Map<String, Object> valueMap = (Map<String, Object>) value;
            Object type = valueMap.get("type");
            // Only use type if it looks like a saga business type (contains dash)
            if (type != null && !type.toString().isBlank() && isSagaType(type.toString())) {
                return type.toString();
            }
        }
        
        return fallback;
    }

    /**
     * Checks if a type string looks like a saga business type.
     * Saga types typically contain dashes (e.g., "order-placement").
     * Non-saga types are typically single words (e.g., "REQUEST", "CANCEL").
     */
    private boolean isSagaType(String type) {
        return type.contains("-");
    }

    @SuppressWarnings("unchecked")
    private String extractPrimaryKey(SinkRecord record) {
        Object key = record.key();
        if (key == null) {
            return null;
        }
        if (key instanceof Struct) {
            Struct keyStruct = (Struct) key;
            // Get first field value as primary key
            if (!keyStruct.schema().fields().isEmpty()) {
                Object pkValue = keyStruct.get(keyStruct.schema().fields().get(0));
                return pkValue != null ? pkValue.toString() : null;
            }
        }
        if (key instanceof Map) {
            // Handle JsonConverter without schemas (returns Map)
            Map<String, Object> keyMap = (Map<String, Object>) key;
            if (!keyMap.isEmpty()) {
                // Get first value (typically "id")
                Object pkValue = keyMap.values().iterator().next();
                return pkValue != null ? pkValue.toString() : null;
            }
        }
        return key.toString();
    }

    /**
     * Extracts a dynamic event type from the record payload.
     * Looks for status fields in this priority order:
     * 1. "sagastatus" + "currentstep" - saga state with step (e.g., "order-placement-started-credit-approval")
     * 2. "sagastatus" - saga state alone (STARTED, COMPLETED, ABORTED, ABORTING)
     * 3. "status" - general status field (CREATED, APPROVED, etc.)
     * 4. "type" field - event type from payload (for non-saga tables)
     * 5. Debezium "op" field - CDC operation (create, update, delete)
     * 6. Falls back to "update-{objectType}"
     */
    @SuppressWarnings("unchecked")
    private String extractEventType(SinkRecord record, String objectType) {
        Object value = record.value();
        
        // Try to extract from Map (JsonConverter without schemas)
        if (value instanceof Map) {
            Map<String, Object> valueMap = (Map<String, Object>) value;
            
            // Check for sagastatus (saga state machine) with optional currentstep
            Object sagaStatus = valueMap.get("sagastatus");
            if (sagaStatus != null && !sagaStatus.toString().isBlank()) {
                String eventType = objectType + "-" + sagaStatus.toString().toLowerCase();
                // Append currentstep if available for more granular events
                Object currentStep = valueMap.get("currentstep");
                if (currentStep != null && !currentStep.toString().isBlank()) {
                    eventType += "-" + currentStep.toString().toLowerCase();
                }
                return eventType;
            }
            
            // Check for general status field
            Object status = valueMap.get("status");
            if (status != null && !status.toString().isBlank()) {
                return objectType + "-" + status.toString().toLowerCase();
            }
            
            // Check for type field (for payment, etc.)
            Object type = valueMap.get("type");
            if (type != null && !type.toString().isBlank() && !type.toString().equals(objectType)) {
                return objectType + "-" + type.toString().toLowerCase();
            }
        }
        
        // Try to extract from Struct (with schemas)
        if (value instanceof Struct) {
            Struct valueStruct = (Struct) value;
            
            // Check for sagastatus with optional currentstep
            if (valueStruct.schema().field("sagastatus") != null) {
                String sagaStatus = valueStruct.getString("sagastatus");
                if (sagaStatus != null && !sagaStatus.isBlank()) {
                    String eventType = objectType + "-" + sagaStatus.toLowerCase();
                    if (valueStruct.schema().field("currentstep") != null) {
                        String currentStep = valueStruct.getString("currentstep");
                        if (currentStep != null && !currentStep.isBlank()) {
                            eventType += "-" + currentStep.toLowerCase();
                        }
                    }
                    return eventType;
                }
            }
            
            // Check for status
            if (valueStruct.schema().field("status") != null) {
                String status = valueStruct.getString("status");
                if (status != null && !status.isBlank()) {
                    return objectType + "-" + status.toLowerCase();
                }
            }
            
            // Check for type field
            if (valueStruct.schema().field("type") != null) {
                String type = valueStruct.getString("type");
                if (type != null && !type.isBlank() && !type.equals(objectType)) {
                    return objectType + "-" + type.toLowerCase();
                }
            }
            
            // Fall back to Debezium op field
            if (valueStruct.schema().field("op") != null) {
                String op = valueStruct.getString("op");
                return mapOperation(op) + "-" + objectType;
            }
        }
        
        // Default fallback
        return "update-" + objectType;
    }

    private String mapOperation(String op) {
        return switch (op) {
            case "c", "r" -> "create"; // create or read (snapshot)
            case "u" -> "update";
            case "d" -> "delete";
            default -> "update";
        };
    }

    private String extractTimestamp(SinkRecord record) {
        Object value = record.value();
        if (value instanceof Struct) {
            Struct valueStruct = (Struct) value;
            // Check for ts_ms in Debezium envelope
            if (valueStruct.schema().field("ts_ms") != null) {
                Long tsMs = valueStruct.getInt64("ts_ms");
                return ISO_FORMATTER.format(Instant.ofEpochMilli(tsMs));
            }
        }
        // Use current time as fallback
        return ISO_FORMATTER.format(Instant.now());
    }

    @Override
    public void flush(Map<org.apache.kafka.common.TopicPartition, org.apache.kafka.clients.consumer.OffsetAndMetadata> offsets) {
        try {
            if (outputPath.getParent() != null) {
                Files.createDirectories(outputPath.getParent());
            }
            Files.writeString(outputPath, ocelLog.toJson());
        } catch (Exception e) {
            throw new RuntimeException("Failed to write OCEL log to " + outputPath, e);
        }
    }

    @Override
    public void stop() {
        // Final flush on stop
        flush(null);
    }
}
