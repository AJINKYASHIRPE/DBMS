package com.bank.backend;

import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private final JdbcTemplate jdbc;
    private final JwtUtil jwt;

    public AuthController(JdbcTemplate jdbc, JwtUtil jwt) {
        this.jdbc = jdbc;
        this.jwt = jwt;
    }

    record CustomerLogin(String accountNo, String pin) {}
    record AdminLogin(String username, String password) {}

    @PostMapping("/customer/login")
    public Map<String, Object> customerLogin(@RequestBody CustomerLogin r) {
        Integer n = jdbc.queryForObject(
                "SELECT COUNT(*) FROM accounts WHERE account_no = ? AND pin_hash = SHA2(?, 256)",
                Integer.class, r.accountNo(), r.pin());
        if (n == null || n == 0)
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid account number or PIN");
        return Map.of("token", jwt.create(r.accountNo(), "CUSTOMER"), "role", "CUSTOMER");
    }

    @PostMapping("/admin/login")
    public Map<String, Object> adminLogin(@RequestBody AdminLogin r) {
        Integer n = jdbc.queryForObject(
                "SELECT COUNT(*) FROM admins WHERE username = ? AND password_hash = SHA2(?, 256)",
                Integer.class, r.username(), r.password());
        if (n == null || n == 0)
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid username or password");
        return Map.of("token", jwt.create(r.username(), "ADMIN"), "role", "ADMIN");
    }
}
