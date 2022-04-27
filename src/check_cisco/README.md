# check_cisco plugins

Suite of plugins for monitoring Cisco devices supporting SNPM. Specifically, the suite is composed by:

* `check_cisco_ce_alarms`: Checks the alarms on a CISCO-CONTENT-ENGINE-MIB compliant device.
* `check_cisco_cpu`: Checks the CPU load (in percent) on a CISCO-PROCESS-MIB or OLD-CISCO-CPU-MIB SNMP compliant device.
* `check_cisco_cras_sesions`: Checks the number of active sessions on a Cisco Remote Access Server supporting the ciscoRemoteAccessMonitorMIB MIB.
* `check_cisco_envmon`: Checks the enviroment sensors on a CISCO-ENVMON-MIB compliant device.
* `check_cisco_fru_fan`: Checks the fans of a CISCO-ENTITY-FRU-CONTROL-MIB compliant device (Cisco Catalyst switches, routers, ASA, MDS 9000 series, ...).
* `check_cisco_fru_module`: Checks the modules status on a CISCO-ENTITY-FRU-CONTROL-MIB compliant device (Cisco Catalyst switches, routers, ASA, MDS 9000 series, ...)
* `check_cisco_fru_ps`: Checks power on a CISCO-ENTITY-FRU-CONTROL-MIB compliant device (Cisco Catalyst switches, routers, ASA, MDS 9000 series, ...)
* `check_cisco_memory`: Checks the used and fragmented memory on a CISCO_MEMORY_POOL_MIB SNMP compliant device.
