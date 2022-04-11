# check_ups_alarms. README.

MIB UPS (RFC 1628) supports an active alarms table in the managed device (OID upsAlarmTable, 1.3.6.1.2.1.33.1.6.2). Each table input stores:

- upsAlarmId: An unique active alarm identifier
- upsAlarmDescr: A reference to an alarm description object
- upsAlarmTime: The value of sysUpTime when the alarm condition was detected

MIB includes a list of alarms objects called Well-Known-Alarms:

| ID | OID | DESCRIPTION |
|----|-----|-------------|
| 1  | upsAlarmBatteryBad (1.3.6.1.2.1.33.1.6.3.1) | One or more batteries have been determined to require replacement |
| 2  | upsAlarmOnBattery (1.3.6.1.2.1.33.1.6.3.2) | The UPS is drawing power from the batteries |
| 3  | upsAlarmLowBattery (1.3.6.1.2.1.33.1.6.3.3) | The remaining battery run-time is less than or equal to upsConfigLowBattTime |
| 4  | upsAlarmDepletedBattery (1.3.6.1.2.1.33.1.6.3.4) | The UPS will be unable to sustain the present load when and if the utility power is lost |
| 5  | upsAlarmTempBad (1.3.6.1.2.1.33.1.6.3.5) | A temperature is out of tolerance |
| 6  | upsAlarmInputBad (1.3.6.1.2.1.33.1.6.3.6) | An input condition is out of tolerance |
| 7  | upsAlarmOutputBad (1.3.6.1.2.1.33.1.6.3.7) | An output condition (other than OutputOverload) is out of tolerance |
| 8  | upsAlarmOutputOverload (1.3.6.1.2.1.33.1.6.3.8) | The output load exceeds the UPS output capacity |
| 9  | upsAlarmOnBypass (1.3.6.1.2.1.33.1.6.3.9) | The Bypass is presently engaged on the UPS |
| 10 | upsAlarmBypassBad (1.3.6.1.2.1.33.1.6.3.10) | The Bypass is out of tolerance |
| 11 | upsAlarmOutputOffAsRequested (1.3.6.1.2.1.33.1.6.3.11) | The UPS has shutdown as requested, i.e., the output is off |
| 12 | upsAlarmUpsOffAsRequested (1.3.6.1.2.1.33.1.6.3.12) | The entire UPS has shutdown as commanded |
| 13 | upsAlarmChargerFailed (1.3.6.1.2.1.33.1.6.3.13) | An uncorrected problem has been detected within the UPS charger subsystem |
| 14 | upsAlarmUpsOutputOff (1.3.6.1.2.1.33.1.6.3.14) |	The output of the UPS is in the off state |
| 15 | upsAlarmUpsSystemOff (1.3.6.1.2.1.33.1.6.3.15) |	The UPS system is in the off state |
| 16 | upsAlarmFanFailure (1.3.6.1.2.1.33.1.6.3.16) | The failure of one or more fans in the UPS has been detected |
| 17 | upsAlarmFuseFailure (1.3.6.1.2.1.33.1.6.3.17) | The failure of one or more fuses has been detected  |
| 18 | upsAlarmGeneralFault (1.3.6.1.2.1.33.1.6.3.18) | A general fault in the UPS has been detected |
| 19 | upsAlarmDiagnosticTestFailed (1.3.6.1.2.1.33.1.6.3.19) | The result of the last diagnostic test indicates a failure |
| 20 | upsAlarmCommunicationsLost (1.3.6.1.2.1.33.1.6.3.20) | A problem has been encountered in the communications between the agent and the UPS |
| 21 | upsAlarmAwaitingPower (1.3.6.1.2.1.33.1.6.3.21) | The UPS output is off and the UPS is awaiting the return of input power |
| 22 | upsAlarmShutdownPending (1.3.6.1.2.1.33.1.6.3.22) | A upsShutdownAfterDelay countdown is underway |
| 23 | upsAlarmShutdownImminent (1.3.6.1.2.1.33.1.6.3.23) | The UPS will turn off power to the load in less than 5 seconds; this may be either a timed shutdown or a low battery shutdown |
| 24 | upsAlarmTestInProgress (1.3.6.1.2.1.33.1.6.3.24) | A test is in progress, as initiated and indicated by the Test Group.  Tests initiated via other implementation-specific mechanisms can indicate the presence of the testing in the alarm table, if desired, via a OBJECT-IDENTITY macro in the MIB document specific to that implementation and are outside the scope of this OBJECT-IDENTITY |

Note that the upsAlarmDescr field stores the alarm OID, not to the description itself. For instance, this should be a valid alarm table entry:

- upsAlarmId: 1
- upsAlarmDescr: 1.3.6.1.2.1.33.1.6.3.3
- upsAlarmTime: (whatever UTIME valid value)

See http://monitoringtt.blogspot.com/2017/10/plugin-of-month-checking-ups-alarms.html for more information.
