# check_ups_inputs

Checks the input levels (frequency, voltage, current and/or power) on a RFC1628 (UPS-MIB) SNMP compliant device.

# Usage

    check_up_inputs -H <hostname>
        -w [<frequency range>],[<voltage range>],[<current range>],[<power range>]
        -c [<frequency range>],[<voltage range>],[<current range>],[<power range>]
        [-i <input list>]
        [-C <SNMP Community>] [-E <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]
        [-V <version>]

Type Type `check_ups_inputs --help` to get more info.

# Examples

## check_ups_inputs -H 192.168.0.101 -i 1,2,3 -w ,210:240,,\~:3000 -c ,200:250,,\~:4000

Checks the 1 to 3 input levels of a UPS-MIB SNMP compliant device with IP address 192.168.0.101.

Plugin returns WARNING if voltage is out of  210 to 240 volts range or the output power exceeds 3000W, and returns CRITICAL if voltage is out of 200 to 250 volts range or power exceeds 4000W.
