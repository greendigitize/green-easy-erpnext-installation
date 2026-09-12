# Installation Steps

1. Start from a clean supported Ubuntu 24.04 or Debian 13 Server VM.
2. Choose ERPNext v15 or v16.
3. Installer detects OS and selects the matching Python, Node/npm, and MariaDB profile.
4. Create/use the dedicated Frappe Linux user.
5. Configure MariaDB.
6. Install the isolated Python runtime.
7. Install Node.js with NVM and verify bundled npm/Yarn.
8. Install Bench and initialize the selected Frappe branch.
9. Create the site and install ERPNext.
10. Install matching official optional apps if selected.
11. Configure production Supervisor/Nginx when requested.
12. Run final service and HTTP health checks.

## Testing recommendation

Test v15 first, then v16, each on a clean VM or clean snapshot. Keep screenshots/logs for every failure so fixes can be incorporated without changing already-working components.

The installer installs compatibility support for the official Saudi Riyal Sign `U+20C1` and configures ERPNext currency `SAR` to use that symbol. The Unicode sign is distinct from the older `U+FDFC` Rial Sign. The font package is installed under `/usr/local/share/fonts/green-saudi-riyal`.
