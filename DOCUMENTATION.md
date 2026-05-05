# Oracle RAC Services — Checkmk MKP Technical Documentation

## Table of Contents

1. [Overview](#1-overview)
2. [Requirements](#2-requirements)
   - [2.1 Checkmk Agent Requirements](#21-checkmk-agent-requirements)
   - [2.2 Checkmk Server Requirements](#22-checkmk-server-requirements)
3. [Installation & Configuration](#3-installation--configuration)
   - [3.1 Importing the MKP](#31-importing-the-mkp)
   - [3.2 Deploying the Agent Script](#32-deploying-the-agent-script)
   - [3.3 Configuring Rules in Checkmk](#33-configuring-rules-in-checkmk)
   - [3.4 How the Bakery Works](#34-how-the-bakery-works)
4. [Monitored Metrics & Services](#4-monitored-metrics--services)
   - [4.1 Service Overview](#41-service-overview)
   - [4.2 Metric Descriptions](#42-metric-descriptions)
   - [4.3 Check States & Logic](#43-check-states--logic)
5. [Troubleshooting](#5-troubleshooting)
   - [5.1 Agent-Side Troubleshooting](#51-agent-side-troubleshooting)
   - [5.2 Server-Side Troubleshooting](#52-server-side-troubleshooting)
6. [Uninstallation](#6-uninstallation)
7. [Security Considerations](#7-security-considerations)
8. [Known Limitations & Compatibility Notes](#8-known-limitations--compatibility-notes)
9. [Appendix](#9-appendix)
   - [9.1 File Structure of the MKP](#91-file-structure-of-the-mkp)
   - [9.2 Example Agent Output](#92-example-agent-output)
   - [9.3 Glossary](#93-glossary)
   - [9.4 References & Further Reading](#94-references--further-reading)

---

## 1. Overview

**Oracle RAC Services** is a Checkmk Monitoring Extension Package (MKP) that
monitors Oracle Real Application Clusters (RAC) and the Oracle Cluster Ready
Services (CRS) infrastructure. It collects CRS health, voting disk availability,
cluster resource status, and Oracle Cluster Registry (OCR) integrity from every
monitored RAC node.

| Attribute | Value |
|-----------|-------|
| Plugin type | Agent-based (Perl agent plugin + Python check plugins) |
| Agent section | `oracle_rac_services` |
| Separator | Pipe (`\|`, ASCII 124) |
| Number of check plugins | 5 |
| Number of WATO rule sets | 1 |
| Check interval | 15 minutes (all metrics) |
| Cluster-aware | Yes — all check plugins implement `cluster_check_function` |
| Cluster algorithm | WorstOf (reports the worst state across all RAC nodes) |

### Supported Checkmk editions

| Edition | Supported | Notes |
|---------|-----------|-------|
| Checkmk Raw (CRE) | Yes | Manual agent deployment only; no bakery |
| Checkmk Standard (CSE) | Yes | Manual agent deployment only; no bakery |
| Checkmk Cloud (CCE) | Yes | Full support including bakery |
| Checkmk Enterprise (CEE) | Yes | Full support including bakery |
| Checkmk MSP (CME) | Yes | Full support including bakery |

### Supported Checkmk versions

| Version | Status |
|---------|--------|
| 2.3.x | Supported (minimum required) |
| 2.4.x | Supported |

### Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0.0 | 2026-04-30 | Initial release — CRS health, voting disks, resource status, OCR integrity |

---

## 2. Requirements

### 2.1 Checkmk Agent Requirements

#### Operating system

| Platform | Bakery deployment | Manual deployment |
|----------|------------------|-------------------|
| Linux (x86-64, ARM) | Yes | Yes |
| AIX | Yes | Yes |
| Windows | No | No |

> **NOTE:** Windows is not supported. Oracle Grid Infrastructure on Windows uses
> a fundamentally different architecture that this plugin does not cover.

#### Software on the monitored host

| Requirement | Version / Notes |
|-------------|-----------------|
| Checkmk agent | Must match the server version (2.3.x or later) |
| Perl | 5.10 or later; no CPAN modules required — the plugin is fully self-contained |
| Oracle Grid Infrastructure | Must be installed and the CRS stack must be running |

The plugin calls two Oracle binaries directly:
- `$GRID_HOME/bin/crsctl` — CRS control utility
- `$GRID_HOME/bin/ocrcheck` — OCR integrity checker

Both must be present in the discovered Grid Home.

#### Grid Home discovery

The plugin resolves the Grid Home at runtime using this ordered strategy (first
match wins):

1. **`$GRID_HOME` environment variable** — if set and `$GRID_HOME/bin/crsctl`
   exists, this path is used immediately.
2. **oratab file** — the plugin reads `/etc/oratab` (Linux) or
   `/var/opt/oracle/oratab` (AIX/Solaris) and prefers entries whose SID begins
   with `+` (e.g. `+ASM`, `+APX`), since these are Grid/ASM SIDs.
3. **Any oratab entry** whose `ORACLE_HOME` contains `bin/crsctl` is accepted
   as a fallback.

If none of these strategies yields a valid Grid Home, the plugin emits the
section header (`<<<oracle_rac_services:sep(124)>>>`) with no data rows and
exits cleanly — Checkmk will not go stale.

#### Required user permissions

The Checkmk agent on Linux runs as **root** by default, which is sufficient.
If the agent runs as a non-root user:

| Requirement | Detail |
|-------------|--------|
| Group membership | User must belong to `oinstall` and/or `asmadmin` (exact groups depend on the Oracle installation) |
| Execute permission | `crsctl` and `ocrcheck` must be executable by the agent user |
| CRS socket access | `crsctl` communicates with the CRS daemon via local UNIX sockets under `/var/run/oracle/`; the agent user must have read access |

Example `sudoers` entry if the agent runs as `cmk`:

```
cmk ALL=(root) NOPASSWD: /u01/app/grid/19.0.0/bin/crsctl, /u01/app/grid/19.0.0/bin/ocrcheck
```

If using sudo, set `$GRID_HOME` in the agent environment and prefix the
commands in `oracle_rac_services.pl` accordingly.

#### Network ports

None. All data is collected via local process execution (`crsctl`, `ocrcheck`).
No TCP/UDP ports are opened by the plugin.

#### Required environment variables and config files

| Resource | Purpose | Required |
|----------|---------|----------|
| `/etc/oratab` or `/var/opt/oracle/oratab` | Grid Home discovery | No — only needed if `$GRID_HOME` is not set |
| `$GRID_HOME` | Explicit Grid Home override | No — discovered automatically from oratab |
| `$ORACLE_SID` | Used by Oracle tools; set by the plugin to the discovered SID | Set by plugin automatically |

The plugin sets the following environment variables before executing Oracle
commands, ensuring English-language output regardless of the OS locale:

```
ORACLE_SID       = <discovered SID>
ORACLE_HOME      = <discovered Grid Home>
GRID_HOME        = <discovered Grid Home>
LD_LIBRARY_PATH  = <Grid Home>/lib          (Linux)
LIBPATH          = <Grid Home>/lib          (AIX)
SRVM_PROPERTY_DEFS = -Duser.language=en -Duser.country=US
NLS_LANG         = AMERICAN_AMERICA
PATH             = <Grid Home>/bin:$PATH
```

---

### 2.2 Checkmk Server Requirements

#### Minimum version and edition

| Attribute | Value |
|-----------|-------|
| Minimum Checkmk version | **2.3.0p1** |
| Bakery support | Enterprise, Cloud, and MSP editions only |
| Check and rule functionality | All editions |

#### Python environment

The check plugins use only Python packages that ship with Checkmk 2.3+:

| Package | Source |
|---------|--------|
| `cmk.agent_based.v2` | Checkmk core |
| `cmk.rulesets.v1` | Checkmk core |
| `cmk.graphing.v1` | Checkmk core |
| `cmk.ccc.debug` / `cmk.utils.debug` | Checkmk core (version-dependent path) |

No pip packages or third-party libraries are required.

#### Disk space

Two metrics produce RRD performance data files on the server:

| Metric | RRD name | Typical size |
|--------|----------|-------------|
| m5015 — Voting Disk Count | `rac_voting_disk_count` | ~400 KB per service |
| m5020 — CRS Resource Status | `rac_crs_status` | ~400 KB per service |

The remaining three metrics (m5000, m5010, m5030) are binary and produce no
RRD data.

#### Permissions on the Checkmk server

Standard Checkmk site-user permissions are sufficient. No elevated privileges
are required to install or run this MKP.

---

## 3. Installation & Configuration

### 3.1 Importing the MKP

#### Via the web interface

1. Download the latest `oracle_rac_services-X.Y.Z.mkp` from the
   [Releases page](https://github.com/TazamaTech-Software/Checkmk-Oracle-RAC-Services/releases).
2. Log in to Checkmk as an administrator.
3. Navigate to **Setup → Extension packages**.
4. Click **Upload package**, select the `.mkp` file, and click **Upload**.
5. The package appears in the list with status **Enabled**.

> **NOTE:** No site restart is required. Extension packages are loaded
> dynamically in Checkmk 2.3+.

#### Via the command line

Log in as the Checkmk site user, then:

```bash
# Copy the MKP to the site first (if needed)
scp oracle_rac_services-1.0.0.mkp <checkmk-server>:/tmp/

# Install
mkp install /tmp/oracle_rac_services-1.0.0.mkp

# Verify
mkp list | grep oracle_rac_services
```

Expected output of `mkp list`:

```
oracle_rac_services  1.0.0  Oracle RAC Services Monitoring
```

#### Verifying successful installation

```bash
# Check that all Python files are importable
python3 -c "import cmk_addons.plugins.oracle_rac_services.oracle_rac_services_metrics"

# Confirm the agent plugin is present
ls -l ~/local/share/check_mk/agents/plugins/oracle_rac_services.pl
```

Check plugins are registered in the Checkmk web interface under
**Setup → Service monitoring rules → Oracle RAC Services Computer Metrics**.

---

### 3.2 Deploying the Agent Script

#### What the script does

`oracle_rac_services.pl` is a self-contained Perl script that:

1. Discovers the Oracle Grid Home from the environment or oratab.
2. Sets the Oracle execution environment (locale, library paths).
3. Runs `crsctl` and `ocrcheck` to collect 5 metrics.
4. Emits the results as a pipe-delimited Checkmk agent section.

The script has no external Perl module dependencies and no writable
configuration file. All behavior is determined by the Oracle environment
on the host.

#### Option A — Agent Bakery (Enterprise/Cloud/MSP only, recommended)

> **NOTE:** This option requires a Checkmk edition that includes the Agent
> Bakery (CEE, CCE, or CME). It is not available in Checkmk Raw or Standard.

1. In Checkmk go to **Setup → Agents → Agent rules** and search for
   **Oracle RAC Services**.
2. Create a new rule, set **enabled = true**, and assign it to the host group
   or folder containing your RAC nodes.
3. Navigate to **Setup → Agents → Windows, Linux, Solaris, AIX** and click
   **Bake agents**.
4. Deploy the baked agent package to the target hosts using your normal
   mechanism (Checkmk auto-update, Ansible, manual RPM/DEB install, etc.).

The baked agent places the plugin at:

```
# Linux
/usr/lib/check_mk_agent/plugins/oracle_rac_services.pl

# AIX
/usr/check_mk/lib/plugins/oracle_rac_services.pl
```

#### Option B — Manual deployment (all editions)

```bash
# Linux
sudo cp oracle_rac_services.pl /usr/lib/check_mk_agent/plugins/
sudo chmod 755 /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl
sudo chown root:root /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl

# AIX
cp oracle_rac_services.pl /usr/check_mk/lib/plugins/
chmod 755 /usr/check_mk/lib/plugins/oracle_rac_services.pl
```

#### Required configuration before deployment

The only configurable value inside the script is the expected number of voting
disks, used by metric **m5010** (which is disabled by default):

```perl
# Line 28 of oracle_rac_services.pl
my $EXPECTED_VOTING_DISKS = 3;   # Adjust to match your cluster
```

Edit this before copying the script if your cluster uses a number other than 3.
All other behavior is determined at runtime from the Oracle environment.

#### Triggering service discovery after deployment

After the script is deployed and producing output, run a service discovery on
the host:

```bash
# As site user — discover new services
cmk -I <hostname>

# Apply changes
cmk -R
```

Or via the web interface: **Setup → Hosts → <hostname> → Run service discovery**.

#### Verifying the script output

```bash
# Run as root on the monitored host
perl /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl

# From the Checkmk server, inspect cached agent output
cmk --debug --cache <hostname> | grep -A 20 'oracle_rac_services'

# Or dump a fresh agent run via the agent controller
cmk-agent-ctl dump | grep -A 20 'oracle_rac_services'
```

Expected output from a healthy cluster (SID `+ASM`, 3 voting disks):

```
<<<oracle_rac_services:sep(124)>>>
+ASM|5000|0|ERRORLINE=|None|None|None|None
+ASM|5010|0|ERRORLINE=|None|None|None|None
+ASM|5015|3|LINE=Located 3 voting disk(s)|None|None|None|None
+ASM|5020|0|ERRORLINE=|None|None|None|None
+ASM|5030|0|ERRORLINE=|None|None|None|None
```

---

### 3.3 Configuring Rules in Checkmk

#### Locating the rule set

**Setup → Service monitoring rules → Oracle RAC Services Computer Metrics**

(Direct path: search "Oracle RAC Services" in the Setup search bar.)

Rule set name (internal identifier): `oracle_rac_services_parameters`

The rule set appears under the **Databases** topic.

#### Available parameters

The rule contains one sub-section per metric. Each metric has four fields:

| Parameter | Type | Accepted values | Description |
|-----------|------|-----------------|-------------|
| `enabled` | Boolean | `true` / `false` | Whether the metric is evaluated. Disabled metrics produce no service and no alert, even if data is present in the agent output. |
| `warning` | String (numeric or `NaN`) | Any number or literal `NaN` | Threshold value for WARNING state. `NaN` disables the WARNING threshold. Validated against the regex `([-]?([0-9]+[.])?[0-9]+\|NaN)`. |
| `critical` | String (numeric or `NaN`) | Any number or literal `NaN` | Threshold value for CRITICAL state. `NaN` disables the CRITICAL threshold. |
| `type` | Read-only string | `MAX` or `MIN` | Direction of the threshold comparison. `MAX` = alert when value *exceeds* the threshold (higher is worse). `MIN` = alert when value *falls below* the threshold (lower is worse). This field is fixed per metric and cannot be changed via the GUI. |

#### Default parameter values

| Metric | enabled | type | warning | critical |
|--------|---------|------|---------|----------|
| m5000 — CRS Failures | `true` | MAX | `0.9` | `NaN` |
| m5010 — Voting Disk Match | **`false`** | MAX | `0.9` | `NaN` |
| m5015 — Voting Disk Count | `true` | MIN | `2` | `1` |
| m5020 — CRS Resource Status | `true` | MAX | `0.9` | `NaN` |
| m5030 — OCR Integrity | `true` | MAX | `0.9` | `NaN` |

These defaults are compiled into the check plugin
(`check_default_parameters` in `oracle_rac_services.py`) and apply when no
matching WATO rule exists for a host.

#### Threshold semantics for binary metrics

Metrics m5000, m5010, m5020, and m5030 produce only two values: `0` (healthy)
or `1` (problem). A warning threshold of `0.9` means any value ≥ 1 triggers
WARNING — effectively "alert on any problem." To escalate to CRITICAL instead,
set **critical = `0.9`** (and optionally set warning to `NaN` to suppress the
intermediate WARNING state).

#### Example rule configurations

**Alert CRITICAL immediately on any CRS failure (skip WARNING):**

```
m5000:
  enabled: true
  type: MAX        (read-only)
  warning: NaN
  critical: 0.9
```

**Alert if fewer than 3 voting disks are found (stricter than default):**

```
m5015:
  enabled: true
  type: MIN        (read-only)
  warning: 3
  critical: 2
```

**Disable OCR monitoring on a specific host group:**

```
m5030:
  enabled: false
```

#### Rule assignment and precedence

Rules follow standard Checkmk precedence: rules at a more specific folder or
host label level override rules at a higher level. Use the **Analyse** button
on the rule set page to verify which rule applies to a given host.

The rule condition uses `HostAndItemCondition`. Since services have no item,
rules are scoped by host conditions only (folder, host label, host tag). The
item filter field in the condition is not applicable and should be left empty.

---

### 3.4 How the Bakery Works

#### What is baked

The bakery plugin (`cmk/base/cee/plugins/bakery/oracle_rac_services.py`)
is called by the Agent Bakery when generating agent packages. It performs
one action: if the plugin is enabled via a WATO rule (`conf['enabled'] == True`),
it includes `oracle_rac_services.pl` in the baked package for:

- `OS.LINUX` — deployed to `/usr/lib/check_mk_agent/plugins/`
- `OS.AIX` — deployed to `/usr/check_mk/lib/plugins/`

No configuration file is generated; no systemd unit is created. The Perl
script has no baked-in parameters — all behavior is determined at runtime from
the Oracle environment.

If the plugin is **disabled** (no matching rule, or rule explicitly sets
enabled = false), the Perl script is excluded from the baked agent. Hosts
that receive this agent package will not run the plugin.

#### Baking workflow

**GUI:**

1. Configure the agent rule (Section 3.3).
2. Go to **Setup → Agents → Windows, Linux, Solaris, AIX**.
3. Click **Bake agents** and wait for the bake job to complete.
4. Deploy the agent package via your normal mechanism.

**CLI (as site user):**

```bash
# Bake all agents
cmk -v --bake-agents

# Bake for a specific host only
cmk -v --bake-agents <hostname>
```

#### Verifying baked content

```bash
# List baked agent packages
ls /omd/sites/<site>/var/check_mk/agents/

# Inspect a specific package (replace with actual filename)
tar -tzf /omd/sites/<site>/var/check_mk/agents/<package>.tar.gz | grep oracle
```

You should see `plugins/oracle_rac_services.pl` in the archive.

> **WARNING:** Do not modify `oracle_rac_services.pl` inside a baked package.
> Changes to the source file must be made in
> `local/share/check_mk/agents/plugins/oracle_rac_services.pl` (on the
> Checkmk server), followed by a new bake and re-deployment.

---

## 4. Monitored Metrics & Services

### 4.1 Service Overview

One service is created per check plugin per host. With all default-enabled
metrics, four services are created per host (m5010 is disabled by default
and creates no service unless enabled).

| Service Name | Check Plugin | Default | Description |
|---|---|---|---|
| `Oracle RAC CRS Failures` | `oracle_m5000` | Enabled | CRS daemon health status |
| `Oracle RAC CRS Voting Disk` | `oracle_m5010` | **Disabled** | Expected voting disk count validation |
| `Oracle RAC Voting Disks Count` | `oracle_m5015` | Enabled | Actual voting disk count |
| `Oracle RAC CRS Status` | `oracle_m5020` | Enabled | Count of CRS resources not in target state |
| `Oracle RAC OCR Integrity` | `oracle_m5030` | Enabled | Oracle Cluster Registry integrity |

All five check plugins read from the same agent section (`oracle_rac_services`)
and implement `cluster_check_function`. Node matching during cluster checks is
done by **metric name only** — the Oracle SID reported by the agent (e.g.
`+ASM1` on one node, `+ASM2` on another) does not affect service identity or
cluster aggregation. Every node that reports data for a metric contributes to
the WorstOf result regardless of its instance SID suffix.

---

### 4.2 Metric Descriptions

#### m5000 — Oracle RAC CRS Failures

| Attribute | Value |
|-----------|-------|
| Check plugin | `oracle_m5000` |
| Service name | `Oracle RAC CRS Failures` |
| Source command | `crsctl check crs` |
| Value type | Binary integer |
| Unit | None (0 = healthy, 1 = failure) |
| Threshold type | MAX |
| Default warning | `0.9` |
| Default critical | `NaN` (disabled) |
| Performance counter | None |
| Enabled by default | Yes |

The plugin scans `crsctl check crs` output for the keywords `Cannot` or
`Failure` (case-insensitive). On a match, value = `1` and the matched line
plus the preceding line are reported in `OPTION1` as `ERRORLINE=<text>`.

**Alert text:** `At least one CRS Failure found in: '<ERRORLINE>'.`

---

#### m5010 — Oracle RAC CRS Voting Disk Match

| Attribute | Value |
|-----------|-------|
| Check plugin | `oracle_m5010` |
| Service name | `Oracle RAC CRS Voting Disk` |
| Source command | `crsctl query css votedisk` |
| Value type | Binary integer |
| Unit | None (0 = expected count confirmed, 1 = mismatch) |
| Threshold type | MAX |
| Default warning | `0.9` |
| Default critical | `NaN` (disabled) |
| Performance counter | None |
| Enabled by default | **No** |

Checks whether the command output contains the literal string
`Located <N> voting disk`, where `<N>` is the value of `$EXPECTED_VOTING_DISKS`
in the Perl script (default `3`). This is a strict string match — the expected
count must be configured correctly in the script before deployment.

> **TIP:** For flexible count monitoring, prefer **m5015** (which reports the
> actual count without requiring a hardcoded expectation). Enable m5010 only
> when you need a binary pass/fail check against a fixed expected count.

**Alert text:** `Issue for at least one CRS Voting Disk found in: '<ERRORLINE>'.`

---

#### m5015 — Oracle RAC Voting Disks Count

| Attribute | Value |
|-----------|-------|
| Check plugin | `oracle_m5015` |
| Service name | `Oracle RAC Voting Disks Count` |
| Source command | `crsctl query css votedisk` |
| Value type | Integer |
| Unit | Count of voting disks |
| Threshold type | MIN |
| Default warning | `2` (WARN when fewer than 2 disks found) |
| Default critical | `1` (CRIT when fewer than 1 disk found) |
| Performance counter | `rac_voting_disk_count` |
| Enabled by default | Yes |

Extracts the actual voting disk count from the line matching the regex
`Located (\d+) voting disk`. If this line is absent (command failure or
unexpected output), value = `-1`, which immediately breaches the CRITICAL
threshold.

The perfometer in Checkmk renders a bar graph with a focus range of `[0, 3)`,
using light-blue color.

**Alert text:**
`Only <MONVALUE> voting disk(s) located. Expected at least <THRESHOLD>. Details: '<LINE>'.`

---

#### m5020 — Oracle RAC CRS Resource Status

| Attribute | Value |
|-----------|-------|
| Check plugin | `oracle_m5020` |
| Service name | `Oracle RAC CRS Status` |
| Source command | `crsctl stat res -w '(TARGET = ONLINE) AND (STATE != ONLINE)' -v` |
| Value type | Non-negative integer |
| Unit | Count of offline resources |
| Threshold type | MAX |
| Default warning | `0.9` (WARN on any offline resource) |
| Default critical | `NaN` (disabled) |
| Performance counter | `rac_crs_status` |
| Enabled by default | Yes |

Counts CRS resources that have `TARGET = ONLINE` but `STATE != ONLINE`. Each
such resource increments the counter. The names, target servers, and states of
affected resources are concatenated in `OPTION1` as `ERRORLINE=<text>` (pipe
characters within resource names are replaced with `?`; values longer than
512 characters are truncated with ` ...`).

Value = `0` means all targeted resources are online.

The perfometer renders a bar graph with focus range `(0, 1)` using light-blue
color.

**Alert text:**
`For at least one CRS Resource issue were found in: '<ERRORLINE>'.`

---

#### m5030 — Oracle RAC OCR Integrity

| Attribute | Value |
|-----------|-------|
| Check plugin | `oracle_m5030` |
| Service name | `Oracle RAC OCR Integrity` |
| Source command | `ocrcheck` |
| Value type | Binary integer |
| Unit | None (0 = both checks passed, 1 = one or more failed) |
| Threshold type | MAX |
| Default warning | `0.9` |
| Default critical | `NaN` (disabled) |
| Performance counter | None |
| Enabled by default | Yes |

Validates that `ocrcheck` output contains **both** of the following strings:

1. `Device/File integrity check succeeded`
2. `Cluster registry integrity check succeeded`

If either string is absent, value = `1` and the missing check names are
reported in `OPTION1`. Value = `1` also results when `ocrcheck` cannot be
executed (binary missing or permission denied).

**Alert text:**
`The Oracle Cluster Registration Utility (ocrcheck) returned error: '<ERRORLINE>'.`

---

### 4.3 Check States & Logic

#### State calculation

All five check plugins share a single state calculation function (`calc_state`
in `oracle_rac_services_lib.py`). The logic per threshold type:

**MAX (metrics m5000, m5010, m5020, m5030):**

```
if value > critical  →  CRIT   (when critical ≠ NaN)
if value > warning   →  WARN   (when warning ≠ NaN)
otherwise            →  OK
```

**MIN (metric m5015 only):**

```
if value < critical  →  CRIT   (when critical ≠ NaN)
if value < warning   →  WARN   (when warning ≠ NaN)
otherwise            →  OK
```

CRITICAL is evaluated before WARNING. If both thresholds are set, the highest
severity wins.

#### Disabled metric behavior

If a metric is marked `enabled = false` in the active rule, the check function
returns OK immediately without evaluating any threshold. This means:
- The service still exists (if it was previously discovered while enabled).
- It will always show OK regardless of the measured value.
- To fully suppress the service, disable it in the rule *before* running
  discovery, or manually remove the service.

#### No-data behavior

If the agent section contains no data row for the metric, `check_oracle` yields:

```
State.UNKNOWN — "No data received for metric <metric>"
```

This occurs when the agent plugin stopped running or the metric was disabled
in the Perl script. UNKNOWN state does not write to the RRD — performance
graphs will show a gap.

#### Cluster behavior

All five check plugins implement `cluster_check_function` using the **WorstOf**
algorithm:

- Each node's individual state is calculated using the same `calc_state` logic.
- `State.worst(*node_states.values())` selects the most severe state across all
  nodes.
- The displayed metric value uses the worst-case value:
  - For MAX metrics: the **maximum** value across all nodes.
  - For MIN metrics: the **minimum** value across all nodes.

A single node reporting a problem causes the entire cluster service to show
that problem state.

Node matching is done by **metric name only**, not by Oracle SID. Cluster
checks therefore work correctly even when RAC nodes use different ASM instance
names (e.g. `+ASM1` on node 1, `+ASM2` on node 2) — all nodes contribute
to the single cluster service regardless of their instance SID suffix.

---

## 5. Troubleshooting

### 5.1 Agent-Side Troubleshooting

#### Running the plugin manually

```bash
# Run as root on the monitored host
perl /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl

# AIX
perl /usr/check_mk/lib/plugins/oracle_rac_services.pl
```

If the script emits only the section header with no data rows:

```
<<<oracle_rac_services:sep(124)>>>
```

The Grid Home was not found. See "Grid Home not discovered" below.

#### Common errors and solutions

---

**Grid Home not discovered (empty section)**

```bash
# Inspect oratab
cat /etc/oratab | grep -v '^#' | grep -v '^$'

# Try to locate crsctl manually
find /u01 /app /oracle /grid -name crsctl 2>/dev/null

# Test explicit override
GRID_HOME=/u01/app/19.0.0/grid perl /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl
```

If the explicit override works, set `GRID_HOME` in the Checkmk agent
environment:

```bash
# /etc/default/check_mk_agent  (distribution-dependent)
export GRID_HOME=/u01/app/19.0.0/grid
```

Alternatively, add a correct `+ASM` entry to `/etc/oratab`:

```
+ASM:/u01/app/19.0.0/grid:N
```

---

**`crsctl command not available` in OPTION1**

The plugin resolved a Grid Home from oratab or the environment but the binary
does not exist at `$GRID_HOME/bin/crsctl`.

```bash
# Verify
test -x "$GRID_HOME/bin/crsctl" && echo "OK" || echo "MISSING"
ls -l "$GRID_HOME/bin/crsctl" "$GRID_HOME/bin/ocrcheck"
```

Correct the `GRID_HOME` path or the oratab entry.

---

**Permission denied**

```bash
# Identify agent user
ps aux | grep check_mk_agent

# Test as that user
sudo -u <agent-user> $GRID_HOME/bin/crsctl check crs
sudo -u <agent-user> $GRID_HOME/bin/ocrcheck
```

Add the agent user to the appropriate groups:

```bash
usermod -aG oinstall <agent-user>
usermod -aG asmadmin <agent-user>
```

---

**Plugin not running at all (section missing from agent output)**

```bash
# Check file exists and is executable
ls -l /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl

# Check for syntax errors
perl -c /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl

# Run agent manually to confirm section appears
check_mk_agent | head -100
```

---

**Plugin times out**

`crsctl` or `ocrcheck` may hang if CRS is in a partial failure state. The
Checkmk agent has a global plugin timeout (default: 60 seconds). If CRS is
unresponsive, the plugin will be killed and the section will be absent.

Run manually with a timeout to reproduce:

```bash
timeout 30 perl /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl
```

If the plugin times out, CRS itself is the problem — investigate with Oracle
support tooling, not with this plugin.

---

#### Enabling debug output on the agent side

The Perl plugin writes warnings to `stderr` (captured in the agent log) for
failed command executions. To see these:

```bash
perl /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl 2>/tmp/rac_debug.log
cat /tmp/rac_debug.log
```

#### Agent log file locations

| Platform | Log location |
|----------|-------------|
| Linux (systemd) | `journalctl -u check-mk-agent.socket` |
| Linux (xinetd) | `/var/log/syslog` or `/var/log/messages` |
| AIX | `/var/log/check_mk/check_mk_agent.log` |

---

### 5.2 Server-Side Troubleshooting

#### Inspecting service discovery output

```bash
# As site user — list discovered services for a host
cmk -v --checks=oracle_m5000,oracle_m5010,oracle_m5015,oracle_m5020,oracle_m5030 <hostname>

# Re-run discovery
cmk -vv -I <hostname>
```

#### Debugging check execution

```bash
# Verbose check run for all oracle plugins
cmk -v --debug <hostname> 2>&1 | grep -A 5 oracle

# Debug a single check plugin with full output
cmk -v --debug --checks=oracle_m5015 <hostname>
```

The `--debug` flag activates the `if debug.enabled():` branches in
`oracle_rac_services_lib.py`, which print the parsed section dictionary and
intermediate state calculations to stdout.

#### Inspecting raw agent output

```bash
# From cached output (updated on last agent contact)
cat /omd/sites/<site>/tmp/check_mk/cache/<hostname> | grep -A 20 oracle_rac_services

# From a live agent run
cmk --debug --cache <hostname> | grep -A 20 oracle_rac_services
```

#### Common server-side errors and solutions

---

**Services go UNKNOWN — "No data received for metric `<metric>`"**

1. Verify the agent plugin is running and producing output (Section 5.1).
2. Verify the metric is still enabled in the active WATO rule.
3. If the MKP was recently updated or the plugin redeployed, run a full
   re-discovery:

```bash
cmk -I <hostname>
cmk -R
```

---

**Services not discovered after MKP import**

```bash
cmk -II <hostname>   # force full re-discovery
cmk -R
```

---

**Thresholds not applied — service always OK despite problems**

1. Check the active rule via the GUI Analyse button.
2. Confirm the metric's `enabled` field is `true` in the active rule.
3. Confirm `warning` and `critical` are numeric values (not `NaN`) for the
   state you expect.
4. Run the check with debug to see the raw value and threshold evaluation:

```bash
cmk -v --debug --checks=oracle_m5000 <hostname> 2>&1 | grep -i "m5000\|state\|warn\|crit"
```

---

**Performance graphs not appearing for m5015 or m5020**

- Graphs only appear when the service is in OK or WARN state. UNKNOWN state
  does not write RRD data.
- Confirm that the metric's `counter` field is set (it is for m5015 and m5020;
  not for m5000, m5010, m5030).
- Check RRD file existence:

```bash
ls /omd/sites/<site>/var/pnp4nagios/perfdata/<hostname>/
# Look for files named rac_voting_disk_count.rrd and rac_crs_status.rrd
```

---

**Bakery not including the agent script**

1. Confirm an agent rule for **Oracle RAC Services** exists and matches the
   host.
2. Re-bake: `cmk -v --bake-agents <hostname>`.
3. Inspect the baked package:

```bash
ls /omd/sites/<site>/var/check_mk/agents/
tar -tzf /omd/sites/<site>/var/check_mk/agents/<package>.tar.gz | grep oracle
```

If the script is absent, the agent rule may not be matching (check folder
assignment and host labels).

---

#### Server log locations

| Log | Location | Relevant for |
|-----|----------|-------------|
| Microcore (CEE) | `/omd/sites/<site>/var/log/cmc.log` | Check scheduling, staleness |
| Nagios core (RAW) | `/omd/sites/<site>/var/log/nagios/nagios.log` | Check scheduling |
| GUI/REST errors | `/omd/sites/<site>/var/log/web.log` | MKP install errors |
| Agent output cache | `/omd/sites/<site>/tmp/check_mk/cache/<hostname>` | Raw agent data |
| Check output | `/omd/sites/<site>/tmp/check_mk/counters/<hostname>` | Counter state |

---

## 6. Uninstallation

### Remove the MKP from the Checkmk server

**Via the web interface:**

1. Navigate to **Setup → Extension packages**.
2. Find `oracle_rac_services` and click **Delete**.

**Via the command line:**

```bash
mkp remove oracle_rac_services
```

> **NOTE:** Removing the MKP does not automatically delete services that were
> already discovered. Existing services will go UNKNOWN on the next check cycle
> because the check plugins are no longer present.

### Remove stale services

After removing the MKP, remove the Oracle RAC services from all affected hosts:

```bash
# For each affected host
cmk -I <hostname>   # re-discovery will remove services with no matching plugin
cmk -R
```

Or remove services manually via **Monitor → <host> → Services → Remove services**.

### Remove the agent plugin from monitored hosts

**Manual removal:**

```bash
# Linux
sudo rm /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl

# AIX
rm /usr/check_mk/lib/plugins/oracle_rac_services.pl
```

**Via bakery:** Disable the Oracle RAC Services agent rule, re-bake, and
redeploy the agent package. The Perl script will be absent from the new package.

### Impact on monitoring data

- RRD files for `rac_voting_disk_count` and `rac_crs_status` are preserved on
  the filesystem even after services are removed. They can be deleted manually
  from `/omd/sites/<site>/var/pnp4nagios/perfdata/<hostname>/` if no longer
  needed.
- Historical check results and event logs are not affected by MKP removal.

---

## 7. Security Considerations

### Data accessed and transmitted

The agent plugin accesses only Oracle cluster state information via local
process execution. It does **not** connect to any database, does not read
Oracle data files, and does not use any Oracle credentials.

Data transmitted to the Checkmk server in the `oracle_rac_services` section:

- Oracle SID (e.g. `+ASM`) — the identifier of the Grid/ASM instance
- CRS health status (binary 0/1)
- Voting disk count (integer) and raw `crsctl` output line
- Names and states of CRS resources that are not in their target state
- OCR check result and missing check names

None of this data is confidential by Oracle security classification, but it
does reveal cluster topology and current fault state.

### Principle of least privilege

If the Checkmk agent cannot run as `root`, restrict access as narrowly as
possible:

```bash
# /etc/sudoers.d/checkmk-oracle
Defaults:cmk !requiretty
cmk ALL=(root) NOPASSWD: /u01/app/grid/19.0.0/bin/crsctl check crs
cmk ALL=(root) NOPASSWD: /u01/app/grid/19.0.0/bin/crsctl query css votedisk
cmk ALL=(root) NOPASSWD: /u01/app/grid/19.0.0/bin/crsctl stat res * -v
cmk ALL=(root) NOPASSWD: /u01/app/grid/19.0.0/bin/ocrcheck
```

If using sudo wrappers, update the `execute_oracle_command` subroutine in
the Perl script to prepend `sudo` to each command.

### Credentials

This plugin stores **no credentials**. No database passwords, no OS user
passwords, no API tokens. `crsctl` and `ocrcheck` use OS-level IPC to
communicate with the CRS daemon.

### Network exposure

The plugin runs locally on the agent host. The only network connection involved
is the standard Checkmk agent transport (TCP 6556 or agent controller TLS
tunnel) used to deliver the section output to the server. This is no different
from any other Checkmk agent plugin.

### Output sanitisation

The Perl script sanitises all values before including them in the pipe-delimited
output:
- Literal pipe characters (`|`) in Oracle output are replaced with `?` to
  prevent field splitting.
- Output strings are truncated to 512 characters with a ` ...` suffix to
  prevent unbounded agent output.

---

## 8. Known Limitations & Compatibility Notes

| Limitation | Detail |
|------------|--------|
| Windows not supported | Oracle Grid Infrastructure on Windows is not covered. The bakery plugin explicitly targets `OS.LINUX` and `OS.AIX` only. |
| No async execution | The plugin runs synchronously during the agent check cycle. If `crsctl` or `ocrcheck` hangs (e.g. during CRS restart), the agent will be delayed. |
| `$EXPECTED_VOTING_DISKS` is hardcoded | Metric m5010 requires editing the Perl script before deployment. There is no runtime configuration mechanism for this value. |
| English-only output | The plugin forces English locale via `NLS_LANG=AMERICAN_AMERICA` and `SRVM_PROPERTY_DEFS`. If Oracle is configured to produce output in a language that uses different success/failure phrases, the pattern matching in m5000 and m5030 may not work correctly. |
| Debug API path change | The plugin imports `cmk.ccc.debug` (2.4.0+) with a fallback to `cmk.utils.debug` (2.3.x). If Checkmk changes this path again in a future release, the import will fail. |
| One section per host | The agent section contains data for all SIDs found. If a host runs multiple Grid Homes (unusual), only one is discovered (the first match). |
| m5010 disabled by default | Enabling m5010 without adjusting `$EXPECTED_VOTING_DISKS` will produce false WARN alerts if the cluster has a different number of voting disks. |

### Upgrade notes

When upgrading from one plugin version to another:

1. Install the new MKP (it replaces the old one).
2. Re-bake and redeploy agents if using the bakery.
3. Run service re-discovery if new metrics were added or removed.
4. Review WATO rules — new default parameters may differ from previous versions.

---

## 9. Appendix

### 9.1 File Structure of the MKP

#### Repository layout

```
Checkmk-Oracle-RAC-Services/
├── .github/
│   └── workflows/
│       └── build.yml                          GitHub Actions CI/CD pipeline
├── .mkp-builder.ini                           Package metadata and build configuration
├── build.py                                   MKP build script (pure Python, no dependencies)
├── CHANGELOG.md                               Version history
├── DOCUMENTATION.md                           This document
├── LICENSE                                    GNU GPL v2
├── README.md                                  Quick-start configuration guide
└── local/                                     MKP payload (mirrors Checkmk site/local/)
    ├── lib/python3/
    │   ├── cmk/base/cee/plugins/bakery/
    │   │   └── oracle_rac_services.py         Bakery plugin (CEE/CCE/MSP only)
    │   └── cmk_addons/plugins/oracle_rac_services/
    │       ├── agent_based/
    │       │   ├── oracle_rac_services.py     Check plugin registrations (5 plugins)
    │       │   └── oracle_rac_services_lib.py Parsing, state calculation, cluster logic
    │       ├── graphing/
    │       │   └── oracle_rac_services.py     Metric and perfometer definitions
    │       ├── rulesets/
    │       │   ├── ruleset_oracle_rac_services.py     WATO rule set registration
    │       │   └── ruleset_oracle_rac_services_lib.py Rule form specification
    │       └── oracle_rac_services_metrics.py Central metric definitions (METRIC_DEF)
    └── share/check_mk/agents/plugins/
        └── oracle_rac_services.pl             Agent plugin (Perl, Linux + AIX)
```

#### MKP archive layout

The `.mkp` file is a gzip-compressed tar archive with the following structure:

```
oracle_rac_services-1.0.0.mkp  (tar.gz)
├── info                                       Package metadata (Python literal dict)
├── agents/
│   └── plugins/
│       └── oracle_rac_services.pl
└── lib/
    └── python3/
        ├── cmk/base/cee/plugins/bakery/
        │   └── oracle_rac_services.py
        └── cmk_addons/plugins/oracle_rac_services/
            ├── agent_based/
            │   ├── oracle_rac_services.py
            │   └── oracle_rac_services_lib.py
            ├── graphing/
            │   └── oracle_rac_services.py
            ├── oracle_rac_services_metrics.py
            └── rulesets/
                ├── ruleset_oracle_rac_services.py
                └── ruleset_oracle_rac_services_lib.py
```

---

### 9.2 Example Agent Output

#### Healthy cluster (SID: `+ASM`, 3 voting disks, all resources online)

```
<<<oracle_rac_services:sep(124)>>>
+ASM|5000|0|ERRORLINE=|None|None|None|None
+ASM|5010|0|ERRORLINE=|None|None|None|None
+ASM|5015|3|LINE=Located 3 voting disk(s)|None|None|None|None
+ASM|5020|0|ERRORLINE=|None|None|None|None
+ASM|5030|0|ERRORLINE=|None|None|None|None
```

#### Degraded cluster (CRS failure, 2 voting disks, one resource offline)

```
<<<oracle_rac_services:sep(124)>>>
+ASM|5000|1|ERRORLINE=CRS-4535: Cannot communicate with Cluster Ready Services CRS-4000: Command Check failed, or completed with errors.|None|None|None|None
+ASM|5010|1|ERRORLINE=Not found: 'Located 3 voting disk'|None|None|None|None
+ASM|5015|2|LINE=Located 2 voting disk(s)|None|None|None|None
+ASM|5020|1|ERRORLINE=ora.diskmon:rac1:OFFLINE|None|None|None|None
+ASM|5030|0|ERRORLINE=|None|None|None|None
```

#### No Grid Home found (plugin ran but no data collected)

```
<<<oracle_rac_services:sep(124)>>>
```

#### Field format reference

```
SID | MetricNumber | Value | Option1 | Option2 | Option3 | Option4 | Option5
```

| Field | Content |
|-------|---------|
| SID | Oracle SID (Grid/ASM instance name, e.g. `+ASM`) |
| MetricNumber | Raw metric number: `5000`, `5010`, `5015`, `5020`, `5030` |
| Value | Numeric metric value (integer or float parsed as float) |
| Option1 | Key=value string with additional context (e.g. `ERRORLINE=...`, `LINE=...`) |
| Option2–5 | Reserved; currently always `None` |

---

### 9.3 Glossary

| Term | Definition |
|------|------------|
| **ASM** | Oracle Automatic Storage Management — the cluster volume manager used in RAC environments |
| **CRS** | Cluster Ready Services — the Oracle component that manages cluster resources and health |
| **crsctl** | Oracle CLI tool for controlling and querying CRS; located in `$GRID_HOME/bin/` |
| **Grid Home** | The Oracle installation directory for Grid Infrastructure (CRS, ASM, network services) |
| **MKP** | Monitoring Extension Package — Checkmk's format for distributing plugins as a single installable archive (gzip-compressed tar) |
| **OCR** | Oracle Cluster Registry — a shared configuration repository for CRS; checked by `ocrcheck` |
| **ocrcheck** | Oracle CLI tool that validates OCR integrity; located in `$GRID_HOME/bin/` |
| **oratab** | A text file listing Oracle database and Grid instances with their home directories; typically `/etc/oratab` |
| **RAC** | Real Application Clusters — Oracle's multi-node database clustering technology |
| **WorstOf** | Checkmk cluster algorithm that reports the most severe state across all nodes |
| **Voting disk** | A shared disk used by CRS for node fencing and tie-breaking during split-brain scenarios |
| **WATO** | Web Administration Tool — Checkmk's configuration system; accessed via the **Setup** menu |
| **NaN** | "Not a Number" — used in threshold fields to indicate that a threshold level is disabled |
| **Perfometer** | Checkmk term for the bar-graph visualization shown in service list views |

---

### 9.4 References & Further Reading

| Resource | URL |
|----------|-----|
| MKP source repository | https://github.com/TazamaTech-Software/Checkmk-Oracle-RAC-Services |
| Checkmk MKP documentation | https://docs.checkmk.com/latest/en/mkps.html |
| Checkmk Agent Bakery API | https://docs.checkmk.com/latest/en/bakery_api.html |
| Checkmk agent-based check API v2 | https://docs.checkmk.com/latest/en/devel_check_plugins.html |
| Checkmk Extension Packages (Exchange) | https://exchange.checkmk.com |
| Oracle crsctl reference | https://docs.oracle.com/en/database/oracle/oracle-database/19/cwadd/oracle-clusterware-control-crsctl-utility-reference.html |
| Oracle ocrcheck reference | https://docs.oracle.com/en/database/oracle/oracle-database/19/cwadd/oracle-cluster-registry-ocr-administration.html |
| Oracle RAC voting disk documentation | https://docs.oracle.com/en/database/oracle/oracle-database/19/cwadd/managing-oracle-cluster-voting-disks.html |
