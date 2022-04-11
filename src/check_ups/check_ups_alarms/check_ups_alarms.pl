#!/usr/bin/perl

# check_UPS_alarms Nagios Plugin
#
# This nagios plugin is free software, and comes with ABSOLUTELY
# NO WARRANTY. It may be used, redistributed and/or modified under
# the terms of the GNU General Public Licence (see
# http://www.fsf.org/licensing/licenses/gpl.txt).

# MODULE DECLARATION

use strict;

use Monitoring::Plugin;
use Net::SNMP qw(SNMP_VERSION_2C);

# FUNCTION DECLARATION

sub CreateNagiosManager ();
sub CheckArguments ();
sub PerformCheck ();

# CONSTANT DEFINITION

use constant MIB_UPS_ALARMS => '1.3.6.1.2.1.33.1.6';

use constant NAME    => 'check_UPS_alarmas';
use constant VERSION => '0.3b';
use constant USAGE =>
"Usage:\ncheck_UPS_alarms -H <hostname> -w <warning list> -c <critical list>\n"
  . "\t\t[-C <SNMP Community>]  [E <SNMP Version>] [-P <SNMP port>]\n"
  . "\t\t[-V <version>]\n";
use constant BLURB =>
  "This plugin checks the active UPS alarms comparing them with\n"
  . "both warning and critical alarm lists.";
use constant LICENSE =>
  "This nagios plugin is free software, and comes with ABSOLUTELY\n"
  . "no WARRANTY. It may be used, redistributed and/or modified under\n"
  . "the terms of the GNU General Public Licence\n"
  . "(see http://www.fsf.org/licensing/licenses/gpl.txt).\n";
use constant EXAMPLE => "\n\n"
  . "Example:\n" . "\n"
  . "check_UPS_alarms -H 192.168.0.1 -w 1..4,11 -c 5..10\n" . "\n"
  . "It checks host  192.168.0.1 (UPS-MIB SNMP compliant device) looking for any active alarm\n"
  . "present in both warning and critical lists.\n"
  . "Plugin returns CRITICAL one or more alarms with id 5 to 10 are active,\n"
  . "and WARNING if one or more alarms with id 1, 2, 3, 4 or 11 are active.\n"
  . "In both two cases a list of active alarm ids and descriptions is returned.\n"
  . "In other case it returns OK if check has been successfully performed.";

# VARIABLE DEFINITION

my $Nagios;
my $Error;
my $PluginResult, my $PluginOutput;

# MAIN FUNCTION

# Get command line arguments
$Nagios = &CreateNagiosManager( USAGE, VERSION, BLURB, LICENSE, NAME, EXAMPLE );
eval { $Nagios->getopts };

if ( !$@ ) {

    # Command line parsed
    if ( &CheckArguments( $Nagios, $Error ) ) {

        # Argument checking passed
        $PluginResult = &PerformCheck( $Nagios, $PluginOutput );
    }
    else {
        # Error checking arguments
        $PluginOutput = $Error;
        $PluginResult = UNKNOWN;
    }
    $Nagios->nagios_exit( $PluginResult, $PluginOutput );
}
else {
    # Error parsing command line
    $Nagios->nagios_exit( UNKNOWN, $@ );
}

# FUNCTION DEFINITIONS

# Creates and configures a Nagios plugin object
# Input: strings (usage, version, blurb, license, name and example) to configure argument parsing functionality
# Return value: reference to a Nagios plugin object

sub CreateNagiosManager() {

    # Create GetOpt object
    my $Nagios = Monitoring::Plugin->new(
        usage   => $_[0],
        version => $_[1],
        blurb   => $_[2],
        license => $_[3],
        plugin  => $_[4],
        extra   => $_[5]
    );

    # Add argument hostname
    $Nagios->add_arg(
        spec     => 'hostname|H=s',
        help     => 'SNMP agent hostname or IP address',
        required => 1
    );

    # Add argument community
    $Nagios->add_arg(
        spec     => 'community|C=s',
        help     => 'SNMP agent community (default: public)',
        default  => 'public',
        required => 0
    );

    # Add argument version
    $Nagios->add_arg(
        spec     => 'snmpver|E=s',
        help     => 'SNMP protocol version (default: 2)',
        default  => '2',
        required => 0
    );

    # Add argument port
    $Nagios->add_arg(
        spec     => 'port|P=i',
        help     => 'SNMP agent port (default: 161)',
        default  => 161,
        required => 0
    );

    # Add argument warning
    $Nagios->add_arg(
        spec     => 'warning|w=s',
        help     => "Warning alarm id list (type --help for usage example)",
        required => 1
    );

    # Add argument critical
    $Nagios->add_arg(
        spec     => 'critical|c=s',
        help     => "Critical alarm id list (type --help for usage example)",
        required => 1
    );

    # Return value
    return $Nagios;
}

# Checks argument values and sets some default values
# Input: Nagios Plugin object
# Output: Error description string
# Return value: True if arguments ok, false if not

sub CheckArguments() {
    my $Nagios = $_[0];
    my @IfRange;
    my $ArgOK;
    my $ThresholdsFormat;
    my $WarningAlarm;
    my @WARange;
    my @WarningAlarms;
    my $WARangeLength;
    my $CriticalAlarm;
    my @CARange;
    my @CriticalAlarms;
    my $CARangeLength;

    if ( $Nagios->opts->port <= 0 ) {
        $_[1] = "Invalid SNMP agent port: must be greater than zero";
        return 0;
    }

    #Check Warnings Alarms Number
    if ( $Nagios->opts->warning =~ /^(\d+|\d+\.\.\d+)(,(\d+|\d+\.\.\d+))*$/ )
    {    #One or more digits
        @WarningAlarms = split( /,/, $Nagios->opts->warning );
        foreach $WarningAlarm (@WarningAlarms) {
            @WARange       = split( /\.\./, $WarningAlarm );
            $WARangeLength = @WARange;
            if ( $WARangeLength > 1 ) {    #It is an alarm range
                if ( @WARange[0] >= @WARange[1] ) {
                    $_[1] =
"Invalid warning alarm range.The first number must be lower than the second one.";
                    return 0;
                }
                else {
                    if (   $WARange[0] < 0
                        || $WARange[0] > 65535
                        || $WARange[1] < 0
                        || $WARange[1] > 65535 )
                    {
                        $_[1] = "Invalid warning alarm number";
                        return 0;
                    }
                }
            }
            else {    #It is an Alarm Id
                if ( $WarningAlarm < 0 || $WarningAlarm > 65535 ) {
                    $_[1] = "Invalid warning alarm number";
                    return 0;
                }
            }
        }
    }
    else {
        $_[1] = "Invalid warning alarm expression";
        return 0;
    }

    #Check Critical Alarms Number
    if ( $Nagios->opts->critical =~ /^(\d+|\d+\.\.\d+)(,(\d+|\d+\.\.\d+))*$/ )
    {    #One or more digits
        @CriticalAlarms = split( /,/, $Nagios->opts->critical );
        foreach $CriticalAlarm (@CriticalAlarms) {
            @CARange       = split( /\.\./, $CriticalAlarm );
            $CARangeLength = @CARange;
            if ( $CARangeLength > 1 ) {    # It is an alarm range
                if ( @CARange[0] >= @CARange[1] ) {
                    $_[1] =
"Invalid critical alarm range.The first number must be lower than the second one.";
                    return 0;
                }
                else {
                    if (   $CARange[0] < 0
                        || $CARange[0] > 65535
                        || $CARange[1] < 0
                        || $CARange[1] > 65535 )
                    {
                        $_[1] = "Invalid critical alarm number";
                        return 0;
                    }
                }
            }
            else {    # It is an Alarm Id
                if ( $CriticalAlarm < 0 || $CriticalAlarm > 65535 ) {
                    $_[1] = "Invalid critical alarm number";
                    return 0;
                }
            }
        }
    }
    else {
        $_[1] = "Invalid critical alarm expression";
        return 0;
    }

    return 1;
}

# Performs whole check:
# Input: Nagios Plugin object
# Output: Plugin output string
# Return value: Plugin return value

sub PerformCheck() {
    my $OID_UpsAlarmsPresent = MIB_UPS_ALARMS . '.1.0';
    my $OID_UpsAlarmsTable   = MIB_UPS_ALARMS . '.2';

    my $Nagios = $_[0];

    my $SNMPSession;
    my $SNMPError;
    my @descriptionOId;
    my $alarmId;

    my $PluginOutput;
    my $PluginReturnValue = UNKNOWN;
    my @RangeWarningAlarms;
    my @RangeCriticalAlarms;

    # Start new SNMP session
    ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
        -hostname  => $Nagios->opts->hostname,
        -community => $Nagios->opts->community,
        -version   => $Nagios->opts->snmpver,
        -port      => $Nagios->opts->port
    );

    if ( !defined($SNMPSession) ) {
        $PluginOutput = "Error '$SNMPError' starting SNMP session";
    }
    else {
        my $RequestResult =
          $SNMPSession->get_request( -varbindlist => [$OID_UpsAlarmsPresent] );
        if ( !defined $RequestResult ) {

            # SNMP query error
            $PluginOutput =
                "Error '$SNMPError' retrieving info "
              . "from agent $Nagios->{opts}->{hostname}:$Nagios->{opts}->{port} "
              . "using protocol $Nagios->{opts}->{snmpver} "
              . "and community string **hidden for security**"
              ;    # '$Nagios->{opts}->{community}'";
        }
        else {
            my $upsAlarmsPresent = $RequestResult->{$OID_UpsAlarmsPresent};
            if ( $upsAlarmsPresent == 0 ) {

                # If no alarms presents everything is ok and plugin finishes
                $PluginReturnValue = OK;
                $PluginOutput      = "No active alarms";
            }
            else {
                # One or more alarms are active
                my $WarningOutput  = '';
                my $CriticalOutput = '';
                my @WarningAlarms  = split( /,/, $Nagios->opts->warning );
                my @CriticalAlarms = split( /,/, $Nagios->opts->critical );
                my $AlarmsTable =
                  $SNMPSession->get_table( -baseoid => $OID_UpsAlarmsTable );
                my $AlarmsActive = "";
                my @AlarmMessages;
                my $description;

                #Extracted from UPS-MIB
                $AlarmMessages[1] =
"One or more batteries have been determined to require  replacement.";
                $AlarmMessages[2] =
                  "The UPS is drawing power from the batteries.";
                $AlarmMessages[3] =
"The remaining battery run-time is less than or equal to upsConfigLowBattTime.";
                $AlarmMessages[4] =
"The UPS will be unable to sustain the present load when and if the utility power is lost.";
                $AlarmMessages[5] = "A temperature is out of tolerance.";
                $AlarmMessages[6] = "An input condition is out of tolerance.";
                $AlarmMessages[7] =
"An output condition (other than OutputOverload) is out of tolerance.";
                $AlarmMessages[8] =
                  "The output load exceeds the UPS output capacity.";
                $AlarmMessages[9] =
                  "The Bypass is presently engaged on the UPS.";
                $AlarmMessages[10] = "The Bypass is out of tolerance.";
                $AlarmMessages[11] =
                  "The UPS has shutdown as requested, i.e., the output is off.";
                $AlarmMessages[12] =
                  "The entire UPS has shutdown as commanded.";
                $AlarmMessages[13] =
"An uncorrected problem has been detected within the UPS charger subsystem.";
                $AlarmMessages[14] =
                  "The output of the UPS is in the off state.";
                $AlarmMessages[15] = "The UPS system is in the off state.";
                $AlarmMessages[16] =
"The failure of one or more fans in the UPS has been detected.";
                $AlarmMessages[17] =
                  "The failure of one or more fuses has been detected.";
                $AlarmMessages[18] =
                  "A general fault in the UPS has been detected.";
                $AlarmMessages[19] =
                  "The result of the last diagnostic test indicates a failure.";
                $AlarmMessages[20] =
"A problem has been encountered in the communications between the agent and the UPS.";
                $AlarmMessages[21] =
"The UPS output is off and the UPS is awaiting the return of input power.";
                $AlarmMessages[22] =
                  "A upsShutdownAfterDelay countdown is underway.";
                $AlarmMessages[23] =
"The UPS will turn off power to the load in less than 5 seconds; this may be either a timed shutdown or a low battery shutdown.";

                for ( my $i = 1 ; $i <= $upsAlarmsPresent ; $i++ ) {

                    # Get the descriptionOID of the alarm
                    @descriptionOId = split( /\./,
                        $$AlarmsTable{ MIB_UPS_ALARMS . ".2.1.$i.2" } );

                    # Alarm id is the last number after the '.'
                    $alarmId = $descriptionOId[$#descriptionOId];
                    $AlarmsActive .= "$alarmId, ";
                    $description = "";

                    # Check if the alarm is a WellKnownAlarms to add description
                    if ( $alarmId <= $#AlarmMessages ) {
                        $description = "($AlarmMessages[$alarmId])";
                    }

# Check if alarmId is one value of the criticalAlarm array or if it is in a range of the array
                    for ( my $j = 0 ; $j <= $#CriticalAlarms ; $j++ ) {
                        @RangeCriticalAlarms =
                          split( /\.\./, $CriticalAlarms[$j] );
                        if ($#RangeCriticalAlarms) {

                            # Checking range
                            if (   $alarmId >= $RangeCriticalAlarms[0]
                                && $alarmId <= $RangeCriticalAlarms[1] )
                            {
                                $CriticalOutput .=
                                  "#Alarm $alarmId $description is active; ";
                            }
                        }
                        else {
                            if ( $alarmId == $RangeCriticalAlarms[0] ) {
                                $CriticalOutput .=
                                  "#Alarm $alarmId $description is active; ";
                            }
                        }
                    }

                    if ( $CriticalOutput eq '' ) {

                        # No critical alarms present, search warning alarms
                        for ( my $j = 0 ; $j <= $#WarningAlarms ; $j++ ) {
                            @RangeWarningAlarms =
                              split( /\.\./, $WarningAlarms[$j] );
                            if ($#RangeWarningAlarms) {

                                #Checking range
                                if (   $alarmId >= $RangeWarningAlarms[0]
                                    && $alarmId <= $RangeWarningAlarms[1] )
                                {
                                    $WarningOutput .=
"#Alarm $alarmId $description is active; ";
                                }
                            }
                            else {
                                if ( $alarmId == $RangeWarningAlarms[0] ) {
                                    $WarningOutput .=
"#Alarm $alarmId $description is active; ";
                                }
                            }
                        }
                    }
                }

                if ( $CriticalOutput ne '' ) {
                    $PluginReturnValue = CRITICAL;
                    $PluginOutput      = $CriticalOutput;
                }
                elsif ( $WarningOutput ne '' ) {
                    $PluginReturnValue = WARNING;
                    $PluginOutput      = $WarningOutput;
                }
                else {
                    $PluginReturnValue = OK;
                    substr( $AlarmsActive, -2 ) =
                      '';    #erases last comma and blank
                    $AlarmsActive = "(" . $AlarmsActive . ")";
                    $PluginOutput = "Alarms active $AlarmsActive"
                      . " but not set in check lists";
                }
            }
        }

        # Close SNMP session
        $SNMPSession->close();
    }

    #Return result
    $_[1] = $PluginOutput;
    return $PluginReturnValue;
}
