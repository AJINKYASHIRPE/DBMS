package com.bank.backend;

import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/admin")
public class AdminController {
    private final JdbcTemplate jdbc;

    public AdminController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    record NewAccount(String name, String pin, BigDecimal initialDeposit) {}

    @GetMapping("/accounts")
    public List<Map<String, Object>> accounts() {
        return jdbc.queryForList(
                "SELECT account_no, name, balance, created_at FROM accounts ORDER BY account_no");
    }

    @PostMapping("/accounts")
    public Map<String, Object> createAccount(@RequestBody NewAccount r) {
        String no = jdbc.queryForObject("CALL sp_create_account(?, ?, ?)", String.class,
                r.name(), r.pin(), r.initialDeposit());
        return Map.of("accountNo", no);
    }

    @GetMapping("/accounts/{accountNo}/transactions")
    public List<Map<String, Object>> transactions(@PathVariable String accountNo) {
        return jdbc.queryForList(
                "SELECT txn_id, txn_type, amount, other_account, description, txn_time " +
                "FROM transactions WHERE account_no = ? ORDER BY txn_time DESC, txn_id DESC",
                accountNo);
    }

    record PinReset(String pin) {}

    @PostMapping("/accounts/{accountNo}/reset-pin")
    public ResponseEntity<Map<String, String>> resetPin(@PathVariable String accountNo,
                                                        @RequestBody PinReset r) {
        if (r.pin() == null || !r.pin().matches("[0-9]{4}"))
            return ResponseEntity.badRequest().body(Map.of("error", "PIN must be exactly 4 digits"));
        int n = jdbc.update("UPDATE accounts SET pin_hash = SHA2(?, 256) WHERE account_no = ?",
                r.pin(), accountNo);
        if (n == 0)
            return ResponseEntity.status(404).body(Map.of("error", "Account not found"));
        return ResponseEntity.ok(Map.of("status", "PIN updated"));
    }

    @GetMapping("/loans")
    public List<Map<String, Object>> loans() {
        return jdbc.queryForList(
                "SELECT a.name, ls.* FROM loan_status ls " +
                "JOIN accounts a ON a.account_no = ls.account_no ORDER BY ls.loan_id");
    }
}
