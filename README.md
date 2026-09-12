<p align="center">
  <img src="./assets/green-digitize-banner.svg" alt="Green Digitize — ERPNext Easy Installation" width="100%">
</p>

# Green Digitize — ERPNext Easy Installation

> **A simple, step-by-step installation guide for ERPNext.**
>
> Built for fresh Ubuntu servers and VirtualBox VMs, with SSH-based administration and practical recovery guidance.

---

## 📦 Repository Files

| File | Purpose |
|---|---|
| [`erpnext_install.sh`](./erpnext_install.sh) | Downloadable Green Digitize installer launcher |
| [`assets/green-digitize-banner.svg`](./assets/green-digitize-banner.svg) | Green Digitize banner used by this README |
| [`docs/recovery.md`](./docs/recovery.md) | Downloadable backup and recovery guide |
| `README.md` | Complete installation tutorial |

---

# 1. Compatibility

For a new ERPNext installation, use a **fresh Ubuntu VM or server**.

| Component | Recommendation |
|---|---|
| Operating System | Ubuntu 22.04 LTS or newer supported release |
| CPU | 2+ cores recommended |
| RAM | 4 GB minimum for basic testing; more for production |
| Disk | 40 GB+ recommended; 100 GB is a comfortable VM size |
| Access | SSH or local terminal with sudo access |
| User | Non-root Linux user with sudo privileges |

This guide is primarily written for **ERPNext v16**.

### v16 installer requirements

- Python 3.14+
- Node.js 24
- Ubuntu 22.04+ or another OS supported by the installer for v16

> Do not install multiple major ERPNext versions into the same server environment. Use a separate VM/server for a different major version when possible.

---

# 2. Installation

## 2.1 Update and Upgrade

```bash
sudo apt update && sudo apt -y upgrade
```

Then reboot:

```bash
sudo reboot
```

Reconnect through SSH after the server comes back online.

## 2.2 Use a Non-Root User

Check the current user:

```bash
whoami
```

The installer must be run from a normal Linux user with sudo privileges.

If necessary:

```bash
sudo adduser frappeuser
sudo usermod -aG sudo frappeuser
su - frappeuser
```

Verify:

```bash
whoami
```

## 2.3 Clone This Repository

```bash
git clone https://github.com/greendigitize/green-easy-erpnext-installation.git
cd green-easy-erpnext-installation
```

Check the repository files:

```bash
ls -la
```

You should see `erpnext_install.sh`, `README.md`, `assets/` and `docs/`.

## 2.4 Make the Installer Executable

```bash
chmod +x erpnext_install.sh
```

## 2.5 Start the Installer

```bash
./erpnext_install.sh
```

The launcher downloads the pinned upstream installer revision and starts it interactively.

> **Do not run the installer as root.**

---

# 3. Choose ERPNext Version

When the installer displays its version menu, choose:

```text
Version 16
```

The installer will configure the v16 branch and its required dependencies.

---

# 4. Installation Questions

The exact prompts can vary with installer revisions. The normal flow includes configuration for the following.

### Frappe Bench

A typical Bench directory is:

```text
frappe-bench
```

### Site Name

For local testing you may use:

```text
erpnext.local
```

For a real deployment, use the configured domain.

### Administrator Password

Set and securely store a strong ERPNext **Administrator** password.

This is the ERPNext login password and is separate from the MariaDB database root password.

### Database Credentials

Keep database credentials safe. They are required for maintenance, backup, recovery and migration work.

---

# 5. Install ERPNext

When asked whether ERPNext should be installed, choose the affirmative option.

Allow the installation to finish. Large installations can take time depending on CPU, RAM, disk speed and network bandwidth.

---

# 6. Production Setup

For a production-style environment, the installer may configure:

- Nginx
- Supervisor
- Redis
- Scheduler/background jobs
- Socket.IO
- Required service configuration

---

# 7. Open ERPNext

Find the server IP:

```bash
hostname -I
```

For a local VM the address may look like:

```text
http://192.168.x.x
```

For a real server, use the configured domain.

Log in with:

```text
Username: Administrator
Password: <your ERPNext Administrator password>
```

---

# 8. Verify the Installation

Enter the Bench directory:

```bash
cd ~/frappe-bench
```

Check Bench:

```bash
bench --version
```

List installed applications:

```bash
bench --site <your-site-name> list-apps
```

Run the site doctor:

```bash
bench --site <your-site-name> doctor
```

---

# 9. SSH Workflow

```text
Windows PC
   │
   │ SSH
   ▼
Ubuntu VM / Server
   │
   │ Git
   ▼
Green Digitize Repository
   │
   ▼
erpnext_install.sh
   │
   ▼
Frappe Bench
   │
   ▼
ERPNext v16
```

Typical Windows PowerShell command:

```bash
ssh <linux-user>@<server-ip>
```

---

# 10. Troubleshooting

<details>
<summary><strong>Installer says it is running as root</strong></summary>

```bash
whoami
```

If it returns `root`, switch to a normal sudo-enabled user.

</details>

<details>
<summary><strong>Git clone fails</strong></summary>

```bash
ping -c 4 github.com
git --version
```

Then retry the clone command.

</details>

<details>
<summary><strong>ERPNext page does not open</strong></summary>

```bash
hostname -I
sudo supervisorctl status
sudo systemctl status nginx
```

Inspect the actual service error before changing configuration.

</details>

<details>
<summary><strong>Redis connection problem</strong></summary>

From the Bench directory:

```bash
cd ~/frappe-bench
bench setup redis
bench setup socketio
bench setup supervisor
sudo supervisorctl reload
```

Then:

```bash
sudo supervisorctl status
```

Do not change Redis ports randomly; first confirm the current Bench configuration.

</details>

<details>
<summary><strong>Installation stopped or failed</strong></summary>

Do not immediately delete the entire environment. Capture the terminal error first and determine which installation step failed.

For recovery and rebuild guidance, open [`docs/recovery.md`](./docs/recovery.md).

</details>

---

# 11. Backup and Recovery

ERPNext is recoverable when important data has been preserved.

> **Application files can often be rebuilt; deleted database/site data cannot be recreated automatically.**

A damaged application environment does not necessarily mean business data is lost. If the database and site data remain intact, a rebuild may be possible without recreating business records.

If the database, site files or backups have been deleted or corrupted, recovery depends on what valid backups remain.

Read the full recovery guide:

**[Open the Backup & Recovery Guide](./docs/recovery.md)**

---

# 12. Fresh Reinstallation

Treat a completely fresh reinstall as a potentially destructive operation.

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

The safest path is:

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

Third-party apps can have their own compatibility requirements.

---

# 14. Updating This Repository

```bash
cd ~/green-easy-erpnext-installation
git pull
```

For production, review installer changes and back up the site/database before changing the installation workflow.

---

# 15. Clean Installation Checklist

- [ ] Ubuntu is updated
- [ ] SSH access works
- [ ] Non-root sudo user is being used
- [ ] Repository cloned successfully
- [ ] Installer is executable
- [ ] ERPNext v16 selected intentionally
- [ ] Database credentials stored securely
- [ ] Administrator password stored securely
- [ ] Site created successfully
- [ ] ERPNext installed successfully
- [ ] Supervisor/Nginx/Redis services are healthy where used
- [ ] Browser login works
- [ ] `bench --site <site> list-apps` works
- [ ] Initial backup has been created

---

# 16. Green Digitize

**Green Digitize** provides this repository as an easy starting point for deploying ERPNext with a clear installation path and practical recovery guidance.

The goal is to make installation easier to understand, easier to repeat and easier to recover when something goes wrong.

---

## Important Notes

- Review the installer before using it on a production server.
- ERPNext, Frappe Framework and third-party applications have their own compatibility requirements.
- Always maintain verified backups for production systems.
- Never commit passwords, API keys or other secrets to GitHub.

---

**Green Digitize — ERPNext Easy Installation**

Simple installation. Clear steps. Safer recovery.
