# check_ups_outputs

Checks the output levels (voltage, current, power and/or load percent) on a RFC1628 (UPS-MIB) SNMP compliant device.

# Usage

    check_up_outputs -H <hostname>
        -w [<voltage range>],[<current range>],[<power range>],[<load range>]
        -c [<voltage range>],[<current range>],[<power range>],[<load range>]
        [-o <output list>]
        [-p <UPS power rating>]
        [-C <SNMP Community>] [-E <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]
        [-V <version>]
        [-f]

Type Type `check_ups_outputs --help` to get more info.

# Examples

## check_ups_outputs -H 192.168.0.101 -o 1,2,3 -w 210:240,,,\~:70 -c 200:250,,,\~:90

Checks the 1 to 3 output levels of a UPS-MIB SNMP compliant device with IP address 192.168.0.101.

Plugin returns WARNING if voltage is out of  210 to 240 volts range or the output load exceeds 70%, and returns CRITICAL if voltage is out of 200 to 250 volts range or load exceeds 90%.