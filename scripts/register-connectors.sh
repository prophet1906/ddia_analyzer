#!/bin/bash
#
# Register all Debezium source connectors and OCEL sink connector
#

set -e

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"

echo "Registering connectors at ${CONNECT_URL}..."

# Order Outbox Connector - captures outbox events from Order Service
curl -X POST "${CONNECT_URL}/connectors" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "order-outbox-connector",
    "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "tasks.max": "1",
        "database.hostname": "order-db",
        "database.port": "5432",
        "database.user": "orderuser",
        "database.password": "orderpw",
        "database.dbname": "orderdb",
        "topic.prefix": "dbserver1",
        "schema.include.list": "purchaseorder",
        "table.include.list": "purchaseorder.outboxevent",
        "tombstones.on.delete": "false",
        "slot.name": "debezium_order_outbox",
        "plugin.name": "pgoutput",
        "key.converter": "org.apache.kafka.connect.storage.StringConverter",
        "value.converter": "org.apache.kafka.connect.storage.StringConverter",
        "transforms": "saga",
        "transforms.saga.type": "io.debezium.transforms.outbox.EventRouter",
        "transforms.saga.route.topic.replacement": "${routedByValue}.request",
        "poll.interval.ms": "100",
        "producer.override.interceptor.classes": ""
    }
}'

echo ""

# Payment Outbox Connector - captures outbox events from Payment Service
curl -X POST "${CONNECT_URL}/connectors" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "payment-outbox-connector",
    "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "tasks.max": "1",
        "database.hostname": "payment-db",
        "database.port": "5432",
        "database.user": "paymentuser",
        "database.password": "paymentpw",
        "database.dbname": "paymentdb",
        "topic.prefix": "dbserver2",
        "schema.include.list": "payment",
        "table.include.list": "payment.outboxevent",
        "tombstones.on.delete": "false",
        "slot.name": "debezium_payment_outbox",
        "plugin.name": "pgoutput",
        "key.converter": "org.apache.kafka.connect.storage.StringConverter",
        "value.converter": "org.apache.kafka.connect.storage.StringConverter",
        "transforms": "outbox",
        "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
        "transforms.outbox.route.topic.replacement": "${routedByValue}.response",
        "poll.interval.ms": "100",
        "producer.override.interceptor.classes": ""
    }
}'

echo ""

# Credit/Customer Outbox Connector - captures outbox events from Customer Service
curl -X POST "${CONNECT_URL}/connectors" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "credit-outbox-connector",
    "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "tasks.max": "1",
        "database.hostname": "customer-db",
        "database.port": "5432",
        "database.user": "customeruser",
        "database.password": "customerpw",
        "database.dbname": "customerdb",
        "topic.prefix": "dbserver3",
        "schema.include.list": "customer",
        "table.include.list": "customer.outboxevent",
        "tombstones.on.delete": "false",
        "slot.name": "debezium_credit_outbox",
        "plugin.name": "pgoutput",
        "key.converter": "org.apache.kafka.connect.storage.StringConverter",
        "value.converter": "org.apache.kafka.connect.storage.StringConverter",
        "transforms": "outbox",
        "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
        "transforms.outbox.route.topic.replacement": "${routedByValue}.response",
        "poll.interval.ms": "100",
        "producer.override.interceptor.classes": ""
    }
}'

echo ""

# Saga State Connector - captures saga state machine transitions
curl -X POST "${CONNECT_URL}/connectors" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "sagastate-connector",
    "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "tasks.max": "1",
        "database.hostname": "order-db",
        "database.port": "5432",
        "database.user": "orderuser",
        "database.password": "orderpw",
        "database.dbname": "orderdb",
        "topic.prefix": "dbserver4",
        "schema.include.list": "purchaseorder",
        "table.include.list": "purchaseorder.sagastate",
        "tombstones.on.delete": "false",
        "slot.name": "debezium_sagastate",
        "plugin.name": "pgoutput",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "key.converter.schemas.enable": "false",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter.schemas.enable": "false",
        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "poll.interval.ms": "100",
        "producer.override.interceptor.classes": ""
    }
}'

echo ""

# OCEL Sink Connector - transforms CDC events to OCEL 2.0 JSON
curl -X POST "${CONNECT_URL}/connectors" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ocel-saga-sink",
    "config": {
        "connector.class": "io.debezium.connector.ocel.OcelSinkConnector",
        "tasks.max": "1",
        "topics": "dbserver4.purchaseorder.sagastate",
        "ocel.output.file.path": "/tmp/ocel-output/saga-events.json",
        "consumer.override.interceptor.classes": "",
        "consumer.override.auto.offset.reset": "earliest"
    }
}'

echo ""
echo "Done. Verify with: curl -s ${CONNECT_URL}/connectors | jq ."
