# check_cisco_fru_ps

This plugin checks power on a CISCO-ENTITY-FRU-CONTROL-MIB compliant device (e.g. Cisco MDS 9000 series). It compares the listed power states with a power state identifier list defined for each WARNING and CRITICAL state. If any state of the powers is in any list, plugin returns the related state and a list with the powers involved or OK if not.

Plugin can be run in test mode for both checking if device supports this kind of check and showing a present power list with id,status and description data.


# STATUS IDENTIFIERS

The status ids of a power (extracted from MIB) are:

- 1: offEnvOther
- 2: on
- 3: offAdmin
- 4: offDenied
- 5: offEnvPower
- 6: offEnvTemp
- 7: offEnvFan
- 8: failed
- 9: onButFanFail
- 10: offCooling
- 11: offConnectorRating
- 12: onButInlinePowerFail


# USAGE EXAMPLES

## check_cisco_fru_ps -H 192.168.0.13

Test Mode that checks the compatibility of the plugin on a host with address 192.168.0.13 using SNMP protocol version 1 and 'public' as community.

Plugin returns OK if it is a CISCO-ENTITY-FRU-CONTROL-MIB compliant device and can recover power supply data. Also, a list of all power supplies with id, status and description is returned. If it is not compatible returns UNKNOWN.

## check_cisco_fru_ps -H 192.168.0.13 -e 120,121 -w 9,12 -c 8

Checks, on a CISCO-ENTITY-FRU-CONTROL-MIB compliant device with IP address  192.168.0.13, if any of the psu passed through their id with the -e argument are in any of the states passed in -w and -c argument. 	

It returns CRITICAL if any power (120 or 121 power id) has a state with id 8, WARNING if any power has a state with id 9 or 12, and in other case returns OK.
					
					
# HISTORY

## v.0.3b
Improved compatibility with Cisco Nexus devices setting SNMP max message size to 5 kbytes (many thanks to Helge Waastad, Fabien Dedenon and Tobias Wigand for their feedback)
