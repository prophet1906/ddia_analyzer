package io.debezium.connector.ocel;

import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.data.SchemaBuilder;
import org.apache.kafka.connect.data.Struct;
import org.apache.kafka.connect.sink.SinkRecord;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class OcelSinkTaskTest {

    @TempDir
    Path tempDir;

    private OcelSinkTask task;
    private Path outputFile;

    @BeforeEach
    void setUp() {
        task = new OcelSinkTask();
        outputFile = tempDir.resolve("ocel-output.json");
        
        Map<String, String> config = new HashMap<>();
        config.put(OcelSinkConnector.OUTPUT_FILE_PATH_CONFIG, outputFile.toString());
        task.start(config);
    }

    @Test
    void flushWritesEmptyOcelToFile() throws Exception {
        task.flush(null);
        
        String content = Files.readString(outputFile);
        assertTrue(content.contains("\"eventTypes\":[]"));
        assertTrue(content.contains("\"events\":[]"));
    }

    @Test
    void putHandlesDebeziumEnvelopeEvent() {
        // Debezium envelope format (without ExtractNewRecordState)
        Schema sourceSchema = SchemaBuilder.struct()
            .field("table", Schema.STRING_SCHEMA)
            .build();
        
        Schema valueSchema = SchemaBuilder.struct()
            .field("before", Schema.OPTIONAL_STRING_SCHEMA)
            .field("after", SchemaBuilder.struct()
                .field("id", Schema.STRING_SCHEMA)
                .field("status", Schema.STRING_SCHEMA)
                .build())
            .field("source", sourceSchema)
            .field("op", Schema.STRING_SCHEMA)
            .field("ts_ms", Schema.INT64_SCHEMA)
            .build();
        
        Struct source = new Struct(sourceSchema)
            .put("table", "sagastate");
        
        Struct after = new Struct(valueSchema.field("after").schema())
            .put("id", "uuid-123")
            .put("status", "STARTED");
        
        Struct value = new Struct(valueSchema)
            .put("before", null)
            .put("after", after)
            .put("source", source)
            .put("op", "c")
            .put("ts_ms", 1705312200000L);
        
        Schema keySchema = SchemaBuilder.struct()
            .field("id", Schema.STRING_SCHEMA)
            .build();
        Struct key = new Struct(keySchema).put("id", "uuid-123");
        
        SinkRecord record = new SinkRecord(
            "dbserver4.purchaseorder.sagastate",
            0, keySchema, key, valueSchema, value, 0);
        
        // Should not throw
        task.put(List.of(record));
    }

    @Test
    void putHandlesFlattenedEvent() {
        // Flattened format (with ExtractNewRecordState transform)
        Schema valueSchema = SchemaBuilder.struct()
            .field("id", Schema.STRING_SCHEMA)
            .field("status", Schema.STRING_SCHEMA)
            .field("type", Schema.STRING_SCHEMA)
            .build();
        
        Struct value = new Struct(valueSchema)
            .put("id", "uuid-456")
            .put("status", "COMPLETED")
            .put("type", "order-placement");
        
        Schema keySchema = SchemaBuilder.struct()
            .field("id", Schema.STRING_SCHEMA)
            .build();
        Struct key = new Struct(keySchema).put("id", "uuid-456");
        
        SinkRecord record = new SinkRecord(
            "dbserver4.purchaseorder.sagastate",
            0, keySchema, key, valueSchema, value, 0);
        
        // Should not throw
        task.put(List.of(record));
    }

    @Test
    void extractsBusinessTypeFromPayload() throws Exception {
        // Flattened format with "type" field - should use business type, not table name
        Schema valueSchema = SchemaBuilder.struct()
            .field("id", Schema.STRING_SCHEMA)
            .field("sagastatus", Schema.STRING_SCHEMA)
            .field("type", Schema.STRING_SCHEMA)
            .build();
        
        Struct value = new Struct(valueSchema)
            .put("id", "uuid-789")
            .put("sagastatus", "STARTED")
            .put("type", "order-placement");
        
        Schema keySchema = SchemaBuilder.struct()
            .field("id", Schema.STRING_SCHEMA)
            .build();
        Struct key = new Struct(keySchema).put("id", "uuid-789");
        
        SinkRecord record = new SinkRecord(
            "dbserver4.purchaseorder.sagastate",
            0, keySchema, key, valueSchema, value, 0);
        
        task.put(List.of(record));
        task.flush(null);
        
        String content = Files.readString(outputFile);
        
        // Should use "order-placement" as object type, not "sagastate"
        assertTrue(content.contains("\"order-placement\""), 
            "Should use business type 'order-placement', got: " + content);
        assertTrue(content.contains("\"order-placement_uuid-789\""), 
            "Object ID should use business type");
        // Event type should be dynamic from sagastatus
        assertTrue(content.contains("\"order-placement-started\""), 
            "Event type should be dynamic from sagastatus, got: " + content);
        assertFalse(content.contains("\"sagastate\""), 
            "Should NOT use table name 'sagastate'");
    }

    @Test
    void extractsDynamicEventTypeFromSagaStatus() throws Exception {
        // Test different saga statuses produce different event types
        Schema valueSchema = SchemaBuilder.struct()
            .field("id", Schema.STRING_SCHEMA)
            .field("sagastatus", Schema.STRING_SCHEMA)
            .field("type", Schema.STRING_SCHEMA)
            .build();
        
        Schema keySchema = SchemaBuilder.struct()
            .field("id", Schema.STRING_SCHEMA)
            .build();
        
        // STARTED event
        Struct value1 = new Struct(valueSchema)
            .put("id", "uuid-1")
            .put("sagastatus", "STARTED")
            .put("type", "order-placement");
        Struct key1 = new Struct(keySchema).put("id", "uuid-1");
        
        // COMPLETED event
        Struct value2 = new Struct(valueSchema)
            .put("id", "uuid-1")
            .put("sagastatus", "COMPLETED")
            .put("type", "order-placement");
        Struct key2 = new Struct(keySchema).put("id", "uuid-1");
        
        // ABORTED event
        Struct value3 = new Struct(valueSchema)
            .put("id", "uuid-2")
            .put("sagastatus", "ABORTED")
            .put("type", "order-placement");
        Struct key3 = new Struct(keySchema).put("id", "uuid-2");
        
        task.put(List.of(
            new SinkRecord("dbserver4.purchaseorder.sagastate", 0, keySchema, key1, valueSchema, value1, 0),
            new SinkRecord("dbserver4.purchaseorder.sagastate", 0, keySchema, key2, valueSchema, value2, 1),
            new SinkRecord("dbserver4.purchaseorder.sagastate", 0, keySchema, key3, valueSchema, value3, 2)
        ));
        task.flush(null);
        
        String content = Files.readString(outputFile);
        
        // Should have different event types based on sagastatus
        assertTrue(content.contains("\"order-placement-started\""), 
            "Should have STARTED event type, got: " + content);
        assertTrue(content.contains("\"order-placement-completed\""), 
            "Should have COMPLETED event type, got: " + content);
        assertTrue(content.contains("\"order-placement-aborted\""), 
            "Should have ABORTED event type, got: " + content);
    }

    @Test
    void fallsBackToTableNameWhenNoTypeField() throws Exception {
        // Record without "type" field - should fall back to table name
        Schema valueSchema = SchemaBuilder.struct()
            .field("id", Schema.STRING_SCHEMA)
            .field("status", Schema.STRING_SCHEMA)
            .build();
        
        Struct value = new Struct(valueSchema)
            .put("id", "uuid-abc")
            .put("status", "STARTED");
        
        Schema keySchema = SchemaBuilder.struct()
            .field("id", Schema.STRING_SCHEMA)
            .build();
        Struct key = new Struct(keySchema).put("id", "uuid-abc");
        
        SinkRecord record = new SinkRecord(
            "dbserver4.purchaseorder.orders",
            0, keySchema, key, valueSchema, value, 0);
        
        task.put(List.of(record));
        task.flush(null);
        
        String content = Files.readString(outputFile);
        
        // Should fall back to table name "orders"
        assertTrue(content.contains("\"orders\""), 
            "Should fall back to table name 'orders', got: " + content);
        assertTrue(content.contains("\"orders_uuid-abc\""), 
            "Object ID should use table name");
    }

    @Test
    void putSkipsNullRecords() {
        SinkRecord tombstone = new SinkRecord(
            "test-topic", 0, null, null, null, null, 0);
        
        // Should not throw
        task.put(List.of(tombstone));
    }

    @Test
    void paymentTableUsesTableNameNotTypeField() throws Exception {
        // Payment table has a "type" field with REQUEST/CANCEL, NOT a business object type
        // The object type should be "payment", not "REQUEST"
        Schema valueSchema = SchemaBuilder.struct()
            .field("id", Schema.STRING_SCHEMA)
            .field("type", Schema.STRING_SCHEMA)  // REQUEST or CANCEL
            .field("creditcardno", Schema.STRING_SCHEMA)
            .field("amount", Schema.INT32_SCHEMA)
            .build();
        
        Struct value = new Struct(valueSchema)
            .put("id", "payment-123")
            .put("type", "REQUEST")
            .put("creditcardno", "1234567890")
            .put("amount", 100);
        
        Schema keySchema = SchemaBuilder.struct()
            .field("id", Schema.STRING_SCHEMA)
            .build();
        Struct key = new Struct(keySchema).put("id", "payment-123");
        
        SinkRecord record = new SinkRecord(
            "payment.payment.payment",  // payment topic
            0, keySchema, key, valueSchema, value, 0);
        
        task.put(List.of(record));
        task.flush(null);
        
        String content = Files.readString(outputFile);
        
        // Object type should be "payment" (table name), NOT "REQUEST"
        assertTrue(content.contains("\"payment\""), 
            "Object type should be 'payment', got: " + content);
        assertTrue(content.contains("\"payment_payment-123\""), 
            "Object ID should use table name 'payment'");
        // Event type should include the REQUEST type
        assertTrue(content.contains("\"payment-request\""), 
            "Event type should be 'payment-request', got: " + content);
        // Should NOT have REQUEST as object type
        assertFalse(content.contains("\"REQUEST\""), 
            "Object type should NOT be 'REQUEST', got: " + content);
    }

    @Test
    void customerTableUsesTableName() throws Exception {
        // Customer table has no "type" field, should use table name
        Schema valueSchema = SchemaBuilder.struct()
            .field("id", Schema.INT64_SCHEMA)
            .field("creditlimit", Schema.INT32_SCHEMA)
            .build();
        
        Struct value = new Struct(valueSchema)
            .put("id", 456L)
            .put("creditlimit", 50000);
        
        Schema keySchema = SchemaBuilder.struct()
            .field("id", Schema.INT64_SCHEMA)
            .build();
        Struct key = new Struct(keySchema).put("id", 456L);
        
        SinkRecord record = new SinkRecord(
            "customer.customer.customer",
            0, keySchema, key, valueSchema, value, 0);
        
        task.put(List.of(record));
        task.flush(null);
        
        String content = Files.readString(outputFile);
        
        // Should use table name "customer"
        assertTrue(content.contains("\"customer\""), 
            "Object type should be 'customer', got: " + content);
        assertTrue(content.contains("\"customer_456\""), 
            "Object ID should use table name 'customer'");
    }

    @Test
    void purchaseOrderTableUsesTableName() throws Exception {
        // Purchase order table has "status" field, should use table name for object type
        Schema valueSchema = SchemaBuilder.struct()
            .field("id", Schema.INT64_SCHEMA)
            .field("status", Schema.STRING_SCHEMA)
            .field("customerid", Schema.INT64_SCHEMA)
            .build();
        
        Struct value = new Struct(valueSchema)
            .put("id", 1L)
            .put("status", "CREATED")
            .put("customerid", 456L);
        
        Schema keySchema = SchemaBuilder.struct()
            .field("id", Schema.INT64_SCHEMA)
            .build();
        Struct key = new Struct(keySchema).put("id", 1L);
        
        SinkRecord record = new SinkRecord(
            "order.purchaseorder.purchaseorder",
            0, keySchema, key, valueSchema, value, 0);
        
        task.put(List.of(record));
        task.flush(null);
        
        String content = Files.readString(outputFile);
        
        // Should use table name "purchaseorder"
        assertTrue(content.contains("\"purchaseorder\""), 
            "Object type should be 'purchaseorder', got: " + content);
        assertTrue(content.contains("\"purchaseorder_1\""), 
            "Object ID should use table name 'purchaseorder'");
        // Event type should include status
        assertTrue(content.contains("\"purchaseorder-created\""), 
            "Event type should be 'purchaseorder-created', got: " + content);
    }

    @Test
    void fullTransformationProducesValidOcel() throws Exception {
        // Create a Debezium-style event
        Schema sourceSchema = SchemaBuilder.struct()
            .field("table", Schema.STRING_SCHEMA)
            .build();
        
        Schema valueSchema = SchemaBuilder.struct()
            .field("before", Schema.OPTIONAL_STRING_SCHEMA)
            .field("after", SchemaBuilder.struct()
                .field("id", Schema.STRING_SCHEMA)
                .field("status", Schema.STRING_SCHEMA)
                .build())
            .field("source", sourceSchema)
            .field("op", Schema.STRING_SCHEMA)
            .field("ts_ms", Schema.INT64_SCHEMA)
            .build();
        
        Struct source = new Struct(sourceSchema).put("table", "sagastate");
        Struct after = new Struct(valueSchema.field("after").schema())
            .put("id", "test-uuid")
            .put("status", "STARTED");
        Struct value = new Struct(valueSchema)
            .put("after", after)
            .put("source", source)
            .put("op", "c")
            .put("ts_ms", 1705312200000L);
        
        Schema keySchema = SchemaBuilder.struct().field("id", Schema.STRING_SCHEMA).build();
        Struct key = new Struct(keySchema).put("id", "test-uuid");
        
        SinkRecord record = new SinkRecord(
            "dbserver4.purchaseorder.sagastate", 0, 
            keySchema, key, valueSchema, value, 0);
        
        task.put(List.of(record));
        task.flush(null);
        
        String content = Files.readString(outputFile);
        
        // Verify OCEL structure - falls back to table name since no "type" field in value
        assertTrue(content.contains("\"eventTypes\""), "Missing eventTypes");
        assertTrue(content.contains("\"create-sagastate\""), "Should have event type (from table name)");
        assertTrue(content.contains("\"sagastate_test-uuid\""), "Should have object ID");
        // Verify timestamp format (ISO 8601 with Z suffix)
        assertTrue(content.matches(".*\"time\":\"\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z\".*"), 
            "Should have ISO 8601 timestamp, got: " + content);
    }
}
