
<img width="1215" height="424" alt="elastic_ascii_banner" src="https://github.com/user-attachments/assets/f0e7e014-73e6-4ca5-a9e1-af8539971f2b" />

# Elastic Stack Air-Gapped Installer

An interactive, single-file bash installer for self-hosted Elastic Stack deployments in **air-gapped (no internet) environments**. All three components — Elasticsearch, Kibana, and Fleet Server — are installed from packages you pre-download and transfer to the target host.

> For internet-connected deployments see [elastic-onprem-installer](https://github.com/Raricoza/elastic_onprem_installer).

## What it installs

| Component | Default port |
|---|---|
| Elasticsearch | 9200 |
| Kibana | 5601 |
| Fleet Server (Elastic Agent) | 8220 |

**Topology:** Single-node only.

## Supported platforms

- **RHEL family:** RHEL, CentOS, Rocky Linux, AlmaLinux
- **Debian family:** Ubuntu, Debian
- **Architectures:** x86_64 and ARM64 (aarch64)

## Requirements

### On the target (air-gapped) host

- Root or `sudo` access
- `systemd`
- `curl` (for post-install API calls — install from your internal package mirror if not present)
- `python3` (for JSON parsing during Fleet setup)
- Minimum **8 CPU cores** recommended
- Minimum **32 GB RAM** recommended
- Minimum **200 GB free disk** on the data directory recommended

### Pre-downloaded packages (see below)

All three packages must be the same Elastic Stack version. The installer reads the version from the filenames and will refuse to proceed if they do not match.

## Step 1 — Download packages on an internet-connected machine

Download the following files from [https://www.elastic.co/downloads](https://www.elastic.co/downloads) or directly from the Elastic artifact server:

### RHEL / CentOS / Rocky / AlmaLinux

```
https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-<version>-x86_64.rpm
https://artifacts.elastic.co/downloads/kibana/kibana-<version>-x86_64.rpm
https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-<version>-linux-x86_64.tar.gz
```

For ARM64 hosts, replace `x86_64` with `aarch64` (packages) and `arm64` (tarball):
```
elasticsearch-<version>-aarch64.rpm
kibana-<version>-aarch64.rpm
elastic-agent-<version>-linux-arm64.tar.gz
```

### Ubuntu / Debian

```
https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-<version>-amd64.deb
https://artifacts.elastic.co/downloads/kibana/kibana-<version>-amd64.deb
https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-<version>-linux-x86_64.tar.gz
```

For ARM64, use `arm64.deb` packages and `linux-arm64.tar.gz`.

### Example (version 9.0.1, x86_64, RHEL)

```bash
VERSION=9.0.1
curl -O "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${VERSION}-x86_64.rpm"
curl -O "https://artifacts.elastic.co/downloads/kibana/kibana-${VERSION}-x86_64.rpm"
curl -O "https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${VERSION}-linux-x86_64.tar.gz"
```

## Step 2 — Transfer to the air-gapped host

Copy the three package files and `install.sh` to the target host using any available transfer method (USB, SCP from a jump host, etc.). Place them all in the same directory.

```
/opt/elastic-packages/
├── elasticsearch-9.0.1-x86_64.rpm
├── kibana-9.0.1-x86_64.rpm
├── elastic-agent-9.0.1-linux-x86_64.tar.gz
└── install.sh
```

## Step 3 — Run the installer

```bash
sudo bash install.sh
```

The installer is fully interactive — no flags or config files required.

## What the installer does

1. Detects the OS and CPU architecture
2. Checks system prerequisites (CPU, RAM, disk)
3. Prompts for the package directory and validates:
   - All three packages (Elasticsearch, Kibana, Elastic Agent) are present
   - All packages are the same version
4. Prompts for:
   - **Cluster name** (default: `elastic-poc`) and **node name** (default: hostname)
   - **Bind IP addresses** for Elasticsearch, Kibana, and Fleet Server
   - **Data directory** for Elasticsearch (default: `/var/lib/elasticsearch`)
   - **Log directory** for Elasticsearch (default: `/var/log/elasticsearch`)
   - Optional custom passwords for the `elastic` and `kibana_system` users
5. Installs Elasticsearch and Kibana from the local `.rpm` or `.deb` packages
6. Extracts the Elastic Agent tarball
7. Writes configuration files; creates data/log directories with correct ownership
8. Starts services in dependency order: Elasticsearch → Kibana → Fleet Server
9. Auto-generates the `elastic` superuser password and optionally applies a custom one
10. Generates a Kibana enrollment token and enrolls Kibana with Elasticsearch
11. Generates a Fleet Server service token and installs Fleet Server via the Elastic Agent tarball
12. Opens required firewall ports (supports `firewalld` and `ufw`)
13. Prints a full credential and access URL summary, saved to a local file

## Output files

Both files are written to the same directory as the script:

| File | Contents |
|---|---|
| `elastic-install-<timestamp>.log` | Full step-by-step install log including all credentials |
| `elastic-install-summary.txt` | Access URLs, credentials, and next-step guidance |

## Credentials shown after install

- `elastic` superuser password
- `kibana_system` user password (if a custom password was set)
- Kibana enrollment token
- Fleet Server service token
- CA certificate path (for HTTPS connections to Elasticsearch)

## Security

- TLS is enabled by default on all Elasticsearch HTTP and transport connections
- Kibana uses an enrollment token to establish a trusted connection to Elasticsearch
- Fleet Server communicates with Elasticsearch over TLS using the CA certificate
- `xpack.encryptedSavedObjects.encryptionKey` is automatically generated and set in `kibana.yml`
- RPM packages are installed with `--nosignature` since the Elastic GPG key is not imported in an air-gapped environment; the packages are sourced directly from `artifacts.elastic.co`

## Troubleshooting

Check the install log for detailed output from every step:

```bash
cat elastic-install-*.log
```

Check service status and logs:

```bash
systemctl status elasticsearch kibana elastic-agent
journalctl -u elasticsearch -n 100 --no-pager
journalctl -u kibana -n 100 --no-pager
```

### dpkg dependency errors (Debian/Ubuntu)

If `dpkg -i` fails with unmet dependencies, install the missing packages from your internal package mirror, then re-run the installer (it will skip already-installed components).

---

## Changelog

### 2026-10-05 — Initial release
- Air-gapped single-node installer derived from [elastic-onprem-installer](https://github.com/Raricoza/elastic_onprem_installer)
- Package directory prompt with validation: verifies all three components are present and match version
- Local `.rpm` / `.deb` installation via `rpm --nosignature` and `dpkg -i`
- All post-install security, enrollment, and Fleet Server setup identical to the online installer
- Custom cluster name, node name, data directory, and log directory prompts
