# check_cisco_cpu
Checks the CPU load (in percent) on a CISCO-PROCESS-MIB or OLD-CISCO-CPU-MIB SNMP compliant device.

# Usage
    check_cisco_cpu -H <hostname> -r <Resource id> [-i <interval>] [-d] -w <warning value> -c <critical value>
        [-C <SNMP Community>] [-e <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]
        [-U <SNMP authentication user> -a <SNMP authentication protocol> -A <SNMP authentication pass phrase>
        [-x <SNMP privacy protocol> -X <SNMP privacy pass phrase>] ]

Type `check_cisco_cpu --help` for getting more info.

# Examples
## check_cisco_cpu -H 192.168.0.1 -r 1 -i 1m -w 80 -c 95
Checks the last minute (-i 1m) CPU load on a CPU module with id 1 (-r 1) in a CISCO-PROCESS-MIB SNMP compliant device using 'public' as default SNPM community string and default SNMP port 161.

Plugin returns WARNING if last minute CPU load is above 80%, or CRITICAL if last minute CPU load is above 95%. 

## check_cisco_cpu -H 192.168.0.1 -E 3 -U admin -a MD5 -A authpass -x DES -X encryptpass -i 5m -w 85 -c 95
Checks the last five minutes (-i 1m) CPU load on a OLD-CISCO-CPU-MIB SNMP compliant device using SNMP v3 with default port 161, authentication user 'admin', authentication protocol 'MD5', authenticacion pass phrase 'authpass', encryption protocol DES and encryption pass phrase 'encryptpass'.

Plugin returns WARNING if last five minutes CPU load is above 85%,or CRITICAL if last five minutes CPU load is above 95%.