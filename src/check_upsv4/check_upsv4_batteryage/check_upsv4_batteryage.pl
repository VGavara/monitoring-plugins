#!/usr/bin/perl -w

# check_upsv4_batteryage Nagios Plugin
#
# Checks the condition and age of the battery
# on a DeltaUPS-MIB DEFINITIONS
#
# Type check_upsv4_batteryage --help for getting more info and examples.
#
# This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
# It may be used, redistributed and/or modified under the terms of the GNU
# General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).

# MODULE DECLARATION

use strict;

use File::Path;
use Monitoring::Plugin;
use Date::Calc qw(Date_to_Time);
use Net::SNMP qw(SNMP_VERSION_2C);

# FUNCTION DECLARATION

sub CreateNagiosManager ();
sub CheckArguments ();
sub PerformCheck ();

# CONSTANT DEFINITION

use constant DBPERMISSIONS => 0755;

use constant MIB_UPS_BATTERY => '1.3.6.1.4.1.2254.2.4.7';

use constant NAME    => 'check_upsv4_batteryage';
use constant VERSION => '0.1b';
use constant USAGE => "Usage:\n"
  . "check_upsv4_batteryage -H <hostname>\n"
  . "\t\t-w <warning days>\n"
  . "\t\t-c <critical days>\n"
  . "\t\t[-C <SNMP Community>] [-E <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]\n"
  . "\t\t[-V <version>]\n";
use constant BLURB => "Checks the condition and age of the battery\n"
  . "on a DeltaUPS-MIB DEFINITIONS SNMP compliant device";
use constant LICENSE =>
  "This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY\n"
  . "It may be used, redistributed and/or modified under the terms of the GNU\n"
  . " General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).\n";
use constant EXAMPLE => "\n\n"
  . "Example:\n" . "\n"
  . "check_upsv4_batteryage -H 192.168.0.101 -w 5 -c 10\n"
  . "Checks the condition and age of the battery on a DeltaUPS-MIB SNMP compliant device\n"
  . "with IP address 192.168.0.101.\n"
  . "Plugin returns WARNING if the condition of the battery is 'weak' or\n"
  . "the battery expiration date is exceeded by a period of five to ten days.\n"
  . "It returns CRITICAL if the condition of the battery is 'replace' or\n"
  . "the battery expiration date is exceeded by more than ten days.\n"
  . "In other case (condition of the battery 'good' and battery expiration date \n"
  . "is exceeded less than five days or isn�t exceeded), it returns OK \n"
  . "\n";

# VARIABLE DEFINITION

my $Nagios;
my $Error;
my $PluginResult, my $PluginOutput;
my @arrayWarningRanges;
my @arrayCriticalRanges;

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
        spec     => 'warning|w=i',
        help     => "Warning days to exceed ",
        required => 1
    );

    # Add argument critical
    $Nagios->add_arg(
        spec     => 'critical|c=i',
        help     => "Critical days to exceed",
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
    my $ArgOK;
    my $ThresholdsFormat;
    my $i;
    my $Range;

    # Check if agent port number is > 0
    if ( $Nagios->opts->port <= 0 ) {
        $_[1] = "Invalid SNMP agent port: must be greater than zero";
        return 0;
    }

    return 1;
}

# Performs whole check:
# Input: Nagios Plugin object
# Output: Plugin output string
# Return value: Plugin return value

sub PerformCheck() {

    my $OID_dupsBatteryCondiction = MIB_UPS_BATTERY . '.1';
    my $OID_dupsNextReplaceDate   = MIB_UPS_BATTERY . '.11';

    my $Nagios = $_[0];

    my $SNMPSession;
    my $SNMPError;

    my $RequestResult;

    my $PluginOutput      = "";
    my $PluginReturnValue = UNKNOWN;

    my $BatteryCondition;
    my $BatteryExpirationDate;

    my @ConditionString = ( "good", "weak", "replace" );

    # Start new SNMP session
    ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
        -hostname  => $Nagios->opts->hostname,
        -community => $Nagios->opts->community,
        -version   => $Nagios->opts->snmpver,
        -port      => $Nagios->opts->port,
        -timeout   => $Nagios->opts->timeout
    );

    if ( !defined($SNMPSession) ) {

        #SNMP Get error
        $PluginOutput = "Error '$SNMPError' starting session";
    }
    else {
        # Perform SNMP request

        $RequestResult = $SNMPSession->get_request(
            -varbindlist => [$OID_dupsBatteryCondiction] );
        if ( !defined($RequestResult) ) {
            $PluginOutput =
"Error recovering dupsBatteryCondiction ($OID_dupsBatteryCondiction).";
            return $PluginReturnValue;
        }
        $BatteryCondition = $$RequestResult{$OID_dupsBatteryCondiction};
        $RequestResult    = $SNMPSession->get_request(
            -varbindlist => [$OID_dupsNextReplaceDate] );
        if ( !defined($RequestResult) ) {
            $PluginOutput =
"Error recovering dupsNextReplaceDate ($OID_dupsNextReplaceDate).";
            return $PluginReturnValue;
        }
        $BatteryExpirationDate = $$RequestResult{$OID_dupsNextReplaceDate};

        my $TodaySecs = time();
        my @d2        = (
            substr( $BatteryExpirationDate, 0, 4 ),
            substr( $BatteryExpirationDate, 4, 2 ),
            substr( $BatteryExpirationDate, 6, 2 ),
            0, 0, 0
        );
        my $ExpirationSecs = Date_to_Time(@d2);

   #Days with battery expired (negative values means battery hasn�t expired yet)
        my $ExpiratedDays =
          int( ( ( ( $TodaySecs - $ExpirationSecs ) / 60 ) / 60 ) / 24 );

        if (   ( $BatteryCondition eq 0 )
            && ( $ExpiratedDays < $Nagios->opts->warning ) )
        {
            $PluginReturnValue = OK;
            if ( $ExpiratedDays < 0 ) {
                $PluginOutput =
                    "Battery system condition is 'good', "
                  . ( -$ExpiratedDays )
                  . " days for battery expiration date.";
            }
            else {
                $PluginOutput =
"Expiration date EXCEEDED by $ExpiratedDays days, device reports battery system condition as 'good'.";
            }
        }
        else {
            if ( $BatteryCondition eq 2 ) {    # condition='replace'
                $PluginReturnValue = CRITICAL;
                $PluginOutput =
"Device reports battery system to be replaced, battery expiration date ";
                if ( $ExpiratedDays < 0 ) {
                    $PluginOutput .= "is "
                      . substr( $BatteryExpirationDate, 6, 2 ) . "/"
                      . substr( $BatteryExpirationDate, 4, 2 ) . "/"
                      . substr( $BatteryExpirationDate, 0, 4 ) . " ("
                      . ( -$ExpiratedDays )
                      . " days remaining)\n";
                }
                else {
                    $PluginOutput .= "was "
                      . substr( $BatteryExpirationDate, 6, 2 ) . "/"
                      . substr( $BatteryExpirationDate, 4, 2 ) . "/"
                      . substr( $BatteryExpirationDate, 0, 4 )
                      . " ($ExpiratedDays days ago)\n";
                }
            }
            else {
                if ( $ExpiratedDays >= $Nagios->opts->critical ) {
                    $PluginReturnValue = CRITICAL;
                    $PluginOutput .=
"Expiration date EXCEEDED by $ExpiratedDays days, device reports battery system condition as '$ConditionString[$BatteryCondition]'";
                }
                else {    #Warning
                    $PluginReturnValue = WARNING;
                    if ( $BatteryCondition eq 1 ) {
                        $PluginOutput =
"Battery system condition is 'weak', battery expiration date ";
                        if ( $ExpiratedDays <= 0 ) {
                            $PluginOutput .= "is "
                              . substr( $BatteryExpirationDate, 6, 2 ) . "/"
                              . substr( $BatteryExpirationDate, 4, 2 ) . "/"
                              . substr( $BatteryExpirationDate, 0, 4 ) . " ("
                              . ( -$ExpiratedDays )
                              . " days remaining)\n";
                        }
                        else {
                            $PluginOutput .= "was "
                              . substr( $BatteryExpirationDate, 6, 2 ) . "/"
                              . substr( $BatteryExpirationDate, 4, 2 ) . "/"
                              . substr( $BatteryExpirationDate, 0, 4 )
                              . " ($ExpiratedDays days ago)\n";
                        }
                    }
                    else {
                        if (   ( $ExpiratedDays >= $Nagios->opts->warning )
                            && ( $ExpiratedDays < $Nagios->opts->critical ) )
                        {
                            $PluginOutput =
"Expiration date EXCEEDED by $ExpiratedDays days, device reports battery system condition as 'good'.";
                        }
                    }
                }
            }
        }

        # Close SNMP session
        $SNMPSession->close;
    }

    #Return result
    $_[1] = $PluginOutput;
    return $PluginReturnValue;
}
