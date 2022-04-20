#!/usr/bin/perl -w

# check_cisco_fru_fan Nagios-compatible plugin
#
# Checks the operational state of the fans or fan tray on a
# CISCO-ENTITY-FRU-CONTROL-MIB  complaint device
#
# This check plugin is free software, and comes with ABSOLUTELY
# NO WARRANTY. It may be used, redistributed and/or modified under
# the terms of the MIT General Public License (see
# https://opensource.org/licenses/MIT).
#
# HISTORY
#
# v.0.4b: Improved plugin output in test and check mode; coding style changes
# v.0.3b: Improved compatibility with Cisco Nexus devices setting SNMP max
#         message size to 5 kbytes (many thanks to Helge Waastad, Fabien Dedenon
#         and Tobias Wigand for their feedback)

# MODULE DECLARATION

use strict;

use lib "/usr/local/nagios/perl/lib/";

use Monitoring::Plugin;
use Net::SNMP qw(SNMP_VERSION_2C);

# FUNCTION DECLARATION

sub CreateNagiosManager ();
sub CheckArguments ();

# CONSTANT DEFINITION

use constant FRU_CEFSFANTRAYOPERSTATUS => '1.3.6.1.4.1.9.9.117.1.4.1.1.1';
use constant FRU_ENTPHYSICALDESCR      => '1.3.6.1.2.1.47.1.1.1.1.2';

use constant FRU_FAN_STATUS => [ '', 'Unknown', 'Up', 'Down', 'Warning' ];

use constant FRU_FAN_STATUS_DESC => [
    '', 'Unknown', 'Powered on', 'Powered down',
    'Partial failure, needs replacement as soon as possible'
];

use constant MODE_TEST  => 1;
use constant MODE_CHECK => 2;

use constant SNMP_MAX_MSG_SIZE => 5120;

use constant NAME    => 'check_cisco_fru_fan';
use constant VERSION => '0.4b';
use constant USAGE =>
"Usage:\ncheck_cisco_fru_fan -H <hostname> [-e <fan id list> -w <warning list>] -c <critical list>]\n"
  . "\t\t[-C <SNMP Community>]  [E <SNMP Version>] [-P <SNMP port>]\n"
  . "\t\t[-V <version>]\n";
use constant BLURB =>
  "This plugin checks the operational state of the fans or fans tray \n"
  . "on a CISCO-ENTITY-FRU-CONTROL-MIB complaint device.";
use constant LICENSE =>
  "This check plugin is free software, and comes with ABSOLUTELY\n"
  . "no WARRANTY. It may be used, redistributed and/or modified under\n"
  . "the terms of the MIT General Public License\n"
  . "(see https://opensource.org/licenses/MIT).\n";
use constant EXAMPLE => "\n\n"
  . "Example:\n"
  . "check_cisco_fru_fan -H 192.168.0.12\n" . "\n"
  . "Test Mode that checks the compatibility of the plugin on a host with address 192.168.0.12\n"
  . "using SNMP protocol version 1 and 'public' as community\n"
  . "Plugin returns OK if it is a CISCO-ENTITY-FRU-CONTROL-MIB compliant device and can recover fan data. Also, a list of all fans\n"
  . "with id, status and description is returned. If it is not compatible returns UNKNOWN\n"
  . "\n"
  . "check_cisco_fru_fan -H 192.168.0.12 -e 332,334 -w 4 -c 3\n" . "\n"
  . "Checks, on a CISCO-ENTITY-FRU-CONTROL-MIB compliant device with IP address 192.168.0.12,\n"
  . "if any of the fans passed through their id with the -e argument\n"
  . "are in any of the states passed in -w and -c argument.\n"
  . "It returns CRITICAL if any fan (332 or 334 id fan) has a state with id 3, \n"
  . "WARNING if any fan has a state with id 4, and in other case returns OK\n"
  . "The operational id state of a fan or fan tray is:\n"
  . "\tunknown(1) - unknown.\n"
  . "\tup(2) - powered on.\n"
  . "\tdown(3) - powered down.\n"
  . "\twarning(4) - partial failure, needs replacement as soon as possible.";

# VARIABLE DEFINITION

my $Nagios;
my $Error;
my $PluginMode;
my $PluginReturnValue, my $PluginOutput = "";

# MAIN FUNCTION

# Get command line arguments
$Nagios = &CreateNagiosManager( USAGE, VERSION, BLURB, LICENSE, NAME, EXAMPLE );
eval { $Nagios->getopts };

if ( !$@ ) {

    # Command line parsed
    if ( &CheckArguments( $Nagios, $Error, $PluginMode ) ) {

        # Argument checking passed

        if ( $PluginMode == MODE_TEST ) {
            $PluginReturnValue = &TestHost( $Nagios, $PluginOutput );
            $PluginOutput      = "TEST MODE\n" . $PluginOutput;
        }
        else {
            $PluginReturnValue = &PerformCheck( $Nagios, $PluginOutput );
        }

    }
    else {
        # Error checking arguments
        $PluginOutput      = $Error;
        $PluginReturnValue = UNKNOWN;
    }
    $Nagios->nagios_exit( $PluginReturnValue, $PluginOutput );
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

    # Add argument ids
    $Nagios->add_arg(
        spec     => 'ids|e=s',
        help     => "Fan id list <idFan>(,<idFan>)*",
        required => 0
    );

    # Add argument warning
    $Nagios->add_arg(
        spec => 'warning|w=s',
        help => "Warning thresholds in the format <idFanState>(,<idFanState>)*",
        required => 0
    );

    # Add argument critical
    $Nagios->add_arg(
        spec => 'critical|c=s',
        help => "Critical threshold in the format <idFanState>(,<idFanState>)*",
        required => 0
    );

    # Return value
    return $Nagios;
}

# Checks argument values and sets some default values
# Input: Nagios-compatible plugin object
# Output: Error description string
# Return value: True if arguments ok, false if not

sub CheckArguments() {
    my $Nagios = $_[0];
    my @WarningTypes;
    my $WarningType;

    my @CriticalTypes;
    my $CriticalType;

    if ( $Nagios->opts->port <= 0 ) {
        $_[1] = "Invalid SNMP agent port: must be greater than zero";
        return 0;
    }
    if (   ( !defined $Nagios->opts->warning )
        && ( !defined $Nagios->opts->critical )
        && ( !defined $Nagios->opts->ids ) )
    {    #Test mode
        $_[2] = MODE_TEST;
        return 1;
    }
    elsif (( defined $Nagios->opts->warning )
        && ( defined $Nagios->opts->critical ) )
    {
        #Check Warnings Types Number
        if ( $Nagios->opts->warning =~ /^\d+(,\d+)*$/ ) {    #One or more digits
            @WarningTypes = split( /,/, $Nagios->opts->warning );
            foreach $WarningType (@WarningTypes) {
                if ( $WarningType < 0 || $WarningType > 65535 ) {
                    $_[1] = "Invalid warning id state";
                    return 0;
                }
            }
        }
        else {
            $_[1] = "Invalid warning ids expression";
            return 0;
        }

        #Check Critical Types Number
        if ( $Nagios->opts->critical =~ /^\d+(,\d+)*$/ ) {   #One or more digits
            @CriticalTypes = split( /,/, $Nagios->opts->critical );
            foreach $CriticalType (@CriticalTypes) {
                if ( $CriticalType < 0 || $CriticalType > 65535 ) {
                    $_[1] = "Invalid critical id state";
                    return 0;
                }
            }
        }
        else {
            $_[1] = "Invalid critical ids expression";
            return 0;
        }
        if ( defined $Nagios->opts->ids ) {
            if ( $Nagios->opts->ids !~ /^\d+(,\d+)*$/ ) {
                $_[1] = "Invalid fan ids expression";
                return 0;
            }
        }
        else {
            $_[1] = "Fan ids list must be defined in check mode";
            return 0;
        }
        $_[2] = MODE_CHECK;
    }
    else {
        $_[1] =
"Invalid arguments.It must be defined critical and warning argument for check mode or neither of both for test mode.";
        return 0;
    }

    return 1;
}

# Checks if host supports fans data on CISCO-ENTITY-FRU-CONTROL-MIB .
# If OK, it returns info about fans
# Input: Nagios-compatible plugin object
# Output: Test output string
# Return value: OK if test passed, UNKNOWN if not.

sub TestHost() {
    my $SNMPSession;
    my $SNMPError;
    my $Output = "";
    my $PluginReturnValue;
    my @FanMessages;
    $FanMessages[1] = "Unknown";
    $FanMessages[2] = "Up";
    $FanMessages[3] = "Down.";
    $FanMessages[4] = "Warning";

    ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
        -hostname   => $Nagios->opts->hostname,
        -community  => $Nagios->opts->community,
        -version    => $Nagios->opts->snmpver,
        -port       => $Nagios->opts->port,
        -timeout    => $Nagios->opts->timeout,
        -maxmsgsize => SNMP_MAX_MSG_SIZE
    );

    if ( defined($SNMPSession) ) {
        my $RequestResultIndex =
          $SNMPSession->get_entries( -columns => [FRU_CEFSFANTRAYOPERSTATUS] );
        my $RequestResultDesc =
          $SNMPSession->get_entries( -columns => [FRU_ENTPHYSICALDESCR] );
        if ( !defined($RequestResultIndex) || !defined($RequestResultDesc) ) {
            $SNMPError = $SNMPSession->error();
            if ( defined($SNMPError) && ( $SNMPError ne '' ) ) {
                $_[1] = "SNMP Error: $SNMPError ";
            }
            else {
                $_[1] =
"Empty data set recovered. Probably device didn't support CISCO-ENTITY-FRU-CONTROL-MIB.mib";
            }

            $SNMPSession->close();
            return UNKNOWN;
        }

        my $id;
        my $Oid;
        my $status;
        my $desc = "";
        $Output = "CISCO FANS DATA\n";
        foreach $Oid ( keys %{$RequestResultIndex} ) {
            $id     = ( split( /\./, $Oid ) )[-1];
            $status = FRU_FAN_STATUS->[ $RequestResultIndex->{$Oid} ];
            $desc   = $RequestResultDesc->{ FRU_ENTPHYSICALDESCR . ".$id" }
              if defined $RequestResultDesc->{ FRU_ENTPHYSICALDESCR . ".$id" };
            $Output .=
                "Fan id: $id\tFan status: "
              . $RequestResultIndex->{$Oid}
              . " ($status)\tFan description = $desc\n";
        }
        $PluginReturnValue = OK;
        $SNMPSession->close();
    }
    else {
        $PluginReturnValue = UNKNOWN;
        $Output            = "Test failed. No response from host.";
    }

    $_[1] = $Output;
    return $PluginReturnValue;
}

# Performs whole check:
# Input: Nagios-compatible plugin object
# Output: Plugin output string
# Return value: Plugin return value

sub PerformCheck() {
    my $SNMPSession;
    my $SNMPError;

    my @FanIds;
    my $FanId;
    my $FanStatus;

    my @CriticalStates = split( /,/, $Nagios->opts->critical );
    my @WarningStates  = split( /,/, $Nagios->opts->warning );
    my $CriticalOutput = "";
    my $WarningOutput  = "";

    my $PluginOutput;
    my $PluginReturnValue = UNKNOWN;

    my $RequestResult;
    my $FanName;

    # Start new SNMP session
    ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
        -hostname   => $Nagios->opts->hostname,
        -community  => $Nagios->opts->community,
        -version    => $Nagios->opts->snmpver,
        -port       => $Nagios->opts->port,
        -timeout    => $Nagios->opts->timeout,
        -maxmsgsize => SNMP_MAX_MSG_SIZE
    );

    if ( !defined($SNMPSession) ) {
        $PluginOutput = "Error '$SNMPError' starting session";
    }
    else {
        @FanIds = split( /,/, $Nagios->opts->ids );
        foreach $FanId (@FanIds) {
            $RequestResult = $SNMPSession->get_request(
                -varbindlist => [ FRU_CEFSFANTRAYOPERSTATUS . ".$FanId" ] );
            if ( !defined($RequestResult) ) {
                $SNMPSession->close();
                $_[1] = "Unable to recover fan with id = $FanId";
                return UNKNOWN;
            }

            $FanStatus =
              $$RequestResult{ FRU_CEFSFANTRAYOPERSTATUS . ".$FanId" };
            if ( $FanStatus !~ /^\d+$/ ) {
                $SNMPSession->close();
                $_[1] =
                  "No such instance ($FanId) currently exists at this OID";
                return UNKNOWN;
            }

            $RequestResult = $SNMPSession->get_request(
                -varbindlist => [ FRU_ENTPHYSICALDESCR . ".$FanId" ] );
            if (
                ( !defined($RequestResult) )
                || ( $$RequestResult{ FRU_ENTPHYSICALDESCR . ".$FanId" } =~
                    m/No Such/ )
              )
            {
                $SNMPSession->close();
                $_[1] = "Error recovering fan name with id $FanId";
                return UNKNOWN;
            }
            $FanName = $$RequestResult{ FRU_ENTPHYSICALDESCR . ".$FanId" };
            for ( my $i = 0 ; $i <= $#CriticalStates ; $i++ ) {
                if ( $FanStatus == $CriticalStates[$i] ) {
                    $CriticalOutput .=
                      "$FanName: " . FRU_FAN_STATUS_DESC->[$FanStatus] . '; ';
                    last;
                }
            }
            if ( $CriticalOutput eq '' ) {

                #No critical state
                for ( my $i = 0 ; $i <= $#WarningStates ; $i++ ) {
                    if ( $FanStatus == $WarningStates[$i] ) {
                        $WarningOutput .= "$FanName: "
                          . FRU_FAN_STATUS_DESC->[$FanStatus] . '; ';
                        last;
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
                if ( @FanIds == 1 ) {
                    $PluginOutput = "Fan device '$FanName' status is "
                      . FRU_FAN_STATUS->[$FanStatus];
                }
                else {
                    $PluginOutput = "All checked fans are OK";
                }
            }

        }

        $SNMPSession->close();
    }

    #Return result
    $_[1] = $PluginOutput;
    return $PluginReturnValue;
}
