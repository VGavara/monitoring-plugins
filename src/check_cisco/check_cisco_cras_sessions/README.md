# check_cisco_cras_sessions

This plugin checks the number of active sessions on a Cisco Remote Access Server supporting the ciscoRemoteAccessMonitorMIB MIB.

Different types of sessions can be checked depending on the checked host: Email, IPSec, LAN to LAN, Load Balancing, SSL VPN clients and/or Web VPNs.

The thresholds can be defined as absolute values or as percent over the maximum sessions supported by the device.

# Usage

    check_cisco_cras_sessions -H <hostname> [-w <warning threshold>] [-c <critical threshold>]
        [-C <SNMP Community>]  [E <SNMP Version>] [-P <SNMP port>]
        [-s <session type> -S <session type> ...] [--percent]} [--total]
        [-V <version>]

Type `check_cisco_cras_sessions --help` for getting more info.

# Examples

## check_cisco_cras_sessions -H 192.168.0.12
Checks the number of sessions in a host with address 192.168.0.12 using SNMP protocol version 1 and 'public' as community. Plugin returns always OK.

## check_cisco_cras_sessions -H 192.168.0.12 -w 30 -c 50
Similar to the previous example but returning WARNING if the number of sessions of any kind is higher than 30 and CRITICAL if it's higher than 50.

## check_cisco_cras_sessions -H 192.168.0.12 -s email -s ipsec -w 30 -c 50
Similar to the previous example but just checking the Email (-s email) and IPSec (-s ipsec) sessions.

## check_cisco_cras_sessions -H 192.168.0.12 -s email -s ipsec -T -w 30 -c 50
Similar to the previous example but totalizing (-T) the sessions, ie, returning WARNING if the sum of email and ipsec sessions is higher than 30 and CRITICAL if it's higher than 50.

## check_cisco_cras_sessions -H 192.168.0.12 -p -w 30 -c 50
Sessions of any kind are checked and their total is managed as percent (-p) over the device max supportable sessions. Thresholds and results are considered as percent.