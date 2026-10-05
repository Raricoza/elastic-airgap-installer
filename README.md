
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

## Air-gapped considerations

The following services are automatically disabled or configured by the installer to prevent failed outbound connection attempts:

| Service | Setting applied | Why |
|---|---|---|
| GeoIP database updates | `ingest.geoip.downloader.enabled: false` in `elasticsearch.yml` | ES polls `geoip.elastic.co` on startup |
| Elastic Maps Service | `map.includeElasticMapsService: false` in `kibana.yml` | Map tile backgrounds come from `tiles.maps.elastic.co` |
| Usage telemetry | `telemetry.enabled: false` / `telemetry.optIn: false` in `kibana.yml` | Prevents outbound usage-data calls |
| AI Assistant knowledge base | `xpack.observabilityAIAssistant.enabled: false` in `kibana.yml` | Kibana polls `kibana-knowledge-base-artifacts.elastic.co` for AI knowledge base content |
| Fleet Package Registry | `xpack.fleet.registryUrl` set if a local EPR URL is provided | Fleet fetches integrations from `epr.elastic.co` by default |

### AI Assistant

The Kibana AI Assistant is disabled by default. It will not work without:

1. An LLM connector configured (OpenAI, Bedrock, etc.) — available through Kibana → Stack Management → Connectors
2. Network access to the LLM provider endpoint

To re-enable after configuring a connector, remove `xpack.observabilityAIAssistant.enabled: false` from `/etc/kibana/kibana.yml` and restart Kibana.

### Elastic Package Registry (EPR)

Without a local EPR, you **cannot install integrations** (System, Nginx, Windows, custom) from the Fleet UI after install. The installer prompts for an EPR URL during configuration.

To deploy EPR as a Docker container on a host with access to Docker Hub (then transfer the image or use an internal registry):

```bash
# Pull the image on an internet-connected machine
docker pull docker.elastic.co/package-registry/distribution:latest

# Save and transfer
docker save docker.elastic.co/package-registry/distribution:latest | gzip > epr.tar.gz

# Load on the air-gapped host
docker load < epr.tar.gz

# Run EPR (port 8080 by default)
docker run -d --name epr -p 8080:8080 \
  docker.elastic.co/package-registry/distribution:latest
```

If you didn't configure EPR during install, add it to `/etc/kibana/kibana.yml` and restart Kibana:

```yaml
xpack.fleet.registryUrl: "http://<epr-host>:8080"
```

```bash
systemctl restart kibana
```

### Kibana reporting (PDF/PNG)

Kibana's reporting feature uses a bundled headless Chromium browser. It requires `fontconfig` and at least one font package to be installed on the host. The installer checks for `fontconfig` and warns if it is missing — install it from your internal package mirror.

### Agent self-upgrades

Fleet agents **cannot self-upgrade** in an air-gapped environment. The agent upgrade mechanism downloads new binaries from `artifacts.elastic.co`, which is unreachable.

Options for keeping agents current:
- **Manual upgrade:** copy a new agent tarball to each host and run `elastic-agent upgrade --version <ver> --source-uri file:///path/to/tarball`
- **Local Elastic Artifact Registry:** deploy the artifact registry Docker image (`docker.elastic.co/beats/elastic-agent`) internally and configure `xpack.fleet.artifactRegistryProxyUrl` in `kibana.yml` to point to it

### Machine learning models

ELSER and other NLP models are not included in the Elasticsearch package and cannot be auto-downloaded in an air-gapped environment. To use ML features:

1. Download the model files from Elastic on an internet-connected machine
2. Use `eland` or the Elasticsearch API to upload the model manually
3. See [Elastic docs — deploy a trained model](https://www.elastic.co/guide/en/machine-learning/current/ml-nlp-deploy-models.html)

## Cross-Cluster Search from Elastic Cloud Hosted (ECH)

This is the recommended topology for a "limited internet" air-gapped deployment: the on-prem cluster holds data in a restricted network; ECH queries it via Cross-Cluster Search (CCS) while providing the Kibana/Fleet management plane.

### How it works

ECH connects to the on-prem Elasticsearch over standard HTTPS (port 9200) in **proxy mode** — no dedicated remote-cluster port (9443) is required. Traffic flows: ECH → limited internet path → on-prem port 9200.

### Setup (installer handles steps 1–2 automatically)

**1. Create a cross-cluster API key on the on-prem cluster** (installer does this if CCS is enabled):

```bash
POST /_security/cross_cluster/api_key
{
  "name": "ech-ccs-key",
  "access": {
    "search": [{ "names": ["*"] }]
  }
}
```

Save the `encoded` value from the response.

**2. Get the on-prem CA certificate:**

```bash
cat /etc/elasticsearch/certs/http_ca.crt
```

**3. In the ECH console:**

1. Go to your ECH deployment → **Security** → **Trusted CA** → upload `http_ca.crt`
2. Go to **Security** → **Remote clusters** → **Add remote cluster**:
   - **Name:** `on-prem` (or any label — this becomes the CCS prefix)
   - **Mode:** Proxy
   - **URL:** `https://<public-ip-of-on-prem>:9200`
   - **API key:** paste the `encoded` value from step 1

**4. Verify the connection** in the ECH Dev Console:

```
GET /_remote/info
```

**5. Run a CCS query** from ECH:

```
GET /on-prem:<index-name>/_search
```

### Firewall requirements

| Port | Direction | Required for |
|---|---|---|
| 9200/tcp | Inbound to on-prem from ECH egress IPs | CCS queries |
| 5601/tcp | Internal only | Kibana (not needed externally if managed via ECH) |
| 8220/tcp | Internal only | Fleet Server (agents on the on-prem network) |

The installer opens 9200, 5601, and 8220 in the local firewall (`firewalld`/`ufw`). You must also open 9200 inbound on any upstream network firewall or cloud security group.

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

### 2026-10-05 — CCS support and additional air-gapped hardening
- **Cross-Cluster Search from ECH** — new interactive prompt; installer creates a cross-cluster API key and prints step-by-step ECH console instructions in the post-install summary
- **`server.publicBaseUrl`** — set automatically in `kibana.yml` so alert notification links, share URLs, and report deep-links resolve correctly
- **AI Assistant disabled by default** — `xpack.observabilityAIAssistant.enabled: false` prevents repeated outbound connections to `kibana-knowledge-base-artifacts.elastic.co`; documented how to re-enable once an LLM connector is configured
- **Agent self-upgrade and ML model limitations** documented in README
- CA fingerprint saved globally and included in CCS post-install summary

### 2026-10-05 — Initial release
- Air-gapped single-node installer derived from [elastic-onprem-installer](https://github.com/Raricoza/elastic_onprem_installer)
- Package directory prompt with validation: verifies all three components are present and match version
- Local `.rpm` / `.deb` installation via `rpm --nosignature` and `dpkg -i`
- All post-install security, enrollment, and Fleet Server setup identical to the online installer
- Custom cluster name, node name, data directory, and log directory prompts
- GeoIP downloader disabled automatically (`ingest.geoip.downloader.enabled: false`)
- Elastic Maps Service disabled automatically (`map.includeElasticMapsService: false`)
- Telemetry disabled automatically (`telemetry.enabled: false`)
- Optional local Elastic Package Registry (EPR) URL prompt; sets `xpack.fleet.registryUrl` if provided
- `fontconfig` prerequisite check with warning for Kibana PDF/PNG reporting
