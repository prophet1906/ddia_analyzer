package io.debezium.connector.ocel;

import org.junit.jupiter.api.Test;
import java.util.List;
import java.util.Map;
import static org.junit.jupiter.api.Assertions.*;

class OcelLogTest {

    @Test
    void emptyLogSerializesToValidOcelJson() throws Exception {
        OcelLog log = new OcelLog();
        String json = log.toJson();
        
        // Verify required OCEL 2.0 top-level arrays are present
        assertTrue(json.contains("\"eventTypes\""), "Missing eventTypes");
        assertTrue(json.contains("\"objectTypes\""), "Missing objectTypes");
        assertTrue(json.contains("\"events\""), "Missing events");
        assertTrue(json.contains("\"objects\""), "Missing objects");
        
        // Verify arrays are empty
        assertTrue(json.contains("\"eventTypes\":[]") || json.contains("\"eventTypes\" : []"), 
            "eventTypes should be empty array");
        assertTrue(json.contains("\"objectTypes\":[]") || json.contains("\"objectTypes\" : []"),
            "objectTypes should be empty array");
        assertTrue(json.contains("\"events\":[]") || json.contains("\"events\" : []"),
            "events should be empty array");
        assertTrue(json.contains("\"objects\":[]") || json.contains("\"objects\" : []"),
            "objects should be empty array");
    }

    @Test
    void jsonIsValidFormat() throws Exception {
        OcelLog log = new OcelLog();
        String json = log.toJson();
        
        // Should start with { and end with }
        assertTrue(json.trim().startsWith("{"), "JSON should start with {");
        assertTrue(json.trim().endsWith("}"), "JSON should end with }");
    }

    @Test
    void addEventCreatesValidOcelEvent() throws Exception {
        OcelLog log = new OcelLog();
        
        log.addEvent("e1", "create-sagastate", "2024-01-15T10:30:00Z", "sagastate_uuid-123");
        
        String json = log.toJson();
        assertTrue(json.contains("\"id\":\"e1\""));
        assertTrue(json.contains("\"type\":\"create-sagastate\""));
        assertTrue(json.contains("\"time\":\"2024-01-15T10:30:00Z\""));
        assertEquals(1, log.getEvents().size());
    }

    @Test
    void addEventTypeRegistersNewType() throws Exception {
        OcelLog log = new OcelLog();
        
        log.addEventType("create-sagastate");
        log.addEventType("create-sagastate"); // duplicate should be ignored
        
        assertEquals(1, log.getEventTypes().size());
        String json = log.toJson();
        assertTrue(json.contains("\"name\":\"create-sagastate\""));
    }

    @Test
    void addObjectCreatesValidOcelObject() throws Exception {
        OcelLog log = new OcelLog();
        
        log.addObject("sagastate_uuid-123", "sagastate");
        
        String json = log.toJson();
        assertTrue(json.contains("\"id\":\"sagastate_uuid-123\""));
        assertTrue(json.contains("\"type\":\"sagastate\""));
        assertEquals(1, log.getObjects().size());
    }

    @Test
    void addObjectTypeRegistersNewType() throws Exception {
        OcelLog log = new OcelLog();
        
        log.addObjectType("sagastate");
        log.addObjectType("sagastate"); // duplicate should be ignored
        
        assertEquals(1, log.getObjectTypes().size());
    }
}
