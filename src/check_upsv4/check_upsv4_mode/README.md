# check_upsv4_mode

Checks the working mode (online/bypass/offline with battery normal, low or depleted) in a MIB UPSv4 (DeltaUPS-MIB) SNMP compliant device returning autonomy values as performance data.

# Usage
    check_upsv4_mode -H <hostname>
        -w [<mode id>, <mode id>,...]
        -c [<mode id>, <mode id>, ...]
        [-l <battery low level threshold> [-d <battery depleted level threshold>]
        [-C <SNMP Community>] [-E <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]
        [-V <version>]

Type `check_upsv4_mode --help` for getting more info.

# Examples
## check_upsv4_mode -H 192.168.0.1 -w 2,5 -c 3,4
It checks the working mode of a UPSv4-MIB SNMP compliant device with IP address 192.168.0.1, SNMP protocol 2 and real community 'public'.

The plugin returns WARNING if it is working offline and its battery level is NOT low (Offline=2) or it is in bypass mode (bypass=5). It returns CRITICAL if it is working offline and its level is low (Offline battery low = 3) or the battery is depleted (Offline battery depleted = 4).