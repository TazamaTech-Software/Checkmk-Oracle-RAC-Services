#!/usr/bin/env python3

from cmk.rulesets.v1 import Title, Help, Label
from cmk.rulesets.v1.form_specs import (
    BooleanChoice,
    DefaultValue,
    DictElement,
    Dictionary,
)

from cmk.rulesets.v1.rule_specs import (
    AgentConfig,
    CheckParameters,
    HostAndItemCondition,
    Topic,
)

from cmk_addons.plugins.oracle_rac_services.oracle_rac_services_metrics import METRIC_DEF
from cmk_addons.plugins.oracle_rac_services.rulesets.ruleset_oracle_rac_services_lib import metric_dict_elements


def _agent_parameter_form():
    return Dictionary(
        title=Title("Oracle RAC Services Agent Plugin"),
        help_text=Help("Deploy the Oracle RAC Services agent plugin to monitored hosts."),
        elements={
            "enabled": DictElement(
                parameter_form=BooleanChoice(
                    label=Label("Enable Oracle RAC Services agent plugin"),
                    prefill=DefaultValue(True),
                ),
                required=True,
            ),
        },
    )


rule_spec_oracle_rac_services_agent = AgentConfig(
    name="oracle_rac_services",
    title=Title("Oracle RAC Services"),
    topic=Topic.DATABASES,
    parameter_form=_agent_parameter_form,
)


def _parameter_form():
    return Dictionary(
        title=Title("Oracle RAC Services Thresholds"),
        help_text=Help("Configure thresholds for specific Oracle RAC Services counters."),
        elements=metric_dict_elements(METRIC_DEF),
    )


rule_spec_oracle_rac_services = CheckParameters(
    name="oracle_rac_services_parameters",
    title=Title("Oracle RAC Services Metrics"),
    topic=Topic.DATABASES,
    parameter_form=_parameter_form,
    condition=HostAndItemCondition(item_title=Title("Oracle RAC Services Metrics")),
)
