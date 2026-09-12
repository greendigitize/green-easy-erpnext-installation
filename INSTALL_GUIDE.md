# Installation Guide

## Before you start

Use a clean server VM with sudo access and no desktop environment. Recommended test resources: 4 vCPU, 8 GB RAM, and 60–80 GB disk.

Supported OS profiles in this release:

- Ubuntu 24.04 + ERPNext v15/v16
- Debian 13 + ERPNext v15/v16

The installer intentionally does not support v13/v14 or Ubuntu 22.04 in this release.

## Runtime selection

The installer detects the OS release first and then selects the runtime profile. This avoids treating ERPNext version alone as the source of Python, MariaDB, or npm decisions.

## Production

When production mode is enabled, the installer configures Supervisor and Nginx and performs final service/HTTP checks. It does not rely on a blanket `sudo supervisorctl restart frappe:` before the Supervisor group exists.

## Optional apps

The installer offers official Frappe apps only when a matching branch is configured. HRMS is version matched to ERPNext v15/v16. Payments is installed from the version-15 branch before ERPNext v15.

The installer installs compatibility support for the official Saudi Riyal Sign `U+20C1` and configures ERPNext currency `SAR` to use that symbol. The Unicode sign is distinct from the older `U+FDFC` Rial Sign. The font package is installed under `/usr/local/share/fonts/green-saudi-riyal`.
