# check_upsv4_inputs

Checks the input levels (frequency, voltage and/or current) on a MIB UPSv4 (DeltaUPS-MIB) DEFINITIONS SNMP compliant device.

# Usage
    check_upsv4_inputs -H <hostname>
        -w [<frequency range>],[<voltage range>],[<current range>]
        -c [<frequency range>],[<voltage range>],[<current range>]
        [-C <SNMP Community>] [-E <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]
        [-V <version>]

Type `check_upsv4_inputs --help` for getting more info.

# Examples
## check_upsv4_inputs -H 192.168.0.101 -w ,210:240, -c ,200:250,
Checks the input levels of a DeltaUPS-MIB SNMP compliant device with IP address 192.168.0.101.

Plugin returns WARNING if voltage is out of  210 to 240 volts range, and returns CRITICAL if voltage is out of 200 to 250 volts range. In other case it returns OK.

Ranges are defined as [@]start:end

### Notes
1. start <= end
2. start and ':' is not required if start=0
3. If range is of format 'start:' and end is not specified, assume end is infinity
4. To specify negative infinity, use '~'
5. Alert is raised if metric is outside start and end range (inclusive of endpoints)
6. If range starts with '\@', then alert if inside this range (inclusive of endpoints)

### Range examples
* `10` Generate alert if x < 0 or > 10, (outside the range of {0 .. 10}) 
* `10:` Generate alert if x < 10, (outside {10 .. 8}) 
* `~:10` Generate alert if x > 10, (outside the range of {-8 .. 10}) 
* `10:20` Generate alert if x < 10 or > 20, (outside the range of {10 .. 20}) 
* `@10:20` Generate alert if x = 10 and = 20, (inside the range of {10 .. 20}) 

Note that the symbol '~' in bash is equivalent to the global variable  \$HOME. Make sure to escape this symbol with `\` when type it in the command line.