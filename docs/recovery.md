# ERPNext Backup & Recovery Guide

## Purpose

This document explains what can usually be recovered when an ERPNext installation becomes damaged and what must be protected before a reinstall.

## 1. The Important Rule

**Application files can often be rebuilt; deleted database/site data cannot be recreated automatically.**

If the ERPNext application or Bench environment becomes corrupted while the database and site files remain intact, it may be possible to repair or rebuild the application without recreating the business data.

If the database, site files or backups are deleted or corrupted, recovery depends on the remaining valid backups.

## 2. What Must Be Protected

Before destructive maintenance, preserve:

- Database backups
- `public/files`
- `private/files`
- Site configuration
- Encryption keys and other required secrets
- Custom applications
- Customizations and patches
- Domain and reverse-proxy configuration where applicable

## 3. Before Reinstalling

Do not immediately remove the old Bench or site.

First:

1. Identify the site name.
2. Identify the Bench directory.
3. Check whether the database is still accessible.
4. Create or verify a backup.
5. Preserve site files and configuration.
6. Record installed applications.
7. Record the ERPNext/Frappe versions.

## 4. Recovery Decision

```text
ERPNext problem
      |
      v
Are database + site files intact?
      |
   +--+--+
   |     |
  YES    NO
   |     |
   v     v
Repair  Restore from
/rebuild valid backup
   |     |
   +--+--+
      |
      v
Run migrations/checks
      |
      v
Start services
      |
      v
Verify login and business data
```

## 5. Application Corruption

If only application files are damaged, do not assume the business database is lost.

A controlled rebuild may include:

- Recreating the Bench environment
- Installing the matching Frappe/ERPNext version
- Restoring the site/database
- Restoring public/private files
- Restoring required custom applications
- Running migrations
- Rebuilding production services
- Testing the site before returning it to users

The exact restoration procedure depends on the version and backup method used.

## 6. Data Loss

Reinstalling ERPNext does **not** automatically recreate:

- Users
- Passwords
- Customers
- Suppliers
- Invoices
- Accounting entries
- Stock transactions
- Attachments
- Custom fields
- Other business records

Those records live in the site/database and associated files. A valid backup is required to restore deleted data.

## 7. Fresh Reinstallation

Treat a fresh reinstall as destructive until backups have been verified.

Recommended order:

```text
Backup
  -> Verify backup
  -> Document current environment
  -> Rebuild/reinstall
  -> Restore data
  -> Migrate
  -> Start services
  -> Test
```

Never delete the old environment first and investigate backups later.

## 8. After Recovery

Verify at minimum:

- ERPNext login
- Users and roles
- Company records
- Customers and suppliers
- Chart of Accounts
- Sales invoices
- Purchase invoices
- Stock balances
- Attachments
- Installed applications
- Background jobs
- Email configuration
- Scheduled jobs
- Nginx/Supervisor/Redis services where used

Create a new verified backup after the recovered system is confirmed healthy.
