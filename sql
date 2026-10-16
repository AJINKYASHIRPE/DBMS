DROP DATABASE IF EXISTS bank_db;
CREATE DATABASE bank_db;
USE bank_db;

-- ======================= TABLES =======================

CREATE TABLE admins (
    admin_id      INT AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL
);

CREATE TABLE accounts (
    account_no VARCHAR(10)   PRIMARY KEY,
    name       VARCHAR(100)  NOT NULL,
    pin_hash   VARCHAR(255)  NOT NULL,
    balance    DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    created_at DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE transactions (
    txn_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
    account_no    VARCHAR(10)   NOT NULL,
    txn_type      ENUM('CREATE','DEPOSIT','WITHDRAW','TRANSFER_OUT',
                       'TRANSFER_IN','LOAN_CREDIT','EMI_PAID') NOT NULL,
    amount        DECIMAL(12,2) NOT NULL,
    other_account VARCHAR(10)   NULL,
    description   VARCHAR(200),
    txn_time      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (account_no) REFERENCES accounts(account_no)
);

CREATE TABLE loans (
    loan_id       INT AUTO_INCREMENT PRIMARY KEY,
    account_no    VARCHAR(10)   NOT NULL,
    principal     DECIMAL(12,2) NOT NULL,
    interest_rate DECIMAL(5,2)  NOT NULL,
    months        INT           NOT NULL,
    emi           DECIMAL(12,2) NOT NULL,
    start_date    DATE          NOT NULL,
    FOREIGN KEY (account_no) REFERENCES accounts(account_no)
);

CREATE TABLE installments (
    inst_id   INT AUTO_INCREMENT PRIMARY KEY,
    loan_id   INT           NOT NULL,
    inst_no   INT           NOT NULL,
    due_date  DATE          NOT NULL,
    amount    DECIMAL(12,2) NOT NULL,
    paid_date DATE          NULL,          -- NULL = not paid yet
    UNIQUE (loan_id, inst_no),
    FOREIGN KEY (loan_id) REFERENCES loans(loan_id)
);

-- ======================= VIEW =======================
-- Loan status for admin AND customer: CLOSED / PAYING ON TIME / NOT PAYING ON TIME
CREATE VIEW loan_status AS
SELECT l.loan_id, l.account_no, l.principal, l.emi,
       SUM(i.paid_date IS NOT NULL)                        AS emis_paid,
       l.months                                            AS total_emis,
       SUM(i.paid_date > i.due_date)                       AS late_payments,
       SUM(i.paid_date IS NULL AND i.due_date < CURDATE()) AS overdue_emis,
       SUM(CASE WHEN i.paid_date IS NULL THEN i.amount ELSE 0 END) AS outstanding,
       MIN(CASE WHEN i.paid_date IS NULL THEN i.due_date END)      AS next_due_date,
       CASE
         WHEN SUM(i.paid_date IS NULL) = 0 THEN 'CLOSED'
         WHEN SUM(i.paid_date IS NULL AND i.due_date < CURDATE()) > 0
              THEN 'NOT PAYING ON TIME'
         ELSE 'PAYING ON TIME'
       END AS status
FROM loans l
JOIN installments i ON i.loan_id = l.loan_id
GROUP BY l.loan_id, l.account_no, l.principal, l.emi, l.months;

-- ======================= PROCEDURES =======================
-- (DELIMITER works in the mysql command-line client)
DELIMITER $$

CREATE PROCEDURE sp_create_account(IN p_name VARCHAR(100), IN p_pin CHAR(4),
                                   IN p_initial DECIMAL(12,2))
BEGIN
    DECLARE v_no VARCHAR(10);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

    IF p_pin NOT REGEXP '^[0-9]{4}$' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PIN must be exactly 4 digits';
    END IF;
    IF p_initial < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deposit cannot be negative';
    END IF;

    START TRANSACTION;
    SELECT CAST(COALESCE(MAX(CAST(account_no AS UNSIGNED)), 100000) + 1 AS CHAR)
      INTO v_no FROM accounts;
    INSERT INTO accounts(account_no, name, pin_hash, balance)
        VALUES (v_no, p_name, SHA2(p_pin, 256), p_initial);
    INSERT INTO transactions(account_no, txn_type, amount, description)
        VALUES (v_no, 'CREATE', p_initial, 'Account created');
    COMMIT;
    SELECT v_no AS new_account_no;
END$$

CREATE PROCEDURE sp_deposit(IN p_acc VARCHAR(10), IN p_amt DECIMAL(12,2))
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    IF p_amt <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Amount must be greater than zero';
    END IF;

    START TRANSACTION;
    UPDATE accounts SET balance = balance + p_amt WHERE account_no = p_acc;
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account not found';
    END IF;
    INSERT INTO transactions(account_no, txn_type, amount, description)
        VALUES (p_acc, 'DEPOSIT', p_amt, 'Deposit');
    COMMIT;
END$$

CREATE PROCEDURE sp_withdraw(IN p_acc VARCHAR(10), IN p_amt DECIMAL(12,2))
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    IF p_amt <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Amount must be greater than zero';
    END IF;

    START TRANSACTION;
    UPDATE accounts SET balance = balance - p_amt
     WHERE account_no = p_acc AND balance >= p_amt;
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance or account not found';
    END IF;
    INSERT INTO transactions(account_no, txn_type, amount, description)
        VALUES (p_acc, 'WITHDRAW', p_amt, 'Withdrawal');
    COMMIT;
END$$

CREATE PROCEDURE sp_transfer(IN p_from VARCHAR(10), IN p_to VARCHAR(10),
                             IN p_amt DECIMAL(12,2))
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    IF p_amt <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Amount must be greater than zero';
    END IF;
    IF p_from = p_to THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot transfer to the same account';
    END IF;

    START TRANSACTION;
    UPDATE accounts SET balance = balance - p_amt
     WHERE account_no = p_from AND balance >= p_amt;
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance or sender not found';
    END IF;
    UPDATE accounts SET balance = balance + p_amt WHERE account_no = p_to;
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Receiver account does not exist';
    END IF;

    INSERT INTO transactions(account_no, txn_type, amount, other_account, description)
        VALUES (p_from, 'TRANSFER_OUT', p_amt, p_to, CONCAT('Transfer to ', p_to));
    INSERT INTO transactions(account_no, txn_type, amount, other_account, description)
        VALUES (p_to, 'TRANSFER_IN', p_amt, p_from, CONCAT('Transfer from ', p_from));
    COMMIT;
END$$

CREATE PROCEDURE sp_take_loan(IN p_acc VARCHAR(10), IN p_amt DECIMAL(12,2),
                              IN p_months INT, IN p_rate DECIMAL(5,2))
BEGIN
    DECLARE v_r DOUBLE;
    DECLARE v_emi DECIMAL(12,2);
    DECLARE v_loan INT;
    DECLARE v_i INT DEFAULT 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

    IF p_amt <= 0 OR p_amt > 1000000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Loan amount must be between 1 and 1000000';
    END IF;
    IF p_months < 3 OR p_months > 36 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tenure must be 3 to 36 months';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM accounts WHERE account_no = p_acc) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account not found';
    END IF;
    IF EXISTS (SELECT 1 FROM loan_status WHERE account_no = p_acc AND status <> 'CLOSED') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Customer already has an active loan';
    END IF;

    SET v_r = p_rate / 12 / 100;
    SET v_emi = ROUND(p_amt * v_r * POW(1 + v_r, p_months)
                      / (POW(1 + v_r, p_months) - 1), 2);

    START TRANSACTION;
    INSERT INTO loans(account_no, principal, interest_rate, months, emi, start_date)
        VALUES (p_acc, p_amt, p_rate, p_months, v_emi, CURDATE());
    SET v_loan = LAST_INSERT_ID();

    WHILE v_i <= p_months DO
        INSERT INTO installments(loan_id, inst_no, due_date, amount)
            VALUES (v_loan, v_i, DATE_ADD(CURDATE(), INTERVAL v_i MONTH), v_emi);
        SET v_i = v_i + 1;
    END WHILE;

    UPDATE accounts SET balance = balance + p_amt WHERE account_no = p_acc;
    INSERT INTO transactions(account_no, txn_type, amount, description)
        VALUES (p_acc, 'LOAN_CREDIT', p_amt,
                CONCAT('Loan credited (EMI ', v_emi, ' x ', p_months, ')'));
    COMMIT;
END$$

CREATE PROCEDURE sp_pay_emi(IN p_acc VARCHAR(10))
BEGIN
    DECLARE v_loan INT;
    DECLARE v_inst INT;
    DECLARE v_no INT;
    DECLARE v_amt DECIMAL(12,2);
    DECLARE v_due DATE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

    START TRANSACTION;

    SELECT loan_id INTO v_loan FROM loan_status
     WHERE account_no = p_acc AND status <> 'CLOSED' LIMIT 1;
    IF v_loan IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No active loan';
    END IF;

    SELECT inst_id, inst_no, amount, due_date INTO v_inst, v_no, v_amt, v_due
      FROM installments
     WHERE loan_id = v_loan AND paid_date IS NULL
     ORDER BY inst_no LIMIT 1 FOR UPDATE;

    UPDATE accounts SET balance = balance - v_amt
     WHERE account_no = p_acc AND balance >= v_amt;
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance to pay EMI';
    END IF;

    UPDATE installments SET paid_date = CURDATE() WHERE inst_id = v_inst;
    INSERT INTO transactions(account_no, txn_type, amount, description)
        VALUES (p_acc, 'EMI_PAID', v_amt,
                CONCAT('EMI #', v_no, IF(CURDATE() > v_due, ' (LATE)', ' (on time)')));
    COMMIT;
END$$

DELIMITER ;

USE bank_db;

-- ============ CLEAR OLD SAMPLE DATA (admins table is kept) ============
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE installments;
TRUNCATE TABLE loans;
TRUNCATE TABLE transactions;
TRUNCATE TABLE accounts;
SET FOREIGN_KEY_CHECKS = 1;

-- ============ 12 CUSTOMERS (balances are calculated at the end) ============
INSERT INTO accounts (account_no, name, pin_hash, balance, created_at) VALUES
('100001', 'Ravi Sharma',     SHA2('1111',256), 0, DATE_SUB(NOW(), INTERVAL 14 MONTH)),
('100002', 'Priya Singh',     SHA2('2222',256), 0, DATE_SUB(NOW(), INTERVAL 13 MONTH)),
('100003', 'Amit Verma',      SHA2('3333',256), 0, DATE_SUB(NOW(), INTERVAL 8 MONTH)),
('100004', 'Sneha Patil',     SHA2('4444',256), 0, DATE_SUB(NOW(), INTERVAL 12 MONTH)),
('100005', 'Rahul Deshmukh',  SHA2('5555',256), 0, DATE_SUB(NOW(), INTERVAL 11 MONTH)),
('100006', 'Anjali Gupta',    SHA2('6666',256), 0, DATE_SUB(NOW(), INTERVAL 15 MONTH)),
('100007', 'Vikram Joshi',    SHA2('7777',256), 0, DATE_SUB(NOW(), INTERVAL 9 MONTH)),
('100008', 'Neha Kulkarni',   SHA2('8888',256), 0, DATE_SUB(NOW(), INTERVAL 3 MONTH)),
('100009', 'Suresh Yadav',    SHA2('9999',256), 0, DATE_SUB(NOW(), INTERVAL 7 MONTH)),
('100010', 'Pooja Nair',      SHA2('1010',256), 0, DATE_SUB(NOW(), INTERVAL 20 MONTH)),
('100011', 'Karan Mehta',     SHA2('1212',256), 0, DATE_SUB(NOW(), INTERVAL 18 MONTH)),
('100012', 'Divya Reddy',     SHA2('1313',256), 0, DATE_SUB(NOW(), INTERVAL 4 MONTH));

-- ============ NORMAL TRANSACTIONS ============
INSERT INTO transactions (account_no, txn_type, amount, other_account, description, txn_time) VALUES
-- Ravi (no loan)
('100001','CREATE',      15000, NULL,     'Account created',          DATE_SUB(NOW(), INTERVAL 14 MONTH)),
('100001','DEPOSIT',      8000, NULL,     'Deposit',                  DATE_SUB(NOW(), INTERVAL 6 MONTH)),
('100001','TRANSFER_OUT', 3000, '100002', 'Transfer to 100002',       DATE_SUB(NOW(), INTERVAL 70 DAY)),
('100001','WITHDRAW',     5000, NULL,     'Withdrawal',               DATE_SUB(NOW(), INTERVAL 30 DAY)),
-- Priya (no loan)
('100002','CREATE',      30000, NULL,     'Account created',          DATE_SUB(NOW(), INTERVAL 13 MONTH)),
('100002','DEPOSIT',     15500, NULL,     'Deposit',                  DATE_SUB(NOW(), INTERVAL 5 MONTH)),
('100002','TRANSFER_IN',  3000, '100001', 'Transfer from 100001',     DATE_SUB(NOW(), INTERVAL 70 DAY)),
-- Amit
('100003','CREATE',      10000, NULL,     'Account created',          DATE_SUB(NOW(), INTERVAL 8 MONTH)),
('100003','DEPOSIT',      4000, NULL,     'Deposit',                  DATE_SUB(NOW(), INTERVAL 5 MONTH)),
-- Sneha
('100004','CREATE',      20000, NULL,     'Account created',          DATE_SUB(NOW(), INTERVAL 12 MONTH)),
('100004','WITHDRAW',     8000, NULL,     'Withdrawal',               DATE_SUB(NOW(), INTERVAL 8 MONTH)),
-- Rahul
('100005','CREATE',      12000, NULL,     'Account created',          DATE_SUB(NOW(), INTERVAL 11 MONTH)),
('100005','DEPOSIT',      3000, NULL,     'Deposit',                  DATE_SUB(NOW(), INTERVAL 7 MONTH)),
-- Anjali
('100006','CREATE',       7000, NULL,     'Account created',          DATE_SUB(NOW(), INTERVAL 15 MONTH)),
('100006','DEPOSIT',      2500, NULL,     'Deposit',                  DATE_SUB(NOW(), INTERVAL 10 MONTH)),
-- Vikram
('100007','CREATE',      18000, NULL,     'Account created',          DATE_SUB(NOW(), INTERVAL 9 MONTH)),
('100007','WITHDRAW',     6000, NULL,     'Withdrawal',               DATE_SUB(NOW(), INTERVAL 6 MONTH)),
-- Neha
('100008','CREATE',      25000, NULL,     'Account created',          DATE_SUB(NOW(), INTERVAL 3 MONTH)),
-- Suresh
('100009','CREATE',       6000, NULL,     'Account created',          DATE_SUB(NOW(), INTERVAL 7 MONTH)),
('100009','WITHDRAW',     2500, NULL,     'Withdrawal',               DATE_SUB(NOW(), INTERVAL 90 DAY)),
-- Pooja (no loan, high balance)
('100010','CREATE',     100000, NULL,     'Account created',          DATE_SUB(NOW(), INTERVAL 20 MONTH)),
('100010','DEPOSIT',     50000, NULL,     'Deposit',                  DATE_SUB(NOW(), INTERVAL 9 MONTH)),
-- Karan
('100011','CREATE',      80000, NULL,     'Account created',          DATE_SUB(NOW(), INTERVAL 18 MONTH)),
('100011','DEPOSIT',    120000, NULL,     'Deposit',                  DATE_SUB(NOW(), INTERVAL 12 MONTH)),
-- Divya
('100012','CREATE',        300, NULL,     'Account created',          DATE_SUB(NOW(), INTERVAL 4 MONTH)),
('100012','WITHDRAW',     2000, NULL,     'Withdrawal',               DATE_SUB(NOW(), INTERVAL 50 DAY));

-- ============ LOANS (12% p.a.) ============
INSERT INTO loans (loan_id, account_no, principal, interest_rate, months, emi, start_date) VALUES
(1,  '100003',  12000, 12.00,  6,  2070.58, DATE_SUB(CURDATE(), INTERVAL 3 MONTH)),
(2,  '100004',  60000, 12.00, 12,  5330.93, DATE_SUB(CURDATE(), INTERVAL 6 MONTH)),
(3,  '100005',   9000, 12.00,  3,  3060.20, DATE_SUB(CURDATE(), INTERVAL 5 MONTH)),
(4,  '100006',  18000, 12.00,  6,  3106.07, DATE_SUB(CURDATE(), INTERVAL 8 MONTH)),
(5,  '100007',  36000, 12.00, 12,  3198.56, DATE_SUB(CURDATE(), INTERVAL 4 MONTH)),
(6,  '100008', 100000, 12.00, 24,  4707.35, CURDATE()),
(7,  '100009',  30000, 12.00, 12,  2665.46, DATE_SUB(DATE_SUB(CURDATE(), INTERVAL 1 MONTH), INTERVAL 10 DAY)),
(8,  '100011', 500000, 12.00, 36, 16607.15, DATE_SUB(CURDATE(), INTERVAL 10 MONTH)),
(9,  '100012',   3000, 12.00,  3,  1020.07, DATE_SUB(CURDATE(), INTERVAL 2 MONTH)),
(10, '100005',  20000, 12.00,  6,  3451.19, DATE_SUB(CURDATE(), INTERVAL 1 MONTH));

-- ============ EMI SCHEDULES (generated for every loan) ============
CREATE TEMPORARY TABLE nums (n INT PRIMARY KEY);
INSERT INTO nums VALUES
(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15),(16),(17),(18),
(19),(20),(21),(22),(23),(24),(25),(26),(27),(28),(29),(30),(31),(32),(33),(34),(35),(36);

INSERT INTO installments (loan_id, inst_no, due_date, amount)
SELECT l.loan_id, nums.n, DATE_ADD(l.start_date, INTERVAL nums.n MONTH), l.emi
FROM loans l JOIN nums ON nums.n <= l.months;

DROP TEMPORARY TABLE nums;

-- ============ WHICH EMIs WERE PAID ============
-- Paid on the due date (on time)
UPDATE installments SET paid_date = due_date WHERE due_date <= CURDATE() AND (
      (loan_id = 1 AND inst_no <= 3)
   OR (loan_id = 2 AND inst_no <= 2)
   OR (loan_id = 3 AND inst_no <= 3)
   OR (loan_id = 4 AND inst_no IN (1,3,5))
   OR (loan_id = 5 AND inst_no IN (1,3,4))
   OR (loan_id = 8 AND inst_no <= 10)
   OR (loan_id = 9 AND inst_no = 1));

-- Paid after the due date (late)
UPDATE installments SET paid_date = DATE_ADD(due_date, INTERVAL 7 DAY)  WHERE loan_id = 4 AND inst_no = 2;
UPDATE installments SET paid_date = DATE_ADD(due_date, INTERVAL 12 DAY) WHERE loan_id = 4 AND inst_no = 4;
UPDATE installments SET paid_date = DATE_ADD(due_date, INTERVAL 3 DAY)  WHERE loan_id = 4 AND inst_no = 6;
UPDATE installments SET paid_date = DATE_ADD(due_date, INTERVAL 9 DAY)  WHERE loan_id = 5 AND inst_no = 2;

-- ============ LOAN + EMI TRANSACTIONS (so statements match) ============
INSERT INTO transactions (account_no, txn_type, amount, description, txn_time)
SELECT account_no, 'LOAN_CREDIT', principal,
       CONCAT('Loan credited (EMI ', emi, ' x ', months, ')'),
       TIMESTAMP(start_date, '09:00:00')
FROM loans;

INSERT INTO transactions (account_no, txn_type, amount, description, txn_time)
SELECT l.account_no, 'EMI_PAID', i.amount,
       CONCAT('EMI #', i.inst_no, IF(i.paid_date > i.due_date, ' (LATE)', ' (on time)')),
       TIMESTAMP(i.paid_date, '10:30:00')
FROM installments i JOIN loans l ON l.loan_id = i.loan_id
WHERE i.paid_date IS NOT NULL;

-- ============ SET BALANCES FROM THE TRANSACTION HISTORY ============
UPDATE accounts a
SET balance = (SELECT COALESCE(SUM(CASE
                    WHEN t.txn_type IN ('CREATE','DEPOSIT','TRANSFER_IN','LOAN_CREDIT')
                    THEN t.amount ELSE -t.amount END), 0)
               FROM transactions t WHERE t.account_no = a.account_no);

USE bank_db;

SHOW DATABASES;
SHOW TABLES;

DESC admins;
DESC accounts;
DESC transactions;
DESC loans;
DESC installments;

select * from accounts;
select * from loans;
select * from installments;
select * from transactions;
select * from admins;

SELECT account_no, name, balance FROM accounts;
SELECT loan_id, account_no, principal, emi FROM loans;
SELECT txn_id, account_no, txn_type, amount FROM transactions;

INSERT INTO accounts
(account_no, name, pin_hash, balance)
VALUES
('200002', 'Test Customer Two', SHA2('1357', 256), 8000),
('200003', 'Test Customer Three', SHA2('9876', 256), 12000);

UPDATE accounts
SET name = 'Updated Customer'
WHERE account_no = '200001';
UPDATE accounts
SET balance = balance + 1000
WHERE account_no = '200001';

DELETE FROM transactions
WHERE txn_id = 1;

SELECT * FROM accounts
WHERE account_no LIKE '200%';

SELECT name, balance, balance + 1000 AS increased_balance
FROM accounts;

SELECT name, balance, balance - 500 AS calculated_balance
FROM accounts;

SELECT loan_id, emi, months, emi * months AS total_scheduled_payments
FROM loans;

SELECT loan_id, principal, months,
       principal / months AS average_principal_per_month
FROM loans;

SELECT loan_id, principal, principal % 1000 AS remainder
FROM loans;

SELECT * FROM accounts
WHERE balance = 5000;

SELECT * FROM accounts
WHERE balance <> 5000;

SELECT * FROM accounts
WHERE balance > 10000;

SELECT * FROM accounts
WHERE balance < 10000;

SELECT * FROM loans
WHERE principal >= 50000;

SELECT * FROM loans
WHERE months <= 12;

SELECT * FROM accounts
WHERE balance > 10000 AND name LIKE 'P%';

SELECT * FROM accounts
WHERE balance < 5000 OR balance > 100000;

SELECT * FROM accounts
WHERE NOT balance = 0;

SELECT * FROM accounts
WHERE balance BETWEEN 10000 AND 50000;

SELECT * FROM accounts
WHERE balance > 20000;

SELECT * FROM accounts
WHERE name LIKE 'P%';

SELECT * FROM accounts
WHERE name LIKE '%a';

SELECT * FROM accounts
WHERE name LIKE '%sh%';

SELECT * FROM accounts
WHERE name LIKE '_a%';

SELECT DISTINCT txn_type
FROM transactions;

SELECT * FROM transactions
WHERE other_account IS NULL;

SELECT * FROM transactions
WHERE other_account IS NOT NULL;
SELECT * FROM transactions
WHERE txn_type IN ('DEPOSIT', 'WITHDRAW');

SELECT * FROM transactions
WHERE txn_type NOT IN ('DEPOSIT', 'WITHDRAW');

SELECT name, balance
FROM accounts
ORDER BY balance ASC;

SELECT name, balance
FROM accounts
ORDER BY balance DESC;

SELECT * FROM accounts
ORDER BY name ASC;

SELECT name, balance
FROM accounts
ORDER BY balance DESC
LIMIT 5;

SELECT * FROM transactions
ORDER BY txn_time DESC
LIMIT 3;

SELECT * FROM accounts
ORDER BY account_no
LIMIT 5 OFFSET 5;

SELECT COUNT(*) AS total_accounts
FROM accounts;

SELECT SUM(balance) AS total_balance
FROM accounts;

SELECT AVG(balance) AS average_balance
FROM accounts;

SELECT MAX(balance) AS highest_balance
FROM accounts;

SELECT MIN(balance) AS lowest_balance
FROM accounts;

SELECT SUM(principal) AS total_loan_amount
FROM loans;

SELECT AVG(emi) AS average_emi
FROM loans;

SELECT txn_type, COUNT(*) AS total_transactions
FROM transactions
GROUP BY txn_type;

SELECT txn_type, SUM(amount) AS total_amount
FROM transactions
GROUP BY txn_type;

SELECT account_no, COUNT(*) AS total_loans
FROM loans
GROUP BY account_no;

SELECT account_no, COUNT(*) AS total_loans
FROM loans
GROUP BY account_no
HAVING COUNT(*) > 1;

SELECT txn_type, SUM(amount) AS total_amount
FROM transactions
GROUP BY txn_type
HAVING SUM(amount) > 10000;

SELECT account_no, SUM(amount) AS total_deposits
FROM transactions
WHERE txn_type = 'DEPOSIT'
GROUP BY account_no
HAVING SUM(amount) > 5000;

SELECT txn_type, COUNT(*) AS total_transactions
FROM transactions
GROUP BY txn_type;

SELECT txn_type, SUM(amount) AS total_amount
FROM transactions
GROUP BY txn_type;

SELECT account_no, COUNT(*) AS total_loans
FROM loans
GROUP BY account_no;

SELECT account_no, COUNT(*) AS total_loans
FROM loans
GROUP BY account_no
HAVING COUNT(*) > 1;

SELECT txn_type, SUM(amount) AS total_amount
FROM transactions
GROUP BY txn_type
HAVING SUM(amount) > 10000;

SELECT account_no, SUM(amount) AS total_deposits
FROM transactions
WHERE txn_type = 'DEPOSIT'
GROUP BY account_no
HAVING SUM(amount) > 5000;

SELECT a.account_no, a.name, l.loan_id, l.principal, l.emi
FROM accounts a
INNER JOIN loans l
ON a.account_no = l.account_no;

SELECT l.loan_id, l.account_no, i.inst_no,
       i.due_date, i.amount, i.paid_date
FROM loans l
INNER JOIN installments i
ON l.loan_id = i.loan_id;

SELECT t.txn_id, a.name, t.txn_type,
       t.amount, t.txn_time
FROM transactions t
INNER JOIN accounts a
ON t.account_no = a.account_no;

SELECT a.account_no, a.name, l.loan_id, l.principal
FROM accounts a
LEFT JOIN loans l
ON a.account_no = l.account_no;

SELECT a.account_no, a.name
FROM accounts a
LEFT JOIN loans l
ON a.account_no = l.account_no
WHERE l.loan_id IS NULL;

SELECT a.name, l.loan_id, l.principal
FROM accounts a
RIGHT JOIN loans l
ON a.account_no = l.account_no;

SELECT a.name, l.loan_id, l.principal,
       i.inst_no, i.due_date, i.paid_date
FROM accounts a
JOIN loans l
ON a.account_no = l.account_no
JOIN installments i
ON l.loan_id = i.loan_id
ORDER BY l.loan_id, i.inst_no;

-- Find pairs of accounts with the same balance
SELECT a.name AS customer_one,
       b.name AS customer_two,
       a.balance
FROM accounts a
JOIN accounts b
ON a.balance = b.balance
AND a.account_no < b.account_no;

SELECT a.name, l.loan_id
FROM accounts a
CROSS JOIN loans l
LIMIT 20;

SELECT name, balance
FROM accounts
WHERE balance > (
    SELECT AVG(balance) FROM accounts
);

SELECT name, balance
FROM accounts
WHERE balance = (
    SELECT MAX(balance) FROM accounts
);

SELECT *
FROM loans
WHERE principal > (
    SELECT AVG(principal) FROM loans
);

SELECT *
FROM accounts
WHERE account_no IN (
    SELECT account_no FROM loans
);

SELECT *
FROM accounts a
WHERE EXISTS (
    SELECT 1
    FROM transactions t
    WHERE t.account_no = a.account_no
);

SELECT *
FROM accounts a
WHERE NOT EXISTS (
    SELECT 1
    FROM loans l
    WHERE l.account_no = a.account_no
);

SELECT name, balance,
       CASE
           WHEN balance >= 100000 THEN 'High Balance'
           WHEN balance >= 50000 THEN 'Medium Balance'
           ELSE 'Low Balance'
       END AS balance_category
FROM accounts;

SELECT txn_id, txn_type, amount,
       CASE
           WHEN txn_type = 'DEPOSIT' THEN 'Money In'
           WHEN txn_type = 'WITHDRAW' THEN 'Money Out'
           WHEN txn_type = 'TRANSFER_IN' THEN 'Money In'
           WHEN txn_type = 'TRANSFER_OUT' THEN 'Money Out'
           ELSE 'Other Transaction'
       END AS transaction_category
FROM transactions;

SELECT CURDATE(), NOW();

SELECT txn_id, YEAR(txn_time) AS txn_year,
       MONTH(txn_time) AS txn_month
FROM transactions;

SELECT *
FROM transactions
WHERE txn_time >= DATE_SUB(NOW(), INTERVAL 30 DAY);

SELECT txn_id, DATE_FORMAT(txn_time, '%d-%m-%Y') AS formatted_date
FROM transactions;

SELECT name, created_at,
       DATEDIFF(NOW(), created_at) AS account_age_days
FROM accounts;

SELECT UPPER(name), LOWER(name)
FROM accounts;

SELECT name, LENGTH(name) AS name_length
FROM accounts;

SELECT CONCAT(name, ' - ', account_no) AS customer_details
FROM accounts;

SELECT loan_id, emi, ROUND(emi) AS rounded_emi
FROM loans;

SELECT account_no FROM accounts
UNION
SELECT account_no FROM loans;

SELECT account_no FROM accounts
UNION ALL
SELECT account_no FROM loans;

SELECT name AS customer_name
FROM accounts
WHERE balance > 50000
UNION
SELECT a.name
FROM accounts a
JOIN loans l
ON a.account_no = l.account_no;

SELECT a.account_no, a.name
FROM accounts a
WHERE EXISTS (
    SELECT 1
    FROM loans l
    WHERE l.account_no = a.account_no
);

SELECT a.account_no, a.name
FROM accounts a
WHERE NOT EXISTS (
    SELECT 1
    FROM loans l
    WHERE l.account_no = a.account_no
);

SELECT * FROM loan_status;

SELECT *
FROM loan_status
WHERE status = 'NOT PAYING ON TIME';

SELECT *
FROM loan_status
WHERE status = 'CLOSED';

SELECT a.name, ls.loan_id, ls.emis_paid,
       ls.total_emis, ls.outstanding, ls.status
FROM accounts a
JOIN loan_status ls
ON a.account_no = ls.account_no;

CREATE VIEW account_summary AS
SELECT account_no, name, balance
FROM accounts;

SELECT * FROM account_summary;

SHOW CREATE VIEW loan_status;

DROP VIEW IF EXISTS account_summary;

SELECT *
FROM transactions
WHERE account_no = '100001'
ORDER BY txn_time DESC;

SELECT account_no, SUM(amount) AS total_deposits
FROM transactions
WHERE txn_type = 'DEPOSIT'
GROUP BY account_no;

SELECT account_no, SUM(amount) AS total_withdrawals
FROM transactions
WHERE txn_type = 'WITHDRAW'
GROUP BY account_no;

SELECT a.name, ls.loan_id, ls.outstanding, ls.status
FROM accounts a
JOIN loan_status ls
ON a.account_no = ls.account_no
WHERE ls.outstanding > 0;

SELECT l.account_no, l.loan_id, i.inst_no,
       i.due_date, i.amount
FROM loans l
JOIN installments i
ON l.loan_id = i.loan_id
WHERE i.paid_date IS NULL
ORDER BY i.due_date;

SELECT l.account_no, l.loan_id, i.inst_no,
       i.due_date, i.paid_date
FROM loans l
JOIN installments i
ON l.loan_id = i.loan_id
WHERE i.paid_date > i.due_date;

SELECT a.name, COUNT(t.txn_id) AS transaction_count
FROM accounts a
LEFT JOIN transactions t
ON a.account_no = t.account_no
GROUP BY a.account_no, a.name
ORDER BY transaction_count DESC;

SELECT a.name,
       COUNT(l.loan_id) AS number_of_loans,
       COALESCE(SUM(l.principal), 0) AS total_principal,
       COALESCE(SUM(l.emi), 0) AS combined_monthly_emi
FROM accounts a
LEFT JOIN loans l
ON a.account_no = l.account_no
GROUP BY a.account_no, a.name;

SHOW CREATE TABLE accounts;

SHOW CREATE TABLE transactions;

CREATE TABLE constraint_demo (
    id INT PRIMARY KEY,
    email VARCHAR(100) UNIQUE,
    customer_name VARCHAR(100) NOT NULL,
    age INT CHECK (age >= 18),
    city VARCHAR(50) DEFAULT 'Aurangabad'
);
INSERT INTO constraint_demo (id, email, customer_name, age)
VALUES (1, 'demo@example.com', 'Demo User', 20);
SELECT * FROM constraint_demo;
DROP TABLE constraint_demo;

CREATE INDEX idx_account_name
ON accounts(name);
CREATE INDEX idx_transaction_time
ON transactions(txn_time);
SHOW INDEX FROM accounts;
SHOW INDEX FROM transactions;
DROP INDEX idx_account_name ON accounts;
DROP INDEX idx_transaction_time ON transactions;


CREATE USER IF NOT EXISTS 'bank_reader'@'localhost'
IDENTIFIED BY 'Practice@123';
GRANT SELECT ON bank_db.*
TO 'bank_reader'@'localhost';
SHOW GRANTS FOR 'bank_reader'@'localhost';
REVOKE SELECT ON bank_db.*
FROM 'bank_reader'@'localhost';
GRANT INSERT ON bank_db.transactions
TO 'bank_reader'@'localhost';
REVOKE INSERT ON bank_db.transactions
FROM 'bank_reader'@'localhost';

DELIMITER $$

CREATE TRIGGER before_transaction_insert
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
    IF NEW.amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Transaction amount must be positive';
    END IF;
END$$

DELIMITER ;

SHOW TRIGGERS;

INSERT INTO transactions
(account_no, txn_type, amount, description)
VALUES ('100001', 'DEPOSIT', -500, 'Invalid test');
DROP TRIGGER IF EXISTS before_transaction_insert;

START TRANSACTION;
UPDATE accounts
SET balance = balance + 500
WHERE account_no = '100001';
COMMIT;

START TRANSACTION;
UPDATE accounts
SET balance = balance + 500
WHERE account_no = '100001';
ROLLBACK;

START TRANSACTION;
UPDATE accounts
SET balance = balance + 100
WHERE account_no = '100001';
SAVEPOINT first_savepoint;
UPDATE accounts
SET balance = balance + 200
WHERE account_no = '100002';
ROLLBACK TO first_savepoint;
COMMIT;

SELECT 5 & 3 AS bitwise_and;
SELECT 5 | 3 AS bitwise_or;
SELECT 5 ^ 3 AS bitwise_xor;
SELECT 5 << 1 AS left_shift;
SELECT 5 >> 1 AS right_shift;
SELECT ~5 AS bitwise_not;

SELECT txn_id, COALESCE(other_account, 'N/A') AS related_account
FROM transactions;

SELECT IFNULL(other_account, 'No related account') AS related_account
FROM transactions;

SELECT NULLIF(balance, 0) AS nonzero_balance
FROM accounts;

CREATE TABLE branch_demo (
    branch_id INT PRIMARY KEY,
    branch_name VARCHAR(100)
);

CREATE TABLE account_demo (
    demo_id INT PRIMARY KEY,
    branch_id INT,
    FOREIGN KEY (branch_id) REFERENCES branch_demo(branch_id)
);
ALTER TABLE account_demo
ADD CONSTRAINT fk_demo_branch
FOREIGN KEY (branch_id) REFERENCES branch_demo(branch_id);
ALTER TABLE account_demo
DROP FOREIGN KEY fk_demo_branch;
DROP TABLE account_demo;
DROP TABLE branch_demo;

SHOW FULL TABLES IN bank_db;

SHOW PROCEDURE STATUS
WHERE Db = 'bank_db';
SHOW TRIGGERS FROM bank_db;
SHOW INDEX FROM accounts;
SHOW CREATE TABLE installments;
SHOW CREATE VIEW loan_status;

SET @minimum_balance = 10000;
PREPARE account_query FROM
'SELECT account_no, name, balance
 FROM accounts
 WHERE balance > ?';
EXECUTE account_query USING @minimum_balance;
DEALLOCATE PREPARE account_query;

SELECT name, balance,
       RANK() OVER (ORDER BY balance DESC) AS balance_rank
FROM accounts;

SELECT name, balance,
       ROW_NUMBER() OVER (ORDER BY balance DESC) AS row_num
FROM accounts;

SELECT txn_id, account_no, amount,
       SUM(amount) OVER (
           PARTITION BY account_no
           ORDER BY txn_time, txn_id
       ) AS running_total
FROM transactions;

EXPLAIN
SELECT *
FROM accounts
WHERE balance > 10000;

EXPLAIN
SELECT a.name, l.principal
FROM accounts a
JOIN loans l
ON a.account_no = l.account_no;