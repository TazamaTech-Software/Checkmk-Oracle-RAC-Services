#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Reference for details:
# https://docs.checkmk.com/latest/en/bakery_api.html
# ---------------------------------------------------------------------------

from pathlib import Path

from .bakery_api.v1 import (
    OS,
    Plugin,
    register,
    FileGenerator,
)

DEBUG = False  # Set to True to enable debug output

def get_oracle_rac_services_plugin_files(conf: dict) -> FileGenerator:
    if DEBUG: print(f"Generating Oracle RAC Services plugin files for configuration: {conf}")

    if conf.get('enabled', False):
        yield Plugin(
            base_os = OS.LINUX,
            source = Path("oracle_rac_services.pl"),
            target = Path("oracle_rac_services.pl"),
        )
        yield Plugin(
            base_os = OS.AIX,
            source = Path("oracle_rac_services.pl"),
            target = Path("oracle_rac_services.pl"),
        )

register.bakery_plugin(
    name = "oracle_rac_services",
    files_function = get_oracle_rac_services_plugin_files,
)
