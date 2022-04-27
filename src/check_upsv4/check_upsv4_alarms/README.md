# check_upsv4_alarms

This plugin checks the active UPS alarms of a MIB UPSv4 (DeltaUPS-MIB) SNMP compliant device.

# Usage

    check_upsv4_alarms -H <hostname> -w <warning list> -c <critical list>
        [-C <SNMP Community>]  [E <SNMP Version>] [-P <SNMP port>]
        [-V <version>]

Type `check_upsv4_alarms --help` for getting more info.

# Examples
## check_upsv4_alarms -H 192.168.0.1 -w 1..5,10 -c 5..10
Checks in a MIB UPSv4 SNMP compliant device with IP address 192.168.0.1, if any of the alarms passed in the -w and -c arguments are active.

It returns WARNING if one or more alarms from 1 to 5 or 10 are active, or CRITICAL if one or more alarms from 5 to 10 are active. If not active alarms are found, or their id is greater than 10 it returns OK.

If the state is WARNING or CRITICAL it returns a list of active alarm id's and descriptions.