package com.bank.backend;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/customer")
public class CustomerController {
    private static final BigDecimal LOAN_RATE = new BigDecimal("12.00");

    private final JdbcTemplate jdbc;

    public CustomerController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    record AmountRequest(BigDecimal amount) {}
    record TransferRequest(String toAccount, BigDecimal amount) {}
    record LoanRequest(BigDecimal amount, int months) {}

    @GetMapping("/me")
    public Map<String, Object> me(Authentication a) {
        return jdbc.queryForMap(
                "SELECT account_no, name, balance, created_at FROM accounts WHERE account_no = ?",
                a.getName());
    }

    @PostMapping("/deposit")
    public Map<String, Object> deposit(Authentication a, @RequestBody AmountRequest r) {
        jdbc.update("CALL sp_deposit(?, ?)", a.getName(), r.amount());
        return me(a);
    }

    @PostMapping("/withdraw")
    public Map<String, Object> withdraw(Authentication a, @RequestBody AmountRequest r) {
        jdbc.update("CALL sp_withdraw(?, ?)", a.getName(), r.amount());
        return me(a);
    }

    @PostMapping("/transfer")
    public Map<String, Object> transfer(Authentication a, @RequestBody TransferRequest r) {
        jdbc.update("CALL sp_transfer(?, ?, ?)", a.getName(), r.toAccount(), r.amount());
        return me(a);
    }

    @GetMapping("/transactions")
    public List<Map<String, Object>> transactions(Authentication a) {
        return jdbc.queryForList(
                "SELECT txn_id, txn_type, amount, other_account, description, txn_time " +
                "FROM transactions WHERE account_no = ? ORDER BY txn_time DESC, txn_id DESC LIMIT 50",
                a.getName());
    }

    @GetMapping("/loans")
    public List<Map<String, Object>> loans(Authentication a) {
        return jdbc.queryForList(
                "SELECT * FROM loan_status WHERE account_no = ? ORDER BY loan_id DESC", a.getName());
    }

    @PostMapping("/loans")
    public Map<String, Object> takeLoan(Authentication a, @RequestBody LoanRequest r) {
        jdbc.update("CALL sp_take_loan(?, ?, ?, ?)", a.getName(), r.amount(), r.months(), LOAN_RATE);
        return me(a);
    }

    @PostMapping("/loans/pay-emi")
    public Map<String, Object> payEmi(Authentication a) {
        jdbc.update("CALL sp_pay_emi(?)", a.getName());
        return me(a);
    }
}
