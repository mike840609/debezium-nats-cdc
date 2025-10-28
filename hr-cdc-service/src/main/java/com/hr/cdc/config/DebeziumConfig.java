package com.hr.cdc.config;

import com.hr.cdc.handler.CdcEventHandler;
import io.debezium.engine.ChangeEvent;
import io.debezium.engine.DebeziumEngine;
import io.debezium.engine.format.Json;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.io.IOException;
import java.util.Properties;
import java.util.concurrent.Executor;
import java.util.concurrent.Executors;

/**
 * Configuration for embedded Debezium engine.
 */
@Slf4j
@Configuration
public class DebeziumConfig {

    @Value("${debezium.connector.class}")
    private String connectorClass;

    @Value("${debezium.name}")
    private String connectorName;

    @Value("${debezium.offset.storage}")
    private String offsetStorage;

    @Value("${debezium.offset.storage.file.filename}")
    private String offsetStorageFileName;

    @Value("${debezium.offset.flush.interval.ms}")
    private String offsetFlushIntervalMs;

    @Value("${debezium.database.hostname}")
    private String databaseHostname;

    @Value("${debezium.database.port}")
    private String databasePort;

    @Value("${debezium.database.user}")
    private String databaseUser;

    @Value("${debezium.database.password}")
    private String databasePassword;

    @Value("${debezium.database.dbname}")
    private String databaseName;

    @Value("${debezium.database.server.id}")
    private String serverId;

    @Value("${debezium.database.server.name}")
    private String serverName;

    @Value("${debezium.table.include.list}")
    private String tableIncludeList;

    @Value("${debezium.snapshot.mode}")
    private String snapshotMode;

    @Value("${debezium.schema.history.internal}")
    private String schemaHistory;

    @Value("${debezium.schema.history.internal.file.filename}")
    private String schemaHistoryFileName;

    /**
     * Creates the Debezium engine configuration.
     */
    private Properties buildDebeziumProperties() {
        Properties props = new Properties();

        // Connector config
        props.setProperty("name", connectorName);
        props.setProperty("connector.class", connectorClass);

        // Offset storage
        props.setProperty("offset.storage", offsetStorage);
        props.setProperty("offset.storage.file.filename", offsetStorageFileName);
        props.setProperty("offset.flush.interval.ms", offsetFlushIntervalMs);

        // Database connection
        props.setProperty("database.hostname", databaseHostname);
        props.setProperty("database.port", databasePort);
        props.setProperty("database.user", databaseUser);
        props.setProperty("database.password", databasePassword);
        props.setProperty("database.dbname", databaseName);
        props.setProperty("database.server.id", serverId);
        props.setProperty("database.server.name", serverName);

        // What to capture
        props.setProperty("table.include.list", tableIncludeList);
        props.setProperty("snapshot.mode", snapshotMode);

        // Schema history
        props.setProperty("schema.history.internal", schemaHistory);
        props.setProperty("schema.history.internal.file.filename", schemaHistoryFileName);

        // Additional settings
        props.setProperty("include.schema.changes", "false");
        props.setProperty("topic.prefix", "hr");

        return props;
    }

    /**
     * Creates the Debezium engine bean.
     */
    @Bean
    public DebeziumEngine<ChangeEvent<String, String>> debeziumEngine(CdcEventHandler eventHandler) {
        Properties props = buildDebeziumProperties();

        return DebeziumEngine.create(Json.class)
                .using(props)
                .notifying(eventHandler::handleChangeEvent)
                .build();
    }

    /**
     * Starts the Debezium engine in a separate thread.
     */
    @Bean
    public Executor debeziumExecutor(DebeziumEngine<ChangeEvent<String, String>> debeziumEngine) {
        Executor executor = Executors.newSingleThreadExecutor();
        executor.execute(() -> {
            log.info("Starting Debezium embedded engine...");
            try {
                debeziumEngine.run();
            } catch (IOException e) {
                log.error("Error running Debezium engine", e);
            }
        });
        return executor;
    }
}
