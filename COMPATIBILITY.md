# Compatibility

Green ERPNext Installer 3.0.42 intentionally supports only ERPNext/Frappe v15 and v16. Legacy v13/v14 support has been removed from the installer to keep the supported matrix small and reproducible.

## Ubuntu 24.04

| ERPNext | Python | Node/npm | MariaDB | HR |
|---|---|---|---|---|
| v15 | isolated Python 3.10+ | Node 18 + bundled npm | Ubuntu 24.04 native 10.11.x | matching HRMS v15 |
| v16 | isolated Python 3.14 | Node 24 + bundled npm | official MariaDB 11.8.x | matching HRMS v16 |

## Debian 13

| ERPNext | Python | Node/npm | MariaDB | HR |
|---|---|---|---|---|
| v15 | isolated Python 3.10+ | Node 18 + bundled npm | Debian 13 native 11.8.x | matching HRMS v15 |
| v16 | isolated Python 3.14 | Node 24 + bundled npm | Debian 13 native 11.8.x | matching HRMS v16 |

## Runtime policy

The installer detects the operating system and release first. It then selects Python, Node/npm, and MariaDB for that OS profile and validates the selected versions against the Frappe/ERPNext release.

- The system Python is not replaced.
- Node is installed through NVM and its bundled npm is used; a second unrelated npm is not selected for Bench.
- Existing MariaDB is reused and validated; the installer never performs an automatic downgrade.
- Python is isolated in the Bench environment.
- v15 installs the matching official Payments branch before ERPNext.
- v15/v16 install matching HRMS branches when selected.

## Not supported by this release

- ERPNext/Frappe v13
- ERPNext/Frappe v14
- Ubuntu 22.04 for the supported v15/v16 profiles
- Debian 11/12 for the supported v15/v16 profiles

These exclusions are deliberate: the project is prioritizing the current v15/v16 installation path instead of carrying legacy runtime combinations.

The installer installs compatibility support for the official Saudi Riyal Sign `U+20C1` and configures ERPNext currency `SAR` to use that symbol. The Unicode sign is distinct from the older `U+FDFC` Rial Sign. The font package is installed under `/usr/local/share/fonts/green-saudi-riyal`.
