#!/usr/bin/perl

# check_ups_mode Nagios-compatible plugin
#
# This check plugin is free software, and comes with ABSOLUTELY
# NO WARRANTY. It may be used, redistributed and/or modified under
# the terms of the MIT General Public License (see
# https://opensource.org/licenses/MIT).

# MODULE DECLARATION

use strict;

use File::Path;
use Data::Dumper;
use Monitoring::Plugin;
use Net::SNMP qw(SNMP_VERSION_2C);

# FUNCTION DECLARATION

sub CreateNagiosManager ();
sub CheckArguments ();
sub PerformCheck ();

# CONSTANT DEFINITION

use constant DBPERMISSIONS => 0755;

use constant UPS_MIB_BATTERY => '.1.3.6.1.2.1.33.1.2';
use constant UPS_MIB_OUTPUTS => '.1.3.6.1.2.1.33.1.4';

use constant UPS_MODE_ONLINE          => 1;
use constant UPS_MODE_OFFLINE         => 2;
use constant UPS_MODE_OFFLINE_LOWBATT => 3;
use constant UPS_MODE_OFFLINE_NOBATT  => 4;
use constant UPS_MODE_BYPASSED        => 5;

use constant NAME    => 'check_ups_mode';
use constant VERSION => '1.0';
use constant USAGE => "Usage:\ncheck_ups_mode -H <hostname>\n"
  . "\t\t-w [<mode id>, <mode id>,...]\n"
  . "\t\t-c [<mode id>, <mode id>, ...]\n"
  . "\t\t[-l <battery low level threshold> [-d <battery depleted level threshold>]\n"
  . "\t\t[-C <SNMP Community>] [-E <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]\n"
  . "\t\t[-V <version>]\n";
use constant BLURB =>
"This plugin checks working mode (online/bypass/offline with batt. normal, low or depleted)\n"
  . "on a RFC1628 (UPS-MIB) SNMP compliant device returning autonomy values as performance data.";
use constant LICENSE =>
  "This check plugin is free software, and comes with ABSOLUTELY\n"
  . "no WARRANTY. It may be used, redistributed and/or modified under\n"
  . "the terms of the MIT General Public License\n"
  . "(see https://opensource.org/licenses/MIT).\n";
use constant EXAMPLE => "\n\n"
  . "Example:\n" . "\n"
  . "check_ups_mode -H 192.168.0.1 -w 2,5 -c 3,4\n" . "\n"
  . "It checks the working mode of a UPS-MIB SNMP compliant device with IP address 192.168.0.1, SNMP\n"
  . "protocol 2 and real community 'public'. The plugin returns WARNING if it is working offline\n"
  . "and its battery level is NOT low (Offline=2) or it is in bypass mode (bypass=5).\n"
  . "It return CRITICAL if it is working offline and its level is low (Offline battery low = 3)\n"
  . "or battery is depleted (Offline battery depleted = 4). In other case it returns OK.\n";
"Type check_ups_mode --help to get info about available working mode values.";

# VARIABLE DEFINITION

my $Nagios;
my $Error;
my $PluginResult,     my $PluginOutput;
my @WarningValueList, my @CriticalValueList;

# MAIN FUNCTION

# Get command line arguments
$Nagios = &CreateNagiosManager( USAGE, VERSION, BLURB, LICENSE, NAME, EXAMPLE );
eval { $Nagios->getopts };

if ( !$@ ) {

    # Command line parsed
    if (
        &ManageArguments(
            $Nagios, $Error, \@WarningValueList, \@CriticalValueList
        )
      )
    {
        # Argument checking passed
        $PluginResult =
          &PerformCheck( $Nagios, \@WarningValueList, \@CriticalValueList,
            $PluginOutput );
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

    # Add argument battery low level threshold
    $Nagios->add_arg(
        spec => 'lowthreshold|l=s',
        help =>
          "Battery level threshold that defines 'Offline battery low' mode,\n  "
          . "in the format <value>[%], being <value> the backup minutes\n  "
          . "or <value>% the battery percent.\n  "
          . "(Threshold value defined in UPS is used by default)",
        required => 0
    );

    # Add argument battery depleted level threshold
    $Nagios->add_arg(
        spec => 'depthreshold|d=s',
        help =>
"Battery level threshold that defines 'Offline battery depleted' mode,\n  "
          . "in the format <value>[%], being <value> the backup minutes\n  "
          . "or <value>% the battery percent.\n  "
          . "(Threshold value defined in UPS is used by default)",
        required => 0
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
        spec => 'warning|w=s',
        help =>
"Warning modes in the format (<mode_id>(,<mode_id>)*) where >mode_id> can be:\n"
          . "\t1: Online\n"
          . "\t2: Offline\n"
          . "\t3: Offline battery low\n"
          . "\t4: Offline battery depleted\n"
          . "\t5: Bypassed",
        required => 1
    );

    # Add argument critical
    $Nagios->add_arg(
        spec => 'critical|c=s',
        help => "Critical modes in the format (<mode_id>(,<mode_id>)*)\n  "
          . "<mode_id> takes the same values that those defined for warning argument.",
        required => 1
    );

    # Return value
    return $Nagios;
}

# Checks argument values and retrieves warning & critical value lists
# Input: Nagios-compatible plugin object
# Output: Error description string, warning and critical lists
# Return value: True if arguments ok, false if not

sub ManageArguments() {
    my $Nagios            = $_[0];
    my $WarningValueList  = $_[2];
    my $CriticalValueList = $_[3];
    my $ThresholdsFormat;

    # Check if low and/or depleted thresholds are properly defined
    if ( defined $Nagios->opts->lowthreshold ) {
        if ( !$Nagios->opts->lowthreshold =~ /^\d+\%{0,1}$/ ) {
            $_[1] =
              "Invalid battery-low threshold: " . $Nagios->opts->lowthreshold;
            return 0;
        }
    }
    if ( defined $Nagios->opts->depthreshold ) {
        if ( !$Nagios->opts->depthreshold =~ /^\d+\%{0,1}$/ ) {
            $_[1] = "Invalid battery-depleted threshold: "
              . $Nagios->opts->depthreshold;
            return 0;
        }
    }
    if (   defined $Nagios->opts->lowthreshold
        && defined $Nagios->opts->depthreshold )
    {
        if ( $Nagios->opts->lowthreshold < $Nagios->opts->depthreshold ) {
            $_[1] =
"battery-low threshold cannot be lower than battery-depleted threshold"
              . $Nagios->opts->lowthreshold;
            return 0;
        }
    }

    # Check if agent port number is > 0
    if ( $Nagios->opts->port <= 0 ) {
        $_[1] = "Invalid SNMP agent port: must be greater than zero";
        return 0;
    }

    # Check warning & critical thresholds
    if ( defined $Nagios->opts->warning ) {
        if ( $Nagios->opts->warning =~ /^\d+(,\d+)*$/ ) {
            @$WarningValueList = split( /,/, $Nagios->opts->warning );

            foreach my $WarningValue (@$WarningValueList) {
                if (   $WarningValue < UPS_MODE_ONLINE
                    || $WarningValue > UPS_MODE_BYPASSED )
                {
                    $_[1] =
                      "Invalid battery status warning value: $WarningValue";
                    return 0;
                }
            }
        }
        else {
            $_[1] =
              "Invalid warning value: list of comma separated numbers expected";
            return 0;
        }
    }

    if ( defined $Nagios->opts->critical ) {
        if ( $Nagios->opts->critical =~ /^\d+(,\d+)*$/ ) {
            @$CriticalValueList = split( /,/, $Nagios->opts->critical );

            foreach my $CriticalValue (@$CriticalValueList) {
                if (   $CriticalValue < UPS_MODE_ONLINE
                    || $CriticalValue > UPS_MODE_BYPASSED )
                {
                    $_[1] =
                      "Invalid battery status critical value: $CriticalValue";
                    return 0;
                }
            }
        }
        else {
            $_[1] =
"Invalid critical value: list of comma separated numbers expected";
            return 0;
        }
    }

    return 1;
}

# Performs whole check:
# Input: Nagios-compatible plugin object, warning value list, critical value list
# Output: Plugin output string
# Return value: Plugin return value

sub PerformCheck() {
    my $OID_UPSOutputStatus              = UPS_MIB_OUTPUTS . '.1.0';
    my $OID_UPSBatteryStatus             = UPS_MIB_BATTERY . '.1.0';
    my $OID_UPSEstimatedMinutesRemaining = UPS_MIB_BATTERY . '.3.0';
    my $OID_UPSEstimatedChargeRemaining  = UPS_MIB_BATTERY . '.4.0';

    my $Nagios            = $_[0];
    my $WarningValueList  = $_[1];
    my $CriticalValueList = $_[2];

    my $SNMPSession;
    my $SNMPError;
    my @RequestColumns;
    my $RequestResult;

    my $UPSMode;

    my $BatteryCharge;
    my $BatteryBackup;
    my $UPSBatteryStatus;

    my $PluginReturnValue = UNKNOWN;
    my $PluginOutput;
    my $PerfData = "";

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
        # Get output status
        push( my @oidRequest, $OID_UPSOutputStatus );
        if (
            !defined(
                $RequestResult =
                  $SNMPSession->get_request( -varbindlist => \@oidRequest )
            )
          )
        {
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
            # Output status successfully retrieved
            $UPSMode = $RequestResult->{$OID_UPSOutputStatus};

            # Retrieve (if available) battery charge percent and backup time
            push( my @oidRequest, $OID_UPSEstimatedChargeRemaining );
            push( @oidRequest,    $OID_UPSEstimatedMinutesRemaining );
            if (
                defined(
                    my $RequestResult =
                      $SNMPSession->get_request( -varbindlist => \@oidRequest )
                )
              )
            {
                $BatteryCharge =
                  $RequestResult->{$OID_UPSEstimatedChargeRemaining};
                $BatteryBackup =
                  $RequestResult->{$OID_UPSEstimatedMinutesRemaining};
            }

            # Process output status as UPS working mode
            $PluginReturnValue = OK;
            if ( $UPSMode == 3 ) {
                $UPSMode = UPS_MODE_ONLINE;
            }
            elsif ( $UPSMode == 4 ) {
                $UPSMode = UPS_MODE_BYPASSED;
            }
            elsif ( $UPSMode == 5 ) {

                # Set Mode value based on UPS battery status as default value
                # prior to check command line threshold arguments
                $UPSMode = UPS_MODE_OFFLINE;
                push( my @oidRequest, $OID_UPSBatteryStatus );
                if (
                    defined $SNMPSession->get_request(
                        -varbindlist => \@oidRequest ) )
                {
                    # Set plugin return value and output
                    if ( $RequestResult->{$OID_UPSBatteryStatus} == 3 ) {
                        $UPSMode = UPS_MODE_OFFLINE_LOWBATT;
                    }
                    elsif ( $RequestResult->{$OID_UPSBatteryStatus} == 4 ) {
                        $UPSMode = UPS_MODE_OFFLINE_NOBATT;
                    }
                }
                else {
                    # Output value = Other, None, Booster or Reducer
                    $UPSMode           = undef;
                    $PluginReturnValue = UNKNOWN;
                    $PluginOutput      = 'Unable to get UPS battery status';
                }

                # Check depleted threshold as defined as argument
                if ( defined $Nagios->opts->depthreshold ) {
                    if ( $Nagios->opts->depthreshold =~ /^\d+$/ ) {

                        # Depleted threshold defined as minutes
                        if ( defined $BatteryBackup ) {
                            $UPSMode = UPS_MODE_OFFLINE_NOBATT
                              if $BatteryBackup <= $Nagios->opts->depthreshold;
                        }
                        else {
# Unable to get Battery backup value, thus unable to evaluate depleted threshold argument
                            $PluginReturnValue = UNKNOWN;
                            $PluginOutput =
'Depleted threshold set but unable to get battery backup time';
                        }
                    }
                    else {
                        # Depleted threshold defined as percent
                        if ( defined $BatteryCharge ) {
                            $UPSMode = UPS_MODE_OFFLINE_NOBATT
                              if $BatteryCharge <= $Nagios->opts->depthreshold;
                        }
                        else {
# Unable to get Battery backup value, thus unable to evaluate depleted threshold argument
                            $PluginReturnValue = UNKNOWN;
                            $PluginOutput =
'Depleted threshold set but unable to get battery charge percent';
                        }
                    }
                }

# Check low threshold as defined as argument (unless depleted condition already set)
                if ( $UPSMode != UPS_MODE_OFFLINE_NOBATT
                    && defined $Nagios->opts->lowthreshold )
                {
                    if ( $Nagios->opts->lowthreshold =~ /^\d+$/ ) {

                        # Low threshold defined as minutes
                        if ( defined $BatteryBackup ) {
                            $UPSMode = UPS_MODE_OFFLINE_LOWBATT
                              if $BatteryBackup <= $Nagios->opts->lowthreshold;
                        }
                        else {
# Unable to get Battery backup value, thus unable to evaluate low threshold argument
                            $PluginReturnValue = UNKNOWN;
                            $PluginOutput =
'Low threshold set but unable to get battery backup time';
                        }
                    }
                    else {
                        # Low threshold defined as percent
                        if ( defined $BatteryCharge ) {
                            $UPSMode = UPS_MODE_OFFLINE_NOBATT
                              if $BatteryCharge <= $Nagios->opts->lowthreshold;
                        }
                        else {
# Unable to get Battery backup value, thus unable to evaluate low threshold argument
                            $PluginReturnValue = UNKNOWN;
                            $PluginOutput =
'Low threshold set but unable to get battery charge percent';
                        }
                    }
                }
            }
            else {
                $PluginReturnValue = UNKNOWN;
            }

            if ( $PluginReturnValue != UNKNOWN ) {

                # Set plugin return value checking warning and critical lists
                if ( grep { $_ == $UPSMode } @$CriticalValueList ) {
                    $PluginReturnValue = CRITICAL;
                }
                elsif ( grep { $_ == $UPSMode } @$WarningValueList ) {
                    $PluginReturnValue = WARNING;
                }

                # Set plugin output and model performance data
                if ( $UPSMode == UPS_MODE_ONLINE ) {
                    $PluginOutput = 'UPS online';
                }
                elsif ( $UPSMode == UPS_MODE_OFFLINE ) {
                    $PluginOutput = 'UPS offline';
                }
                elsif ( $UPSMode == UPS_MODE_OFFLINE_LOWBATT ) {
                    $PluginOutput = 'UPS offline, battery LOW';
                }
                elsif ( $UPSMode == UPS_MODE_OFFLINE_NOBATT ) {
                    $PluginOutput = 'UPS offline, battery DEPLETED';
                }
                elsif ( $UPSMode == UPS_MODE_OFFLINE_NOBATT ) {
                    $PluginOutput = "UPS in bypass mode: output NOT protected";
                }

                if ( defined $BatteryCharge ) {
                    $PluginOutput .= " (battery charged at $BatteryCharge%, ";
                    $PerfData = "BatteryCharge=$BatteryCharge%;;;0;100 ";
                }
                else {
                    $PluginOutput .= ' (unknown battery charge, ';
                }
                if ( defined $BatteryBackup ) {
                    $PluginOutput .= "$BatteryBackup minutes of backup)";
                    $PerfData .= "BatteryBackup=" . $BatteryBackup . "min;;;0;";
                }
                else {
                    $PluginOutput .= 'unknown backup time)';
                }

                # In bypass mode performance data is reported as zero
                if ( $UPSMode == 4 ) {
                    $PerfData =
                      "BatteryCharge=0%;;;0;100 BatteryBackup=0min;;;0;";
                }

                $PluginOutput .= " | $PerfData";
            }
        }

        # Close SNMP session
        $SNMPSession->close;
    }

    # Return result
    $_[3] = $PluginOutput;
    return $PluginReturnValue;
}
