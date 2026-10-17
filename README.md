# Secure Bank

A full-stack bank management system: a MySQL database with stored procedures, a Spring Boot REST API, and a plain HTML/CSS/JS neon frontend.

## Features

**Customer:** sign in with account number and 4-digit PIN; deposit, withdraw and transfer; take a loan (12% p.a., 3 to 36 months); pay EMIs; loan status (paying on time, not paying on time, closed); transaction filter; CSV statement; live EMI estimate.

**Admin:** sign in; create accounts; reset a customer's PIN; search accounts; view any account's transactions; view all loans and their status.

## Tech stack

- MySQL 8: tables, a view (`loan_status`), stored procedures for every money operation (each runs as one database transaction)
- Spring Boot (Java 17): REST API with Spring Security and JWT, `JdbcTemplate` calling the procedures
- Plain HTML, CSS and JavaScript frontend

## Project structure

    DBMS/
    ├── schema.sql      database, procedures, view, demo data
    ├── practice.sql    SQL practice queries (run one at a time, never whole)
    ├── backend/        Spring Boot API
    └── frontend/       index.html, style.css, app.js, config.js

## Run it (GitHub Codespaces or Linux)

1. Start MySQL and load the database:

        sudo service mysql start
        sudo mysql < schema.sql
        sudo mysql -e "CREATE USER IF NOT EXISTS 'aj'@'localhost' IDENTIFIED BY 'pass123'; GRANT ALL ON bank_db.* TO 'aj'@'localhost';"

2. Start the backend (port 8080):

        cd backend
        ./mvnw spring-boot:run

3. Serve the frontend (port 5500), in a second terminal:

        cd frontend
        python3 -m http.server 5500

4. In Codespaces, set port 8080 to Public in the Ports tab, then open port 5500.

## Demo logins

Admin: `admin` / `admin123`

| Account | PIN | Notes |
|---|---|---|
| 100001 | 1111 | no loan |
| 100003 | 3333 | active loan, can pay EMI |
| 100004 | 4444 | overdue loan |
| 100011 | 1212 | many transactions |

Accounts 100001 to 100012 use the PINs 1111, 2222, ... in order, except 100010 (1010), 100011 (1212) and 100012 (1313).

## API overview

| Method | Path | Who |
|---|---|---|
| POST | /api/auth/customer/login, /api/auth/admin/login | public |
| GET | /api/customer/me, /transactions, /loans | customer |
| POST | /api/customer/deposit, /withdraw, /transfer, /loans, /loans/pay-emi | customer |
| GET | /api/admin/accounts, /accounts/{no}/transactions, /loans | admin |
| POST | /api/admin/accounts, /accounts/{no}/reset-pin | admin |

A customer's account number always comes from the login token, never from the request body.

## Known limitations

- PINs and the admin password are stored as unsalted SHA-256 hashes. A real system should use bcrypt or Argon2.
- There is no login rate limiting or lockout, so 4-digit PINs can be guessed by brute force.
- The data is demo data. Do not use real money or real personal details.
