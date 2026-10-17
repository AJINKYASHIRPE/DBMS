package com.bank.backend;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.NestedExceptionUtils;
import org.springframework.dao.DataAccessException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.sql.SQLException;
import java.util.Map;

@RestControllerAdvice
public class ApiExceptionHandler {
    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(DataAccessException.class)
    public ResponseEntity<Map<String, String>> db(DataAccessException e) {
        Throwable root = NestedExceptionUtils.getMostSpecificCause(e);
        if (root instanceof SQLException s && "45000".equals(s.getSQLState())) {
            return ResponseEntity.badRequest().body(Map.of("error", s.getMessage()));
        }
        log.error("Database error", e);
        return ResponseEntity.status(500).body(Map.of("error", "Database error"));
    }
}
