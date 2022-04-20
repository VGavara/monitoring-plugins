# check_ups_battery_values

Checks the battery values (voltage, current and temperature) on a RFC1628 (UPS-MIB) SNMP compliant device.

# Usage

    check_ups_battery_values -H <hostname>
        -w [<voltage range>],[<current range>],[<temperature range>]
        -c [<voltage range>],[<current range>],[<temperature range>]
        [-C <SNMP Community>] [-e <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]
        [-V <version>]

Type Type `check_ups_battery_values --help` to get more info.

# Examples

## check_ups_battery_values -H 192.168.0.101 -w 210:240,,,\~:40 -c 200:250,,\~:50

Checks the voltage, current and temperature battery value levels of a UPS-MIB SNMP compliant device with IP address 192.168.0.101.

The plugin returns WARNING if voltage is out of  210 to 240 volts range or the temperature battery value exceeds 40 Celsius degrees, and returns CRITICAL if voltage is out of 200 to 250 volts range or temperature exceeds 50 Celsius degrees.