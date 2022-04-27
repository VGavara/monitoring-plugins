# check_upsv4

Suite of plugins for monitoring UPSs supporting SNPM and MIB UPSv4 (DeltaUPS-MIB). Specifically, the suite is composed by:

* `check_upsv4_alarms`: Checks the active UPS alarms.
* `check_upsv4_batteryage`: Checks the batteries age and condition.
* `check_upsv4_inputs`: Checks the input levels (frequency, voltage and/or current).
* `check_upsv4_mode`: Checks the UPS working mode (online, bypass or offline, with batteries normal, low or depleted).