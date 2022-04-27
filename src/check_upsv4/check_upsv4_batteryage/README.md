# check_ups_bateryage

Checks the condition and age of the batteries on a MIB UPSv4 (DeltaUPS-MIB) DEFINITIONS SNMP compliant device.

# Usage

    check_upsv4_batteryage -H <hostname>
        -w <warning days>
        -c <critical days>
        [-C <SNMP Community>] [-E <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]
        [-V <version>]

Type `check_ups_bateryage --help` for getting more info.

# Examples
## check_upsv4_batteryage -H 192.168.0.101 -w 5 -c 10
Checks the condition and age of the battery on a MIB UPSv4 SNMP compliant device with IP address 192.168.0.101.

Plugin returns WARNING if the condition of the battery is 'weak' or the battery expiration date is exceeded by a period of 5 to 10 days. It returns CRITICAL if the condition of the battery is 'replace' or the battery expiration date is exceeded by more than 10 days.

In other case (condition of the battery 'good' and battery expiration date is exceeded for less than five days, it returns OK.