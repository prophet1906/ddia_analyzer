#!/bin/bash
# Validates OCEL 2.0 JSON output

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <ocel-file.json>"
    echo ""
    echo "Validates that a JSON file conforms to OCEL 2.0 structure."
    exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
    echo "✗ File not found: $FILE"
    exit 1
fi

echo "Validating OCEL 2.0 JSON: $FILE"
echo ""

# Check if valid JSON
if ! jq . "$FILE" > /dev/null 2>&1; then
    echo "✗ Invalid JSON"
    exit 1
fi
echo "✓ Valid JSON"

# Check required top-level arrays
for field in eventTypes objectTypes events objects; do
    if ! jq -e ".$field" "$FILE" > /dev/null 2>&1; then
        echo "✗ Missing required field: $field"
        exit 1
    fi
    if ! jq -e ".$field | type == \"array\"" "$FILE" > /dev/null 2>&1; then
        echo "✗ Field '$field' must be an array"
        exit 1
    fi
done
echo "✓ All required fields present"

# Count items
EVENT_TYPES=$(jq '.eventTypes | length' "$FILE")
OBJECT_TYPES=$(jq '.objectTypes | length' "$FILE")
EVENTS=$(jq '.events | length' "$FILE")
OBJECTS=$(jq '.objects | length' "$FILE")

echo ""
echo "Summary:"
echo "  Event Types: $EVENT_TYPES"
echo "  Object Types: $OBJECT_TYPES"
echo "  Events: $EVENTS"
echo "  Objects: $OBJECTS"

# Validate event structure
if [ "$EVENTS" -gt 0 ]; then
    echo ""
    echo "Checking event structure..."
    FIRST_EVENT=$(jq '.events[0]' "$FILE")
    
    for field in id type time; do
        if ! echo "$FIRST_EVENT" | jq -e ".$field" > /dev/null 2>&1; then
            echo "✗ Event missing required field: $field"
            exit 1
        fi
    done
    echo "✓ Events have required fields (id, type, time)"
fi

# Validate object structure  
if [ "$OBJECTS" -gt 0 ]; then
    echo ""
    echo "Checking object structure..."
    FIRST_OBJECT=$(jq '.objects[0]' "$FILE")
    
    for field in id type; do
        if ! echo "$FIRST_OBJECT" | jq -e ".$field" > /dev/null 2>&1; then
            echo "✗ Object missing required field: $field"
            exit 1
        fi
    done
    echo "✓ Objects have required fields (id, type)"
fi

echo ""
echo "✓ OCEL 2.0 validation passed!"
