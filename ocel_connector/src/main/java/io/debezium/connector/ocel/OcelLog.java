package io.debezium.connector.ocel;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.*;

/**
 * OCEL 2.0 log container. Accumulates events and objects for JSON serialization.
 * Schema: https://www.ocel-standard.org/2.0/ocel20-schema-json.json
 */
public class OcelLog {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @JsonProperty("eventTypes")
    private final List<Map<String, Object>> eventTypes = new ArrayList<>();

    @JsonProperty("objectTypes")
    private final List<Map<String, Object>> objectTypes = new ArrayList<>();

    @JsonProperty("events")
    private final List<Map<String, Object>> events = new ArrayList<>();

    @JsonProperty("objects")
    private final List<Map<String, Object>> objects = new ArrayList<>();

    // Track known types to avoid duplicates
    private final Set<String> knownEventTypes = new HashSet<>();
    private final Set<String> knownObjectTypes = new HashSet<>();
    private final Set<String> knownObjectIds = new HashSet<>();

    public String toJson() throws Exception {
        return MAPPER.writeValueAsString(this);
    }

    /**
     * Add an event to the log.
     * @param id Unique event ID (e.g., "e1")
     * @param type Event type name (e.g., "create-sagastate")
     * @param time ISO 8601 timestamp
     * @param objectId Related object ID
     */
    public void addEvent(String id, String type, String time, String objectId) {
        Map<String, Object> event = new LinkedHashMap<>();
        event.put("id", id);
        event.put("type", type);
        event.put("time", time);
        event.put("relationships", List.of(Map.of("objectId", objectId, "qualifier", "subject")));
        events.add(event);
    }

    /**
     * Register an event type if not already known.
     */
    public void addEventType(String name) {
        if (knownEventTypes.add(name)) {
            Map<String, Object> eventType = new LinkedHashMap<>();
            eventType.put("name", name);
            eventType.put("attributes", List.of());
            eventTypes.add(eventType);
        }
    }

    /**
     * Add an object to the log (or skip if already exists).
     * @param id Object ID (e.g., "sagastate_uuid-123")
     * @param type Object type name (e.g., "sagastate")
     */
    public void addObject(String id, String type) {
        if (knownObjectIds.add(id)) {
            Map<String, Object> object = new LinkedHashMap<>();
            object.put("id", id);
            object.put("type", type);
            objects.add(object);
        }
    }

    /**
     * Register an object type if not already known.
     */
    public void addObjectType(String name) {
        if (knownObjectTypes.add(name)) {
            Map<String, Object> objectType = new LinkedHashMap<>();
            objectType.put("name", name);
            objectType.put("attributes", List.of());
            objectTypes.add(objectType);
        }
    }

    public List<Map<String, Object>> getEventTypes() {
        return eventTypes;
    }

    public List<Map<String, Object>> getObjectTypes() {
        return objectTypes;
    }

    public List<Map<String, Object>> getEvents() {
        return events;
    }

    public List<Map<String, Object>> getObjects() {
        return objects;
    }
}
