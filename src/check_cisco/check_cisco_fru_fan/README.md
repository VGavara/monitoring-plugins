# check_cisco_fru_fan

This plugin checks fans in a CISCO-ENTITY-FRU-CONTROL-MIB compliant device (e.g. Cisco MDS 9000 series). It compares the listed fan states with a fan state identifier list defined for each WARNING and CRITICAL state. If any state of the fans is in any list, plugin returns the related state and a list with the fans involved or OK if not.

Plugin can be run in test mode for both checking if device supports this kind of check and showing a present fan list with id, status and description data.

# STATUS IDENTIFIERS

The status ids of a fan (extracted from MIB) are:

1. unknown
2. up
3. down
4. warning


# USAGE

    check_cisco_fru_fan -H <hostname> [-e <fan id list> -w <warning list>] -c <critical list>]
        [-C <SNMP Community>]  [E <SNMP Version>] [-P <SNMP port>]
        [-V <version>]

Type `check_cisco_fru_fan --help` for getting more info.

# EXAMPLES

## check_cisco_fru_fan -H 192.168.0.12

Test Mode that checks the compatibility of the plugin on a host with address 192.168.0.12 using SNMP protocol version 1 and 'public' as community.

Plugin returns OK if it is a CISCO-ENTITY-FRU-CONTROL-MIB compliant device and can recover fan data. Also, a list of all fans with id, status and description is returned. If it is not compatible returns UNKNOWN

## check_cisco_fru_fan -H 192.168.0.12 -e 332,334 -w 4 -c 3

Checks, on a CISCO-ENTITY-FRU-CONTROL-MIB compliant device with IP address  192.168.0.12, if any of the fans passed through their id with the -e argument are in any of the states passed in -w and -c argument.

It returns CRITICAL if any fan (332 or 334 id fan) has a state with id 3, WARNING if any fan has a state with id 4, and in other case returns OK.


# HISTORY

## v.0.3b
Improved compatibility with Cisco Nexus devices setting SNMP max message size to 5 kbytes (many thanks to Helge Waastad, Fabien Dedenon and Tobias Wigand for their feedback)
