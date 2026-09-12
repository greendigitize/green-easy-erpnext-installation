# Green Digitize — ERPNext Easy Installation

> **A simple, step-by-step installation guide for ERPNext.**
>
> Built for users who want a clean ERPNext installation on a fresh Ubuntu server or VirtualBox VM, with SSH-based administration and clear recovery guidance.

---

## 🚀 Installation Overview

```mermaid
flowchart TD
    A[Fresh Ubuntu VM / Server] --> B[Update System]
    B --> C[Connect Through SSH]
    C --> D[Clone Green Digitize Repository]
    D --> E[Run Installer]
    E --> F[Choose ERPNext Version]
    F --> G[Configure Database & Site]
    G --> H[Install ERPNext]
    H --> I[Production Setup]
    I --> J[Open ERPNext in Browser]
    J --> K[Verify Installation]
```

---

# 1. Compatibility

## 1.1 Recommended Environment

For a new ERPNext installation, use a **fresh Ubuntu VM or server**.

Recommended for ERPNext v16 testing:

| Component | Recommendation |
|---|---|
| Operating System | Ubuntu 22.04 LTS or newer supported release |
| CPU | 2+ cores recommended |
| RAM | 4 GB minimum for basic testing; more is recommended for production |
| Disk | 40 GB+ recommended; 100 GB is a comfortable VM size |
| Access | SSH or local terminal with sudo access |
| User | Non-root Linux user with sudo privileges |

> **Important:** Resource requirements depend on the number of users, background jobs, reports, attachments and other workloads. Production systems should be sized for the expected workload.

## 1.2 ERPNext Version

This guide is primarily written for **ERPNext v16**.

The installer in this repository may offer other ERPNext versions as well. Always choose the version you have intentionally planned to deploy.

### ERPNext v16 requirements in the installer

- Python 3.14+
- Node.js 24
- Ubuntu 22.04+ or another operating system supported by the installer for v16

> Do not install multiple major ERPNext versions into the same server environment. Use a separate VM/server for a different major version when possible.

---

# 2. Installation

## 2.1 Update and Upgrade the System

Run:

```bash
sudo apt update && sudo apt -y upgrade
```

When the upgrade finishes, reboot the server:

```bash
sudo reboot
```

Reconnect through SSH after the server comes back online.

---

## 2.2 Make Sure You Are NOT Running as Root

The installer should be run from a **normal Linux user with sudo privileges**, not from a root shell.

Check the current user:

```bash
whoami
```

If the result is `root`, create or switch to a normal user before continuing.

Example:

```bash
sudo adduser frappeuser
```

Then grant sudo access:

```bash
sudo usermod -aG sudo frappeuser
```

Switch to that user:

```bash
su - frappeuser
```

Verify:

```bash
whoami
```

You should now see the normal username.

---

## 2.3 Clone the Green Digitize Installer Repository

Clone this repository:

```bash
git clone https://github.com/greendigitize/green-easy-erpnext-installation.git
```

Enter the directory:

```bash
cd green-easy-erpnext-installation
```

Check the files:

```bash
ls -la
```

---

## 2.4 Make the Installer Executable

Run:

```bash
chmod +x erpnext_install.sh
```

---

## 2.5 Start the Installer

Run:

```bash
source erpnext_install.sh
```

The installer will guide you through the setup interactively.

> **Do not run the installer as root.**

---

# 3. Choose ERPNext Version

When the installer displays its version menu, choose the version you want to install.

For the ERPNext v16 test installation, select:

```text
Version 16
```

For an interactive menu, this will normally appear as a numbered choice. Select the number shown beside **Version 16**.

---

# 4. Installation Questions

The exact prompts can vary with installer revisions, but the normal flow includes configuration for the following items.

## 4.1 Frappe Bench

The installer creates a Frappe Bench environment where the framework, ERPNext and the site are managed.

A typical bench directory is:

```text
frappe-bench
```

## 4.2 Site Name

The site is the ERPNext database/site identity.

For local testing you may use a name such as:

```text
erpnext.local
```

For a real deployment, use the domain name you have configured for the server.

## 4.3 Administrator Password

Set a strong ERPNext **Administrator** password and store it securely.

This password is for logging into ERPNext. It is not the same thing as the MariaDB database root password.

## 4.4 Database Passwords

The installation process may configure MariaDB and ask for database credentials.

Keep all database credentials safe. They are important for maintenance, backup, recovery and migration work.

---

# 5. Install ERPNext

When the installer asks whether ERPNext should be installed, choose the affirmative option.

The installer will then fetch ERPNext and install it into the Frappe Bench environment.

During this stage, allow the commands to finish. Large installations can take significant time depending on CPU, RAM, disk speed and network bandwidth.

---

# 6. Production Setup

For a production-style environment, the installer may configure services such as:

- Nginx
- Supervisor
- Redis
- Scheduler/background jobs
- Socket.IO
- Required service configuration

These components allow ERPNext to continue running as managed services rather than depending on a terminal window remaining open.

---

# 7. Open ERPNext

After the installation finishes, determine the server IP address:

```bash
hostname -I
```

From a computer on the same network, open the appropriate address in a browser.

For a local VM, this may be something similar to:

```text
http://192.168.x.x
```

For a server with a configured domain, use the domain assigned to the ERPNext site.

Log in with:

```text
Username: Administrator
Password: <your ERPNext Administrator password>
```

---

# 8. Verify the Installation

Open the Bench directory. For example:

```bash
cd ~/frappe-bench
```

Check Bench:

```bash
bench --version
```

List installed applications for your site:

```bash
bench --site <your-site-name> list-apps
```

Check the site status where appropriate:

```bash
bench --site <your-site-name> doctor
```

> Replace `<your-site-name>` with the actual site name you created.

---

# 9. SSH Workflow

A simple workflow for managing ERPNext from Windows is:

```text
Windows PC
   │
   │ SSH
   ▼
Ubuntu VM / Server
   │
   │ Git
   ▼
Green Digitize Installation Repository
   │
   ▼
ERPNext Installer
   │
   ▼
Frappe Bench
   │
   ▼
ERPNext v16
```

Typical SSH command from Windows PowerShell:

```bash
ssh <linux-user>@<server-ip>
```

Example:

```bash
ssh frappeuser@192.168.1.100
```

Use the username and IP address of your own VM/server.

---

# 10. Troubleshooting

<details>
<summary><strong>Installer says it is running as root</strong></summary>

Check:

```bash
whoami
```

If it returns `root`, switch to a normal sudo-enabled user and run the installer again.

</details>

<details>
<summary><strong>Git clone command fails</strong></summary>

Check network connectivity:

```bash
ping -c 4 github.com
```

Check Git:

```bash
git --version
```

Then retry:

```bash
git clone https://github.com/greendigitize/green-easy-erpnext-installation.git
```

</details>

<details>
<summary><strong>ERPNext page does not open</strong></summary>

First check the machine IP:

```bash
hostname -I
```

Then inspect the services:

```bash
sudo supervisorctl status
```

Also check Nginx:

```bash
sudo systemctl status nginx
```

If Redis or other Frappe services are involved, inspect their status and the Bench logs before changing configuration.

</details>

<details>
<summary><strong>Redis connection problem</strong></summary>

From the Bench directory, use the appropriate Bench setup commands for your installation:

```bash
cd ~/frappe-bench
bench setup redis
bench setup socketio
bench setup supervisor
sudo supervisorctl reload
```

Then inspect service status:

```bash
sudo supervisorctl status
```

Avoid changing Redis ports randomly. First confirm which ports and services the current Bench configuration expects.

</details>

<details>
<summary><strong>Installation stopped or failed part-way through</strong></summary>

Do not immediately delete the entire environment.

First capture the error shown in the terminal and inspect the last installation step. A partial installation can sometimes be repaired without starting from zero.

For a clean rebuild, take backups of any valuable site/database data before destructive operations.

</details>

---

# 11. Backup and Recovery

ERPNext is recoverable when the important data has been preserved.

The key rule is:

> **Application files can often be rebuilt; deleted database/site data cannot be recreated automatically.**

A damaged application environment does not necessarily mean that all business data is lost. The database and site data may remain intact and can sometimes be used during a rebuild or restoration.

However, if the database, site directory, files or backups have been deleted or corrupted, the original data may not be recoverable without a valid backup.

## 11.1 Before Destructive Repair

Before removing an existing ERPNext installation, preserve:

- Database backup
- Site files
- Private files
- Public files
- Configuration information
- Encryption/secrets where required by your deployment

## 11.2 Rebuild Concept

A typical recovery flow is:

```text
Existing ERPNext problem
        │
        ▼
Create / verify backups
        │
        ▼
Determine whether the problem is application or data related
        │
        ├───────────────┐
        ▼               ▼
Application issue    Data issue
        │               │
        ▼               ▼
Repair/rebuild      Restore valid backup
        │               │
        └───────┬───────┘
                ▼
        Run migrations/checks
                │
                ▼
          Start services
                │
                ▼
          Verify ERPNext
```

## 11.3 Important Recovery Warning

Do not assume that reinstalling ERPNext will automatically bring back:

- users
- passwords
- invoices
- customers
- accounting data
- attachments
- customizations

Those depend on the database, site files and backups being preserved and restored correctly.

---

# 12. Fresh Reinstallation

A completely fresh reinstall should be treated as a **destructive operation** unless you have confirmed that all required data is backed up.

Recommended sequence:

```text
1. Stop and assess
2. Take backups
3. Confirm backup integrity
4. Document site/database information
5. Remove or rebuild only what is necessary
6. Reinstall ERPNext
7. Restore data when appropriate
8. Run migrations
9. Verify services
10. Verify login and business data
```

Never delete the old environment first and investigate backups later.

---

# 13. Additional Apps

The safest first installation path is:

```text
ERPNext v16
   ↓
Verify ERPNext
   ↓
Take a backup
   ↓
Install additional apps one at a time
   ↓
Verify after each major change
```

Third-party apps can have their own compatibility requirements. Test them separately instead of treating every additional app as part of the base ERPNext installation.

---

# 14. Updating the Installation Repository

When a newer version of this installer is published, pull the latest repository changes:

```bash
cd ~/green-easy-erpnext-installation
git pull
```

Then inspect the changed files before running an installer update.

> For a production server, do not blindly run a new installer revision over an existing ERPNext environment. Review the changes and back up the site/database first.

---

# 15. Clean Installation Checklist

Use this checklist before declaring the installation complete:

- [ ] Ubuntu is updated
- [ ] SSH access works
- [ ] Non-root sudo user is being used
- [ ] Repository cloned successfully
- [ ] Installer is executable
- [ ] ERPNext v16 selected intentionally
- [ ] Database credentials stored securely
- [ ] ERPNext Administrator password stored securely
- [ ] Site created successfully
- [ ] ERPNext installed successfully
- [ ] Supervisor/Nginx/Redis services are healthy where used
- [ ] Browser login works
- [ ] `bench --site <site> list-apps` works
- [ ] Initial backup has been created

---

# 16. Repository Files

The repository should keep the installation components simple and easy to understand.

Recommended structure:

```text
.
├── README.md
├── erpnext_install.sh
├── assets/
│   └── green-digitize-banner.svg
└── docs/
    └── recovery.md
```

The **README.md** is the main installation tutorial.

The **installer script** performs the automated installation workflow.

The **assets** folder contains the Green Digitize visual branding.

The **docs** folder can hold deeper technical documentation without making the main README difficult for beginners.

---

# 17. Green Digitize

**Green Digitize** provides this repository as an easy starting point for deploying ERPNext with a clear installation path and practical recovery guidance.

The goal of this project is to make the installation process easier to understand, easier to repeat and easier to recover when something goes wrong.

---

## 📌 Important Notes

- This repository is an installation aid; always review the installer before using it on a production server.
- ERPNext, Frappe Framework and third-party applications have their own release cycles and compatibility requirements.
- Always maintain verified backups for production systems.
- Do not expose database credentials or secrets in GitHub.

---

## 📚 Official Resources

- [ERPNext Documentation](https://docs.erpnext.com)
- [Frappe Framework Documentation](https://docs.frappe.io)
- [ERPNext on GitHub](https://github.com/frappe/erpnext)
- [Frappe Framework on GitHub](https://github.com/frappe/frappe)

---

**Green Digitize — ERPNext Easy Installation**

Simple installation. Clear steps. Safer recovery.
