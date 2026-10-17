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