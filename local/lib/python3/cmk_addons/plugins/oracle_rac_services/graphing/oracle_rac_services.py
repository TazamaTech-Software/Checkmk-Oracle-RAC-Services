#!/usr/bin/env python3

from cmk.graphing.v1 import Title
from cmk.graphing.v1.graphs import Graph, MinimalRange
from cmk.graphing.v1.metrics import Color, DecimalNotation, Metric, Unit
from cmk.graphing.v1.perfometers import Closed, FocusRange, Open, Perfometer

from cmk_addons.plugins.oracle_rac_services.oracle_rac_services_metrics import METRIC_DEF


metric_oracle_m5020 = Metric(
    name = METRIC_DEF['m5020']['counter'],
    title = Title("Oracle RAC Status"),
    unit = Unit(DecimalNotation("")),
    color = Color.LIGHT_BLUE,
)
perfometer_oracle_m5020 = Perfometer(
    name = METRIC_DEF['m5020']['counter'],
    focus_range = FocusRange(Open(0), Open(1)),
    segments = [ METRIC_DEF['m5020']['counter'] ],
)

metric_oracle_m5015 = Metric(
    name = METRIC_DEF['m5015']['counter'],
    title = Title("Oracle RAC Voting Disks Count"),
    unit = Unit(DecimalNotation("")),
    color = Color.LIGHT_BLUE,
)
perfometer_oracle_m5015 = Perfometer(
    name = METRIC_DEF['m5015']['counter'],
    focus_range = FocusRange(Closed(0), Open(3)),
    segments = [ METRIC_DEF['m5015']['counter'] ],
)
