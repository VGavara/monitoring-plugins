#!/usr/bin/perl

# check_upsv4_alarms Nagios Plugin
#
# Check the alarms on a DeltaUPS-MIB
#
# This nagios plugin is free software, and comes with ABSOLUTELY
# NO WARRANTY. It may be used, redistributed and/or modified under
# the terms of the GNU General Public Licence (see
# http://www.fsf.org/licensing/licenses/gpl.txt).

# MODULE DECLARATION

use strict;

use lib "/usr/local/nagios/perl/lib/";

use Data::Dumper;
use Monitoring::Plugin;
use Net::SNMP qw(SNMP_VERSION_2C);

# FUNCTION DECLARATION

sub CreateNagiosManager ();
sub CheckArguments ();

#sub PerformCheck ();

# CONSTANT DEFINITION

use constant MIB_UPS_ALARMS => '1.3.6.1.4.1.2254.2.4.9';

#use constant UPS_ALARMS_PRESENT => '.1.3.6.1.2.1.33.1.6.1';

use constant NAME    => 'check_upsv4_alarmas';
use constant VERSION => '0.2b';
use constant USAGE =>
"Usage:\ncheck_upsv4_alarms -H <hostname> -w <warning list> -c <critical list>\n"
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
  . "check_upsv4_alarms -H 192.168.0.1 -w 1..5,10 -c 5..10\n" . "\n"
  . "It checks, in a DeltaUPS SNMP compliant device, if any of the alarms passed with -w \n"
  . "and -c arguments are active. It returns WARNING if one or more alarms from 1 to 5 or 10 \n"
  . "are active, CRITICAL if one or more alarms from 5 to 10 are active. If not active alarms \n"
  . "are found, or their id is greater than 10 it returns OK.\n"
  . "If the state is WARNING or CRITICAL  it returns a list of active alarm id's and descriptions.";

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
        help     => "Warning thresholds in the format <idAlarm>(,<idAlarm>)*",
        required => 1
    );

    # Add argument critical
    $Nagios->add_arg(
        spec     => 'critical|c=s',
        help     => "Critical threshold in the format <idAlarm>(,<idAlarm>)*",
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
# NOTA: mirar solamente la parte que se encarga de recuperar los datos v�a SNMP y la parte final donde devuelve el resultado.
sub PerformCheck() {
    my $SNMPSession;
    my $SNMPError;
    my $i;
    my $j;
    my $alarmId;
    my @CriticalAlarms = split( /,/, $Nagios->opts->critical );
    my @WarningAlarms  = split( /,/, $Nagios->opts->warning );
    my $CriticalOutput = "";
    my $WarningOutput  = "";
    my @RangeWarningAlarms;
    my @RangeCriticalAlarms;
    my $PluginOutput;
    my $PluginReturnValue = UNKNOWN;
    my $RequestResult;
    my $AlarmState;

    #Descriptios extracted from UPSv4.mib od DeltaUPS MIB
    my @AlarmsWarningMessages;
    $AlarmsWarningMessages[1]  = "UPS is disconnected";
    $AlarmsWarningMessages[2]  = "Input power has failed";
    $AlarmsWarningMessages[3]  = "UPS batteries low";
    $AlarmsWarningMessages[4]  = "Load percent is over the load warning value";
    $AlarmsWarningMessages[5]  = "Load percent is over the load severity value";
    $AlarmsWarningMessages[6]  = "UPS load is on bypass";
    $AlarmsWarningMessages[7]  = "General failure";
    $AlarmsWarningMessages[8]  = "Battery ground is faulted";
    $AlarmsWarningMessages[9]  = "UPS test is in progress";
    $AlarmsWarningMessages[10] = "UPS test has failed";
    $AlarmsWarningMessages[11] = "UPS fuse failure";
    $AlarmsWarningMessages[12] = "UPS output is overloaded";
    $AlarmsWarningMessages[13] = "UPS output is overcurrented";
    $AlarmsWarningMessages[14] = "UPS inverter is abnormal";
    $AlarmsWarningMessages[15] = "UPS rectifier is abnormal";
    $AlarmsWarningMessages[16] = "UPS reserve is abnormal";
    $AlarmsWarningMessages[17] = "UPS load is on reserve";
    $AlarmsWarningMessages[18] = "UPS over heat";
    $AlarmsWarningMessages[19] = "UPS output is abnormal";
    $AlarmsWarningMessages[20] = "UPS bypass is bad";
    $AlarmsWarningMessages[21] = "UPS is in standby mode";
    $AlarmsWarningMessages[22] = "UPS charger has failed";
    $AlarmsWarningMessages[23] = "UPS fan has failed";
    $AlarmsWarningMessages[24] = "UPS is in the economic mode";
    $AlarmsWarningMessages[25] = "UPS output is turned off";
    $AlarmsWarningMessages[26] = "Smart Shutdown is in progress";
    $AlarmsWarningMessages[27] = "UPS emergency power off";

    # Start new SNMP session
    ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
        -hostname  => $Nagios->opts->hostname,
        -community => $Nagios->opts->community,
        -version   => $Nagios->opts->snmpver,
        -port      => $Nagios->opts->port,
        -timeout   => $Nagios->opts->timeout
    );

    if ( !defined($SNMPSession) ) {
        $PluginOutput = "Error '$SNMPError' starting session";
    }
    else {

        $RequestResult =
          $SNMPSession->get_entries( -columns => [MIB_UPS_ALARMS] );
        if ( !defined($RequestResult) ) {

            # SNMP output status query error
            $SNMPError = $SNMPSession->error();
            $PluginOutput =
                "Error '$SNMPError' retrieving info "
              . "from agent $Nagios->{opts}->{hostname}:$Nagios->{opts}->{port} "
              . "using protocol $Nagios->{opts}->{snmpver} "
              . "and community string **hidden for security**"
              ;    # '$Nagios->{opts}->{community}'";
        }
        else {
            for ( $i = 1 ; $i <= 27 ; $i++ ) {
                $AlarmState = $RequestResult->{ MIB_UPS_ALARMS . ".$i.0" };
                if ( $AlarmState eq 'NULL' ) {
                    next;
                }
                $alarmId = $i;

# Check if alarmId is one value of the criticalAlarm array or if it is in a range of the array
                for ( $j = 0 ; $j <= $#CriticalAlarms ; $j++ ) {
                    @RangeCriticalAlarms = split( /\.\./, $CriticalAlarms[$j] );
                    if ( $AlarmState eq 1 ) {    #Alarm is active
                        if ($#RangeCriticalAlarms) {    #Checking range
                            if (    ( $alarmId >= $RangeCriticalAlarms[0] )
                                and ( $alarmId <= $RangeCriticalAlarms[1] ) )
                            {
                                $CriticalOutput .=
"#Alarm $alarmId($AlarmsWarningMessages[$alarmId]) is active; ";
                            }
                        }
                        else {
                            if ( $alarmId == $RangeCriticalAlarms[0] ) {
                                $CriticalOutput .=
"#Alarm $alarmId($AlarmsWarningMessages[$alarmId]) is active; ";
                            }
                        }
                    }
                }
                if ( $CriticalOutput eq '' ) {    #No critical alarms
                    for ( $j = 0 ; $j <= $#WarningAlarms ; $j++ ) {
                        @RangeWarningAlarms =
                          split( /\.\./, $WarningAlarms[$j] );
                        if ( $AlarmState eq 1 ) {    #Alarm is active
                            if ($#RangeWarningAlarms) {    #Checking range
                                if (    ( $alarmId >= $RangeWarningAlarms[0] )
                                    and ( $alarmId <= $RangeWarningAlarms[1] ) )
                                {
                                    $WarningOutput .=
"#Alarm $alarmId($AlarmsWarningMessages[$alarmId]) is active; ";
                                }
                            }
                            else {
                                if ( $alarmId == $RangeWarningAlarms[0] ) {

                #La alarma es critica, por lo que se a�ade a la cadena de salida
                                    $WarningOutput .=
"#Alarm $alarmId($AlarmsWarningMessages[$alarmId]) is active; ";
                                }
                            }
                        }
                    }
                }
            }
            if ( $CriticalOutput ne '' ) {
                $PluginReturnValue = CRITICAL;
                $PluginOutput      = $CriticalOutput;
            }
            else {
                if ( $WarningOutput ne '' ) {
                    $PluginReturnValue = WARNING;
                    $PluginOutput      = $WarningOutput;
                }
                else {
                    $PluginReturnValue = OK;
                    $PluginOutput      = "No active alarms";
                }

            }
        }
    }

    #~ }

    #Return result
    $_[1] = $PluginOutput;
    return $PluginReturnValue;
}
