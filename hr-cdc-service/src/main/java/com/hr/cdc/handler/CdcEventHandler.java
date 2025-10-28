package com.hr.cdc.handler;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.debezium.engine.ChangeEvent;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.Map;

/**
 * Handles CDC events from Debezium.
 * This is where you process database changes and implement your business logic.
 */
@Slf4j
@Component
public class CdcEventHandler {

    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * Process a CDC change event from the database.
     *
     * @param event The change event from Debezium
     */
    public void handleChangeEvent(ChangeEvent<String, String> event) {
        try {
            String key = event.key();
            String value = event.value();

            if (value == null) {
                log.debug("Received tombstone event (delete marker) with key: {}", key);
                return;
            }

            // Parse the change event
            Map<String, Object> changeEvent = objectMapper.readValue(value, Map.class);

            // Extract metadata
            Map<String, Object> source = (Map<String, Object>) changeEvent.get("source");
            String operation = (String) changeEvent.get("op");
            String table = (String) source.get("table");
            Long timestamp = (Long) changeEvent.get("ts_ms");

            // Extract data
            Map<String, Object> before = (Map<String, Object>) changeEvent.get("before");
            Map<String, Object> after = (Map<String, Object>) changeEvent.get("after");

            // Log the event
            log.info("CDC Event - Table: {}, Operation: {}, Timestamp: {}", table, operation, timestamp);

            // Route to specific handlers based on table
            switch (table) {
                case "employees":
                    handleEmployeeChange(operation, before, after);
                    break;
                case "salary_changes":
                    handleSalaryChange(operation, before, after);
                    break;
                case "departments":
                    handleDepartmentChange(operation, before, after);
                    break;
                case "positions":
                    handlePositionChange(operation, before, after);
                    break;
                case "leave_requests":
                    handleLeaveRequestChange(operation, before, after);
                    break;
                case "attendance_records":
                    handleAttendanceChange(operation, before, after);
                    break;
                default:
                    log.warn("Unhandled table: {}", table);
            }

        } catch (Exception e) {
            log.error("Error processing CDC event", e);
        }
    }

    private void handleEmployeeChange(String operation, Map<String, Object> before, Map<String, Object> after) {
        switch (operation) {
            case "c": // Create
                log.info("New employee created: {}", after);
                // TODO: Publish EmployeeHired event
                break;
            case "u": // Update
                log.info("Employee updated - Before: {}, After: {}", before, after);
                // TODO: Detect specific changes (promotion, transfer, etc.)
                detectEmployeeUpdates(before, after);
                break;
            case "d": // Delete
                log.info("Employee deleted: {}", before);
                // TODO: Publish EmployeeTerminated event
                break;
            case "r": // Read (snapshot)
                log.debug("Employee snapshot: {}", after);
                break;
        }
    }

    private void detectEmployeeUpdates(Map<String, Object> before, Map<String, Object> after) {
        // Detect promotion (position change)
        if (!equals(before.get("position_id"), after.get("position_id"))) {
            log.info("Employee promoted: position changed from {} to {}",
                    before.get("position_id"), after.get("position_id"));
            // TODO: Publish EmployeePromoted event
        }

        // Detect transfer (department change)
        if (!equals(before.get("department_id"), after.get("department_id"))) {
            log.info("Employee transferred: department changed from {} to {}",
                    before.get("department_id"), after.get("department_id"));
            // TODO: Publish EmployeeTransferred event
        }

        // Detect status change
        if (!equals(before.get("status"), after.get("status"))) {
            log.info("Employee status changed: {} -> {}",
                    before.get("status"), after.get("status"));
            // TODO: Publish appropriate status event
        }
    }

    private void handleSalaryChange(String operation, Map<String, Object> before, Map<String, Object> after) {
        if (operation.equals("c")) {
            log.info("New salary change recorded: {}", after);
            // TODO: Publish SalaryAdjusted event
        }
    }

    private void handleDepartmentChange(String operation, Map<String, Object> before, Map<String, Object> after) {
        switch (operation) {
            case "c":
                log.info("New department created: {}", after);
                // TODO: Publish DepartmentCreated event
                break;
            case "u":
                log.info("Department updated: {}", after);
                // TODO: Publish DepartmentRestructured event
                break;
        }
    }

    private void handlePositionChange(String operation, Map<String, Object> before, Map<String, Object> after) {
        if (operation.equals("c")) {
            log.info("New position created: {}", after);
        }
    }

    private void handleLeaveRequestChange(String operation, Map<String, Object> before, Map<String, Object> after) {
        switch (operation) {
            case "c":
                log.info("Leave request submitted: {}", after);
                // TODO: Publish LeaveRequestSubmitted event
                break;
            case "u":
                if (!equals(before.get("status"), after.get("status"))) {
                    log.info("Leave request status changed: {} -> {}",
                            before.get("status"), after.get("status"));
                    // TODO: Publish LeaveRequestApproved/Rejected event
                }
                break;
        }
    }

    private void handleAttendanceChange(String operation, Map<String, Object> before, Map<String, Object> after) {
        if (operation.equals("c")) {
            log.info("Attendance record created: {}", after);
            // TODO: Check for anomalies (late, absent, etc.)
        }
    }

    private boolean equals(Object o1, Object o2) {
        if (o1 == null && o2 == null) return true;
        if (o1 == null || o2 == null) return false;
        return o1.equals(o2);
    }
}
