#!/usr/bin/env python3

from collections.abc import Mapping

# Import debug objects, remember the path changed between 2.3.0 and 2.4.0
try:
    from cmk.ccc import debug
except ImportError:
    from cmk.utils import debug

from cmk.agent_based.v2 import (
    AgentSection,
    CheckPlugin,
    CheckResult,
    DiscoveryResult,
    StringTable,
)

from cmk_addons.plugins.oracle_rac_services.oracle_rac_services_metrics import METRIC_DEF

from cmk_addons.plugins.oracle_rac_services.agent_based.oracle_rac_services_lib import (
    MetricData,
    parse_oracle,
    discover_oracle,
    check_oracle,
    cluster_check_oracle,
)

agent_section_oracle_rac_services = AgentSection(
    name = "oracle_rac_services",
    parse_function = parse_oracle,
)

_default_parameters = { k: {m: v.get(m, '') for m in ('enabled', 'type', 'critical', 'warning')} for k,v in METRIC_DEF.items() }

# Below is generated code

def discover_oracle_m5000(params, section: Mapping[str, MetricData]) -> DiscoveryResult:
    yield from discover_oracle(params, section, 'm5000')

def check_oracle_m5000(params, section: Mapping[str, MetricData]) -> CheckResult:
    yield from check_oracle(params, section, 'm5000', METRIC_DEF)

def cluster_check_oracle_m5000(params, section) -> CheckResult:
    yield from cluster_check_oracle(params, section, 'm5000', 'WorstOf', METRIC_DEF)

check_plugin_oracle_m5000 = CheckPlugin(
    name = 'oracle_m5000',
    sections = ['oracle_rac_services'],
    service_name = 'Oracle RAC CRS Failures',
    discovery_function = discover_oracle_m5000,
    discovery_default_parameters = _default_parameters,
    discovery_ruleset_name = 'oracle_rac_services_parameters',
    check_function = check_oracle_m5000,
    check_default_parameters = _default_parameters,
    check_ruleset_name = 'oracle_rac_services_parameters',
    cluster_check_function = cluster_check_oracle_m5000,
)

def discover_oracle_m5010(params, section: Mapping[str, MetricData]) -> DiscoveryResult:
    yield from discover_oracle(params, section, 'm5010')

def check_oracle_m5010(params, section: Mapping[str, MetricData]) -> CheckResult:
    yield from check_oracle(params, section, 'm5010', METRIC_DEF)

def cluster_check_oracle_m5010(params, section) -> CheckResult:
    yield from cluster_check_oracle(params, section, 'm5010', 'WorstOf', METRIC_DEF)

check_plugin_oracle_m5010 = CheckPlugin(
    name = 'oracle_m5010',
    sections = ['oracle_rac_services'],
    service_name = 'Oracle RAC CRS Voting Disk',
    discovery_function = discover_oracle_m5010,
    discovery_default_parameters = _default_parameters,
    discovery_ruleset_name = 'oracle_rac_services_parameters',
    check_function = check_oracle_m5010,
    check_default_parameters = _default_parameters,
    check_ruleset_name = 'oracle_rac_services_parameters',
    cluster_check_function = cluster_check_oracle_m5010,
)

def discover_oracle_m5015(params, section: Mapping[str, MetricData]) -> DiscoveryResult:
    yield from discover_oracle(params, section, 'm5015')

def check_oracle_m5015(params, section: Mapping[str, MetricData]) -> CheckResult:
    yield from check_oracle(params, section, 'm5015', METRIC_DEF)

def cluster_check_oracle_m5015(params, section) -> CheckResult:
    yield from cluster_check_oracle(params, section, 'm5015', 'WorstOf', METRIC_DEF)

check_plugin_oracle_m5015 = CheckPlugin(
    name = 'oracle_m5015',
    sections = ['oracle_rac_services'],
    service_name = 'Oracle RAC Voting Disks Count',
    discovery_function = discover_oracle_m5015,
    discovery_default_parameters = _default_parameters,
    discovery_ruleset_name = 'oracle_rac_services_parameters',
    check_function = check_oracle_m5015,
    check_default_parameters = _default_parameters,
    check_ruleset_name = 'oracle_rac_services_parameters',
    cluster_check_function = cluster_check_oracle_m5015,
)

def discover_oracle_m5020(params, section: Mapping[str, MetricData]) -> DiscoveryResult:
    yield from discover_oracle(params, section, 'm5020')

def check_oracle_m5020(params, section: Mapping[str, MetricData]) -> CheckResult:
    yield from check_oracle(params, section, 'm5020', METRIC_DEF)

def cluster_check_oracle_m5020(params, section) -> CheckResult:
    yield from cluster_check_oracle(params, section, 'm5020', 'WorstOf', METRIC_DEF)

check_plugin_oracle_m5020 = CheckPlugin(
    name = 'oracle_m5020',
    sections = ['oracle_rac_services'],
    service_name = 'Oracle RAC CRS Status',
    discovery_function = discover_oracle_m5020,
    discovery_default_parameters = _default_parameters,
    discovery_ruleset_name = 'oracle_rac_services_parameters',
    check_function = check_oracle_m5020,
    check_default_parameters = _default_parameters,
    check_ruleset_name = 'oracle_rac_services_parameters',
    cluster_check_function = cluster_check_oracle_m5020,
)

def discover_oracle_m5030(params, section: Mapping[str, MetricData]) -> DiscoveryResult:
    yield from discover_oracle(params, section, 'm5030')

def check_oracle_m5030(params, section: Mapping[str, MetricData]) -> CheckResult:
    yield from check_oracle(params, section, 'm5030', METRIC_DEF)

def cluster_check_oracle_m5030(params, section) -> CheckResult:
    yield from cluster_check_oracle(params, section, 'm5030', 'WorstOf', METRIC_DEF)

check_plugin_oracle_m5030 = CheckPlugin(
    name = 'oracle_m5030',
    sections = ['oracle_rac_services'],
    service_name = 'Oracle RAC OCR Integrity',
    discovery_function = discover_oracle_m5030,
    discovery_default_parameters = _default_parameters,
    discovery_ruleset_name = 'oracle_rac_services_parameters',
    check_function = check_oracle_m5030,
    check_default_parameters = _default_parameters,
    check_ruleset_name = 'oracle_rac_services_parameters',
    cluster_check_function = cluster_check_oracle_m5030,
)
