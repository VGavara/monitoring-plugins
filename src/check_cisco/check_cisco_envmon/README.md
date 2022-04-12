# check_cisco_envmon

Checks the enviroment sensors on a CISCO-ENVMON-MIB compliant device. The check is performed from a list of sensors by checking if their states are below a given status threshhold.

Depending on the device, the supported sensor types are:

- Voltage sensors
- Temperature sensors
- Fan sensors
- Power supply sensonrs

The plugin will trigger warning or critical alarms whenever a sensor status was above a given status threshold, being the supported states:

- 1: Normal
- 2: Warning
- 3: Critical
- 4: Shutdown
- 5: Not present
- 6: Not functioning

The plugin can be run in test mode in order to know the supported device sensors and their ids.

# Usage

	check_cisco_envmon -H <hostname>
		[-C <SNMP Community>] [-e <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]
		[-g <voltage id list>]
		[-T <temperature id list>]
		[-f <fan id list>]
		[-s <supply id list>]
		[-w <environment states id threshold list> -c <environment states id threshold list>]
		[-V <version>]

Type `check_cisco_envmon --help` for getting more info.

# Examples

## check_cisco_envmon -H 192.168.0.4
If available, displays info of the device with address 192.168.0.4 using SNMP protocol version 1 and 'public' as community (useful for checking compatibility and displaying environmental data).

## check_cisco_envmon -H 192.168.0.4 -w 2,6 -c 3,4
Checks all environmental sensors avaliable on a host with address 192.168.0.4 using SNMP protocol version 1 and 'public' as community.

Plugin returns CRITICAL if any sensor has a environmental state equal to 'critical' (3) or 'shutdown' (4), and WARNING if any sensor has a environmental state equal to 'warning' (2) or 'notFunctioning' (6). In other case it returns OK if check has been performed or UNKNOWN.

## check_cisco_envmon -H 192.168.0.4 -f all -s 1003 -w 2,6 -c 3,4
Checks all avaliable fans, and the power supply with id 1003 on a host with address 192.168.0.4 using SNMP protocol version 1 and 'public' as community.

Plugin returns CRITICAL if any checked sensor has a environmental state equal to 'critical' (3) or 'shutdown' (4), and WARNING if any checked sensor has a environmental state equal to 'warning' (2) or 'notFunctioning' (6). In other case it returns OK if check has been performed, or UNKNOWN if not.

Status values are defined in CISCO-ENVMON-MIB as: Normal(1), Warning(2), Critical(3), Shutdown(4), NotPresent(5), NotFunctioning(6).