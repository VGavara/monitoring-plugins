# check_ups_mode

Checks the working mode (online/bypass/offline with batt. normal, low or depleted) of a RFC1628 (UPS-MIB) SNMP compliant device, returning autonomy values as performance data.

# Usage

    check_ups_mode -H <hostname>
        -w [<mode id>, <mode id>,...]
        -c [<mode id>, <mode id>, ...]
        [-l <battery low level threshold> [-d <battery depleted level threshold>]
        [-C <SNMP Community>] [-E <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]
        [-V <version>]

Type `check_ups_mode --help` to get more info.

# Examples

## check_ups_mode -H 192.168.0.1 -w 2,5 -c 3,4
It checks the working mode of a UPS-MIB SNMP compliant device with IP address 192.168.0.1, SNMP protocol 2 and real community 'public'.

The plugin returns WARNING if it is working offline and its battery level is NOT low (Offline=2) or it is in bypass mode (bypass=5), or it returns CRITICAL if it is working offline and its battery level is low (Offline battery low = 3) or battery is depleted (Offline battery depleted = 4).