# check_cisco_memory

Checks the used and fragmented memory on a CISCO_MEMORY_POOL_MIB SNMP compliant device.

# Usage

    check_cisco_memory -H <hostname> -p <memory pool id> -w <warning value> -c <critical value>
        [-C <SNMP Community>] [-e <SNMP Version>]
        [-u <SNMP security name>] [-a <SNMP authentication protocol> -A <SNMP authentication pass phrase>] [-x <SNMP privacy protocol> -X <SNMP privacy pass phrase>]
        [-P <SNMP port>] [-t <SNMP timeout>]
        [-V <version>]

Type `check_cisco_memory --help` for getting more info.

# Examples
## check_cisco_memory -H 192.168.0.1 -p 1 -w 80,60 -c 95,80
Checks the pool id 1 memory usage and fragmented memory flag on a CISCO_MEMORY_POOL_MIB compliant device using 'public' as community string and default port 161.

The plugin returns WARNING if memory usage is above 80% or fragmented memory is above 60%, or CRITICAL if memory usage is above 95% or fragmented memory is above 80%.