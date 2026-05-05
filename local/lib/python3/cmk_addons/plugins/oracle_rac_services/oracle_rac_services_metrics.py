#!/usr/bin/env python3

METRIC_DEF = {
    'm5000': {'enabled': True,  'interval': '15m', 'type': 'MAX', 'critical': 'NaN', 'warning': '0.9', 'name': 'Oracle RAC CRS Failures',       'alert': "At least one CRS Failure found in: '<ERRORLINE>'.",                                                    'counter': '',                    },
    'm5010': {'enabled': False, 'interval': '15m', 'type': 'MAX', 'critical': 'NaN', 'warning': '0.9', 'name': 'Oracle RAC CRS Voting Disk',      'alert': "Issue for at least one CRS Voting Disk found in: '<ERRORLINE>'.",                                      'counter': '',                    },
    'm5015': {'enabled': True,  'interval': '15m', 'type': 'MIN', 'critical': '1',   'warning': '2',   'name': 'Oracle RAC Voting Disks Count',   'alert': "Only <MONVALUE> voting disk(s) located. Expected at least <THRESHOLD>. Details: '<LINE>'.",             'counter': 'rac_voting_disk_count', },
    'm5020': {'enabled': True,  'interval': '15m', 'type': 'MAX', 'critical': 'NaN', 'warning': '0.9', 'name': 'Oracle RAC CRS Status',           'alert': "For at least one CRS Resource issue were found in: '<ERRORLINE>'.",                                     'counter': 'rac_crs_status',      },
    'm5030': {'enabled': True,  'interval': '15m', 'type': 'MAX', 'critical': 'NaN', 'warning': '0.9', 'name': 'Oracle RAC OCR Integrity',        'alert': "The Oracle Cluster Registration Utility (ocrcheck) returned error: '<ERRORLINE>'.",                     'counter': '',                    },
}
