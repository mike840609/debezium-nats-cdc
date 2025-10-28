package com.hr.cdc;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Main Spring Boot application for HR CDC Service.
 *
 * This application uses embedded Debezium to capture change data from MariaDB
 * and process HR-related events in real-time.
 */
@SpringBootApplication
public class HrCdcApplication {

    public static void main(String[] args) {
        SpringApplication.run(HrCdcApplication.class, args);
    }
}
