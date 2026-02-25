package io.debezium.connector.ocel;

import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.connect.connector.Task;
import org.apache.kafka.connect.sink.SinkConnector;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Kafka Connect Sink Connector that exports Debezium CDC events to OCEL 2.0 JSON format.
 */
public class OcelSinkConnector extends SinkConnector {

    public static final String OUTPUT_FILE_PATH_CONFIG = "ocel.output.file.path";

    private Map<String, String> config;

    @Override
    public String version() {
        return "1.0.0";
    }

    @Override
    public void start(Map<String, String> props) {
        this.config = props;
    }

    @Override
    public Class<? extends Task> taskClass() {
        return OcelSinkTask.class;
    }

    @Override
    public List<Map<String, String>> taskConfigs(int maxTasks) {
        List<Map<String, String>> configs = new ArrayList<>();
        configs.add(config);
        return configs;
    }

    @Override
    public void stop() {
        // Nothing to clean up
    }

    @Override
    public ConfigDef config() {
        return new ConfigDef()
            .define(OUTPUT_FILE_PATH_CONFIG,
                    ConfigDef.Type.STRING,
                    ConfigDef.NO_DEFAULT_VALUE,
                    ConfigDef.Importance.HIGH,
                    "Path to output OCEL 2.0 JSON file");
    }
}
