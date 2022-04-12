# check_cisco_fru_module

Checks the modules status on a CISCO-ENTITY-FRU-CONTROL-MIB compliant device (Cisco Catalyst switches, routers, ASA, MDS 9000 series, ...).

It compares the device reported modules states with a module state identifier list defined for each WARNING and CRITICAL threshold. If any device module state is found on a list, plugin returns the related state and a list with the modules involved or OK if not.

By using it with only host argument, you can use this plugin to test both if SNMP access is enabled to your device, if it supports CISCO-ENTITY-FRU-CONTROL-MIB and for getting module identifiers, useful for defining argument --ids list items.


# MODULE IDENTIFIERS

Since module identifiers are related to each device, mantaining a module list is all but practical. Instead of setting them in a static way (ie, in this readme file) you can run the plugin in test mode in order to get a module list present in your device.

Usage example section (read below) includes an example about running the plugin in test mode.


# STATUS IDENTIFIERS

The status ids of a module (extracted from MIB) are:

- 1: unknown
- 2: ok
- 3: disabled
- 4: okButDiagFailed
- 5: boot
- 6: selfTest
- 7: failed
- 8: missing
- 9: mismatchWithParent
- 10: mismatchConfig
- 11: diagFailed
- 12: dormant
- 13: outOfServiceAdmin
- 14: outOfServiceEnvTemp
- 15: poweredDown
- 16: poweredUp
- 17: powerDenied
- 18: powerCycled
- 19: okButPowerOverWarning
- 20: okButPowerOverCritical
- 21: syncInProgress
- 22: upgrading
- 23: okButAuthFailed


# USAGE 

    check_cisco_fru_module -H <hostname> [-e <module id list>] [-w <warning list> -c <critical list>]
        [-C <SNMP Community>]  [-E <SNMP Version>] [-P <SNMP port>]
        [-V <version>]

Type `check_cisco_fru_module --help` for getting more info.


# EXAMPLES

## check_cisco_fru_module -H 192.168.0.12

Test Mode that checks the compatibility of the plugin on a host with address 192.168.0.12 using SNMP protocol version 1 and 'public' as community.

Plugin returns OK if it is a CISCO-ENTITY-FRU-CONTROL-MIB compliant device and can recover modules data. Also, IT PRINTS a list of all modules with id, status and description is returned. If it is not compatible returns UNKNOWN.

## check_cisco_fru_module -H 192.168.0.12 -e 275,276 -w 4,19,23 -c 7,8,20

Checks, on a CISCO-ENTITY-FRU-CONTROL-MIB compliant device with IP address  192.168.0.12, if any of the modules passed through their id with the -e argument are in any of the states passed in -w and -c argument.

It returns CRITICAL if any of the modules identified as 275 or 276 has an state with id 7 (failed), 8 (missing) or 20 (okButPowerOverCritical), WARNING if any module has an state with id 4 (okButDiagFailed) 19 (okButPowerOverWarning) or 23 (okButAuthFailed) and OK in all other cases.


# HISTORY

## v.0.3b
Improved compatibility with Cisco Nexus devices setting SNMP max message size to 5 kbytes (many thanks to Helge Waastad, Fabien Dedenon and Tobias Wigand for their feedback)
