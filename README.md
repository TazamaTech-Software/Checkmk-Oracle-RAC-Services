# Oracle RAC Services — Checkmk Extension Package (MKP)

Checkmk extension for monitoring Oracle Real Application Clusters (RAC) and
Cluster Resource Services (CRS). Collects health and status data from every
RAC node via the Checkmk agent and evaluates the results on the Checkmk server.

---

## Table of Contents

1. [Requirements — Checkmk Agent Host](#1-requirements--checkmk-agent-host)
2. [Requirements — Checkmk Server](#2-requirements--checkmk-server)
3. [Configuration Steps](#3-configuration-steps)
   - [3.1 Import the MKP](#31-import-the-mkp)
   - [3.2 Deploy the Agent Plugin](#32-deploy-the-agent-plugin)
   - [3.3 Adjusting Thresholds via Rules](#33-adjusting-thresholds-via-rules)
   - [3.4 How the Bakery Works](#34-how-the-bakery-works)
4. [Agent Metric Reference](#4-agent-metric-reference)
5. [Troubleshooting](#5-troubleshooting)

---

## 1. Requirements — Checkmk Agent Host

### Operating system

| Platform | Supported |
|----------|-----------|
| Linux (x86-64, ARM) | Yes |
| AIX | Yes |
| Windows | No |

### Software

| Requirement | Notes |
|-------------|-------|
| Checkmk agent | Version matching the server (2.3.x or later) |
| Perl | 5.10 or later; standard installation, no extra modules needed |
| Oracle Grid Infrastructure / CRS | Must be installed and running; provides `crsctl` and `ocrcheck` |

### Oracle environment

The plugin locates the Grid Home automatically using the following strategy
(first match wins):

1. **`$GRID_HOME` environment variable** — set this if the agent runs under a
   user whose environment does not include the Oracle paths.
2. **`/etc/oratab`** (Linux) or **`/var/opt/oracle/oratab`** (AIX/Solaris) —
   the plugin prefers entries whose SID starts with `+` (e.g. `+ASM`).
3. **Any oratab entry** whose `ORACLE_HOME` contains `bin/crsctl`.

The plugin requires read-execute access to:
- `$GRID_HOME/bin/crsctl`
- `$GRID_HOME/bin/ocrcheck`

The Checkmk agent typically runs as `root` on Linux, which satisfies the
permissions needed by `crsctl` and `ocrcheck`. If it runs as a different user,
ensure that user has execute permission on those binaries and can read the CRS
configuration files (e.g. is a member of the `oinstall` or `asmadmin` group).

### Firewall / connectivity

No additional network ports are required. The plugin runs locally on the agent
host and its output is collected by the standard Checkmk agent mechanism.

---

## 2. Requirements — Checkmk Server

| Requirement | Value |
|-------------|-------|
| Checkmk version | **2.3.0p1 or later** |
| Edition for agent baking | **CEE / CCE / MSP** (Enterprise editions) |
| Edition for manual deployment | **All editions** (RAW included) |

The check plugins, rulesets, and graphing definitions work on all editions.
The **bakery** (automatic agent deployment) requires an Enterprise edition with
the Agent Bakery feature enabled.

---

## 3. Configuration Steps

### 3.1 Import the MKP

1. Download the latest `oracle_rac_services-X.Y.Z.mkp` from the
   [Releases page](https://github.com/TazamaTech-Software/Checkmk-Oracle-RAC-Services/releases).
2. In the Checkmk web interface go to **Setup → Extension packages**.
3. Click **Upload package**, select the `.mkp` file, and confirm.
4. The package status changes to *Enabled*. No restart of the site is required.

To install via the command line (as the site user):

```bash
cmk -v --package install oracle_rac_services-X.Y.Z.mkp
```

### 3.2 Deploy the Agent Plugin

#### Option A — Agent Bakery (CEE/CCE/MSP only, recommended)

The bakery plugin deploys `oracle_rac_services.pl` to monitored hosts
automatically as part of the baked agent package.

1. Go to **Setup → Agent rules → Agent plugins** (or search for
   *Oracle RAC Services*).
2. Create a rule that matches your RAC hosts and set **enabled = true**.
3. Go to **Setup → Agents → Windows, Linux, Solaris, AIX** and click
   **Bake agents**.
4. Deploy the newly baked agent to the target hosts via your normal
   mechanism (signature-based auto-update, Ansible, etc.).

The baked agent places the plugin at:

```
/usr/lib/check_mk_agent/plugins/oracle_rac_services.pl   (Linux)
/usr/check_mk/lib/plugins/oracle_rac_services.pl         (AIX)
```

#### Option B — Manual deployment (all editions)

Copy `oracle_rac_services.pl` from the MKP or this repository to the agent
plugin directory on the target host:

```bash
# Linux
cp oracle_rac_services.pl /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl
chmod 755 /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl

# AIX
cp oracle_rac_services.pl /usr/check_mk/lib/plugins/oracle_rac_services.pl
chmod 755 /usr/check_mk/lib/plugins/oracle_rac_services.pl
```

#### Adjusting the expected voting-disk count

The plugin validates that the number of voting disks found matches an expected
value. The default is **3**, which is the Oracle-recommended minimum for
production RAC clusters.

If your cluster uses a different count, edit the variable near the top of
`oracle_rac_services.pl` before deployment:

```perl
my $EXPECTED_VOTING_DISKS = 3;   # change to match your cluster
```

This only affects metric **m5010** (disabled by default — see
[Section 4](#4-agent-metric-reference)).

#### Verify the plugin runs

After deployment, trigger a manual agent run and check for the plugin section:

```bash
cmk-agent-ctl dump | grep -A 20 'oracle_rac_services'
```

Expected output (healthy cluster):

```
<<<oracle_rac_services:sep(124)>>>
+ASM|5000|0|ERRORLINE=|None|None|None|None
+ASM|5010|0|ERRORLINE=|None|None|None|None
+ASM|5015|3|LINE=Located 3 voting disk(s)|None|None|None|None
+ASM|5020|0|ERRORLINE=|None|None|None|None
+ASM|5030|0|ERRORLINE=|None|None|None|None
```

### 3.3 Adjusting Thresholds via Rules

All thresholds are managed through a single WATO rule set:

**Setup → Service monitoring rules → Oracle RAC Services Computer Metrics**

Each metric has three independently configurable parameters:

| Parameter | Description |
|-----------|-------------|
| **Enabled** | Toggle the metric on or off. Disabled metrics produce no service and no alert. |
| **Warning** | Threshold value that triggers a WARNING state. Accepts a number or `NaN` (disabled). |
| **Critical** | Threshold value that triggers a CRITICAL state. Accepts a number or `NaN` (disabled). |
| **Threshold type** | Read-only display: `MAX` means alert when value *exceeds* the threshold; `MIN` means alert when value *falls below* it. |

Default thresholds:

| Metric | Type | Warning | Critical | Enabled |
|--------|------|---------|----------|---------|
| m5000 — CRS Failures | MAX | `0.9` | `NaN` | Yes |
| m5010 — Voting Disk Match | MAX | `0.9` | `NaN` | **No** |
| m5015 — Voting Disk Count | MIN | `2` | `1` | Yes |
| m5020 — CRS Resource Status | MAX | `0.9` | `NaN` | Yes |
| m5030 — OCR Integrity | MAX | `0.9` | `NaN` | Yes |

For binary metrics (m5000, m5010, m5020, m5030) the value is either `0`
(healthy) or `1` (problem). A warning threshold of `0.9` means any value ≥ 1
triggers WARNING — effectively "alert on any problem." Setting the critical
threshold to `0.9` as well upgrades the alert directly to CRITICAL.

Rules follow standard Checkmk precedence: more specific rules (by host/folder)
override less specific ones.

### 3.4 How the Bakery Works

The bakery plugin is invoked by the Agent Bakery when building agent packages.
Its behavior:

- It receives the rule configuration (`conf['enabled']`).
- If **enabled**, it includes `oracle_rac_services.pl` in the baked agent
  package for **Linux** and **AIX** targets.
- If **disabled** (no matching rule, or rule set to disabled), the Perl script
  is not included and will not run on target hosts.
- **Windows** is not supported by the bakery plugin.

The bakery does **not** modify the content of `oracle_rac_services.pl`. Any
customisation (e.g. `$EXPECTED_VOTING_DISKS`) must be made to the source file
in `local/share/check_mk/agents/plugins/` before baking, or applied manually
after deployment.

---

## 4. Agent Metric Reference

All metrics are emitted in the agent section `<<<oracle_rac_services:sep(124)>>>`
using a pipe (`|`) separator. Output line format:

```
SID | MetricNumber | Value | Option1 | Option2 | Option3 | Option4 | Option5
```

The check interval for all metrics is **15 minutes**.

---

### m5000 — Oracle RAC CRS Failures

| | |
|-|-|
| Source | `crsctl check crs` |
| Value | Binary — `0` = healthy, `1` = failure detected |
| Threshold type | MAX |
| Default warning | `0.9` — triggers on any failure (value ≥ 1) |
| Default critical | `NaN` — disabled |
| Enabled by default | Yes |

Scans `crsctl check crs` output for the keywords `Cannot` or `Failure`. If
found, value = `1` and the matching line(s) are reported in
`OPTION1=ERRORLINE=<text>`.

**Alert message:** `At least one CRS Failure found in: '<ERRORLINE>'.`

---

### m5010 — Oracle RAC CRS Voting Disk Match

| | |
|-|-|
| Source | `crsctl query css votedisk` |
| Value | Binary — `0` = expected count confirmed, `1` = mismatch |
| Threshold type | MAX |
| Default warning | `0.9` |
| Default critical | `NaN` |
| Enabled by default | **No** |

Checks whether the output contains `Located <N> voting disk` where `<N>` equals
`$EXPECTED_VOTING_DISKS` (default `3`). Enable this metric and adjust
`$EXPECTED_VOTING_DISKS` in the Perl script if you want strict count validation
alongside m5015.

**Alert message:** `Issue for at least one CRS Voting Disk found in: '<ERRORLINE>'.`

---

### m5015 — Oracle RAC Voting Disks Count

| | |
|-|-|
| Source | `crsctl query css votedisk` |
| Value | Integer — actual number of voting disks found; `-1` if command failed |
| Threshold type | MIN |
| Default warning | `2` — triggers when fewer than 2 disks are found |
| Default critical | `1` — triggers when fewer than 1 disk is found |
| Enabled by default | Yes |
| Performance counter | `rac_voting_disk_count` |

Reports the **actual count** of located voting disks rather than a pass/fail
comparison. A value of `-1` means the `Located N voting disk` line was not
present in the command output and immediately breaches the critical threshold.

**Alert message:** `Only <MONVALUE> voting disk(s) located. Expected at least <THRESHOLD>. Details: '<LINE>'.`

---

### m5020 — Oracle RAC CRS Resource Status

| | |
|-|-|
| Source | `crsctl stat res -w '(TARGET = ONLINE) AND (STATE != ONLINE)' -v` |
| Value | Integer — count of resources targeted ONLINE but not ONLINE; `0` = all healthy |
| Threshold type | MAX |
| Default warning | `0.9` — triggers on any offline resource |
| Default critical | `NaN` |
| Enabled by default | Yes |
| Performance counter | `rac_crs_status` |

Each resource that is targeted ONLINE but is not currently ONLINE increments
the counter by one. The names, target servers, and states of affected resources
are concatenated in `OPTION1=ERRORLINE=<text>`.

**Alert message:** `For at least one CRS Resource issue were found in: '<ERRORLINE>'.`

---

### m5030 — Oracle RAC OCR Integrity

| | |
|-|-|
| Source | `ocrcheck` |
| Value | Binary — `0` = both checks passed, `1` = one or more checks failed |
| Threshold type | MAX |
| Default warning | `0.9` |
| Default critical | `NaN` |
| Enabled by default | Yes |

Verifies that `ocrcheck` output contains both:
- `Device/File integrity check succeeded`
- `Cluster registry integrity check succeeded`

If either line is absent, value = `1` and `OPTION1` lists the missing
check name(s).

**Alert message:** `The Oracle Cluster Registration Utility (ocrcheck) returned error: '<ERRORLINE>'.`

---

## 5. Troubleshooting

### Agent-side issues

#### Section header present but no data rows

The plugin ran but found no Grid Home. Investigate with:

```bash
# Inspect oratab
cat /etc/oratab | grep -v '^#' | grep -v '^$'

# Locate crsctl manually
find /u01 /app /oracle -name crsctl 2>/dev/null
```

If the Grid Home cannot be discovered automatically, set `$GRID_HOME` in the
Checkmk agent environment:

```bash
# Add to /etc/check_mk/check_mk_agent.conf or equivalent
GRID_HOME=/u01/app/19.0.0/grid
export GRID_HOME
```

#### `oracle_rac_services` section missing entirely

The plugin is not running. Verify:

```bash
ls -l /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl
perl -c /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl
```

Ensure the file exists and has execute permissions (`chmod 755`). Run the
plugin directly to see any errors:

```bash
sudo perl /usr/lib/check_mk_agent/plugins/oracle_rac_services.pl
```

#### Permission denied running `crsctl` or `ocrcheck`

These binaries may require specific group membership. Verify:

```bash
ls -l $GRID_HOME/bin/crsctl $GRID_HOME/bin/ocrcheck
sudo -u <agent-user> $GRID_HOME/bin/crsctl check crs
```

Add the agent user to `oinstall` or `asmadmin` as required by your Oracle
installation.

#### Output contains `crsctl command not available`

The plugin resolved a Grid Home from oratab or environment but the binary does
not exist at that path. Confirm that `$GRID_HOME/bin/crsctl` exists:

```bash
test -x "$GRID_HOME/bin/crsctl" && echo "OK" || echo "MISSING"
```

Correct the oratab entry or the `$GRID_HOME` environment variable.

---

### Server-side issues

#### Service shows UNKNOWN — "No data received for metric `<metric>`"

The agent section contained no data row for the metric on the last check cycle.
Common causes:

- The agent plugin is no longer running (see agent-side steps above).
- The metric was disabled in the ruleset after service creation. Re-enable it
  or remove the service manually.
- After a plugin update or re-deployment, a full re-discovery may be needed:
  **Setup → Hosts → <hostname> → Run service discovery**.

#### Services not discovered after MKP import

Trigger a full service re-discovery on the affected hosts:

```bash
# As site user
cmk -II <hostname>
cmk -R
```

Or via the web interface: **Setup → Hosts → Run service discovery**.

#### Thresholds not applied

Rules are evaluated in Checkmk's standard precedence order (most specific
folder first). Use **Setup → Service monitoring rules → Oracle RAC Services
Computer Metrics → Analyse** to see which rule is effective for a given host
and service.

Also confirm that the metric is marked **enabled** in the active rule. A
disabled metric always evaluates to OK regardless of the measured value.

#### m5010 always WARNING despite healthy voting disks

m5010 is **disabled by default**. If it has been enabled but
`$EXPECTED_VOTING_DISKS` in the Perl script does not match your cluster's
actual disk count, the metric will always report a mismatch. Options:

- Correct `$EXPECTED_VOTING_DISKS` in `oracle_rac_services.pl` and redeploy.
- Disable m5010 in the WATO rule and rely on m5015 (count-based) instead.

#### Performance graphs missing for m5015 or m5020

Only m5015 (`rac_voting_disk_count`) and m5020 (`rac_crs_status`) emit
performance counters. The other metrics are binary and produce no graph.
Verify that the service is in OK or WARN state — UNKNOWN state suppresses
metric storage.
