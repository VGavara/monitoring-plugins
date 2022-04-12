# check_cisco_ce_alarms

Checks the alarms on a CISCO-CONTENT-ENGINE-MIB compliant device.

# Usage

    check_cisco_ce_alarms -H <hostname>
        [-C <SNMP Community>] [-e <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]
        [-w <alarm level list> -c <alarm level list>]
        [-V <version>]

Type `check_cisco_ce_alarms --help` for getting more info.

# Examples
## check_cisco_ce_alarms -H 192.168.0.4
If available, it displays info of the device with address 192.168.0.4 using SNMP protocol version 1 and 'public' as community (useful for checking plugin-device compatibility).

## check_cisco_ce_alarms -H 192.168.0.4 -w M,N -c C
Checks content engine alarms on host 192.168.0.4 using SNMP protocol version 1 and 'public' as community.

Plugin returns CRITICAL if there is any critical (-c C) active alarm and WARNING if there's any minor (-w N) or major (-w M) active alarm.