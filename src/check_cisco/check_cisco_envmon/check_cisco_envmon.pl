#!/usr/bin/perl -w

# check_cisco_envmon Nagios-compatible plugin
# Checks the enviroment sensors on a CISCO-ENVMON-MIB compliant device
# Type check_cisco_envmon --help for getting more info and examples.
#
# This check plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
# It may be used, redistributed and/or modified under the terms of the MIT
# General Public Licence (see https://opensource.org/licenses/MIT).
#
# HISTORY
#
# v.0.3b: Corrected bug that inhibited checking thresholds defined as just one
#         element.

# MODULE DECLARATION

use strict;

use Monitoring::Plugin;
use Net::SNMP qw(SNMP_VERSION_2C);

# FUNCTION DECLARATION

sub CreateNagiosManager ();
sub CheckArguments ();
sub TestHost ();
sub PerformCheck ();

# CONSTANT DEFINITION

use constant ENVMON_MIB => '.1.3.6.1.4.1.9.9.13';

use constant ENVMON_STATES => [
    '',         'Normal',     'Warning', 'Critical',
    'Shutdown', 'NotPresent', 'NotFunctioning'
];

use constant ENVMON_STATE_DESC => [
    '',
    'The environment is good, such as low temperature',
'The environment is bad, such as temperature above normal operation range but not to high',
'The environment is very bad, such as temperature much higher than normal operation limit',
    'The environment is the worst, the system should be shutdown immediately',
'The environmental monitor is not present,, such as temperature sensors do not exist',
'The environmental monitor does not function properly, such as a temperature sensor generates a abnormal data like 1000C'
];

use constant MODE_TEST  => 1;
use constant MODE_CHECK => 2;

use constant NAME    => 'check_cisco_envmon';
use constant VERSION => '0.3b';
use constant USAGE => "Usage:\n"
  . "check_cisco_envmon -H <hostname>\n"
  . "\t\t[-C <SNMP Community>] [-e <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]\n"
  . "\t\t[-g <voltage id list>]\n"
  . "\t\t[-T <temperature id list>]\n"
  . "\t\t[-f <fan id list>]\n"
  . "\t\t[-s <supply id list>]\n"
  . "\t\t[-w <environment states id threshold list> -c <environment states id threshold list>]\n"
  . "\t\t[-V <version>]\n";
use constant BLURB =>
"This plugin checks the enviroment sensors on a CISCO-ENVMON-MIB compliant device.";
use constant LICENSE =>
  "This check plugin is free software, and comes with ABSOLUTELY NO WARRANTY\n"
  . "It may be used, redistributed and/or modified under the terms of the MIT\n"
  . "General Public Licence (see https://opensource.org/licenses/MIT).\n";
use constant EXAMPLE => "\n\n"
  . "Examples:\n" . "\n"
  . "check_cisco_envmon -H 192.168.0.4\n" . "\n"
  . "If available, displays info of the device with address 192.168.0.4\n"
  . "using SNMP protocol version 1 and 'public' as community\n"
  . "(useful for checking compatibility and displaying environmental data)\n"
  . "\n"
  . "check_cisco_envmon -H 192.168.0.4 -w 2,6 -c 3,4\n"
  . "Checks all environmental sensors avaliable on a host with address 192.168.0.4\n"
  . "using SNMP protocol version 1 and 'public' as community.\n"
  . "Plugin returns CRITICAL if any sensor has a environmental state equals to 'critical'(3)\n"
  . "or 'shutdown'(4),and WARNING if any sensor has a environmental state\n"
  . "equals to 'warning'(2) or 'notFunctioning'(6).\n"
  . "In other case it returns OK if check has been performed or UNKNOWN.\n"
  . "\n"
  . "check_cisco_envmon -H 192.168.0.4 -f all -s 1003 -w 2,6 -c 3,4\n" . "\n"
  . "Checks all avaliable fans, and the power supply with id 1003 on a host with address 192.168.0.4\n"
  . "using SNMP protocol version 1 and 'public' as community.\n"
  . "Plugin returns CRITICAL if any checked sensor has a environmental state equals to 'critical'(3)\n"
  . "or 'shutdown'(4),and WARNING if any checked sensor has a environmental state\n"
  . "equals to 'warning'(2) or 'notFunctioning'(6).\n"
  . "In other case it returns OK if check has been performed or UNKNOWN.\n"
  . "Status values are defined in CISCO-ENVMON-MIB as: Normal(1), Warning(2), Critical(3), Shutdown(4), NotPresent(5), NotFunctioning(6).";

# VARIABLE DEFINITION

my $Nagios;
my $Error;
my $PluginMode;
my $PluginReturnValue, my $PluginOutput = '';

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
            $PluginOutput      = "TEST MODE\n\n" . $PluginOutput;
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
        help     => 'SNMP protocol version (default: 1)',
        default  => '1',
        required => 0
    );

    # Add argument port
    $Nagios->add_arg(
        spec     => 'port|P=i',
        help     => 'SNMP agent port (default: 161)',
        default  => 161,
        required => 0
    );

    # Add argument voltage
    $Nagios->add_arg(
        spec => 'voltage|g=s',
        help =>
'Comma separated voltage id list or \'all\' (all voltage ids present)',
        required => 0
    );

    # Add argument temperature
    $Nagios->add_arg(
        spec => 'temperature|T=s',
        help =>
'Comma separated temperature id list or \'all\' (all temperature ids present)',
        required => 0
    );

    # Add argument fan
    $Nagios->add_arg(
        spec => 'fan|f=s',
        help => 'Comma separated fan id list or \'all\' (all fan ids present)',
        required => 0
    );

    # Add argument supply
    $Nagios->add_arg(
        spec => 'supply|s=s',
        help =>
          'Comma separated supply id list or \'all\' (all supply ids present)',
        required => 0
    );

    # Add argument warning
    $Nagios->add_arg(
        spec => 'warning|w=s',
        help => "Comma separated Cisco Environment States Ids threshold list. "
          . "Valid thesholds are numeric values from 1 to 6 "
          . "normal(1), warning(2), critical(3), shutdown(4), notPresent(5), notFunctioning(6)",
        required => 0
    );

    # Add argument critical
    $Nagios->add_arg(
        spec => 'critical|c=s',
        help => "Comma separated Cisco Environment States Ids threshold list. "
          . "Valid thesholds are numeric values from 1 to 6 "
          . "normal(1), warning(2), critical(3), shutdown(4), notPresent(5), notFunctioning(6)",
        required => 0
    );

    # Return value
    return $Nagios;
}

# Checks argument values and sets some default values
# Input: Nagios-compatible plugin object
# Output: Error description string, Plugin mode
# Return value: True if arguments ok, false if not

sub CheckArguments() {
    my $Nagios = $_[0];

    # Check if agent port number is > 0
    if ( $Nagios->opts->port <= 0 ) {
        $_[1] = "Invalid SNMP agent port: must be greater than zero";
        return 0;
    }

    # Check plugin test mode
    if (   ( defined( $Nagios->opts->warning ) )
        && ( defined( $Nagios->opts->critical ) ) )
    {
        $_[2] = MODE_CHECK;

        #print "warn y critical";
        # Check voltage list
        if ( defined( $Nagios->opts->voltage ) ) {
            if ( $Nagios->opts->voltage !~ /^((\d+,)*\d+)|all$/ ) {
                $_[1] =
"Invalid voltage number list: must be a comma separated voltage-id list or 'all'";
                return 0;
            }
        }

        # Check temperature list
        if ( defined( $Nagios->opts->temperature ) ) {
            if ( $Nagios->opts->temperature !~ /^((\d+,)*\d+)|all$/ ) {
                $_[1] =
"Invalid temperature number list: must be a comma separated temperature-id list or 'all'";
                return 0;
            }
        }

        # Check fan list
        if ( defined( $Nagios->opts->fan ) ) {
            if ( $Nagios->opts->fan !~ /^((\d+,)*\d+)|all$/ ) {
                $_[1] =
"Invalid fan number list: must be a comma separated fan-id list or 'all'";
                return 0;
            }
        }

        # Check supply list
        if ( defined( $Nagios->opts->supply ) ) {
            if ( $Nagios->opts->supply !~ /^((\d+,)*\d+)|all$/ ) {
                $_[1] =
"Invalid supply number list: must be a comma separated supply-id list or 'all'";
                return 0;
            }
        }

        # Check warning value list
        if ( $Nagios->opts->warning !~ /^(\d+,)*\d+$/ ) {
            $_[1] =
"Invalid warning threshold list: must be a comma separated environmental cisco state ids";
            return 0;
        }

        # Check critical value list
        if ( $Nagios->opts->critical !~ /^(\d+,)*\d+$/ ) {
            $_[1] =
"Invalid critical threshold list: must be a comma separated environmental cisco state ids";
            return 0;
        }

    }
    else {
        if (   !defined( $Nagios->opts->warning )
            && !defined( $Nagios->opts->critical ) )
        {
            $_[2] = MODE_TEST;

        }
        else {
            $_[1] = "Invalid argument set";
            return 0;
        }
    }

    return 1;
}

# Checks if host supports CISCO-ENVMON related info.
# If true, it returns info about environmental sensors
# Input: Nagios-compatible plugin object
# Output: Test output string
# Return value: OK if test passed, UNKNOWN if not.

sub TestHost() {
    my $OID_EnvMonVoltageStatusEntry     = ENVMON_MIB . '.1.2.1';
    my $OID_EnvMonTemperatureStatusEntry = ENVMON_MIB . '.1.3.1';
    my $OID_EnvMonFanStatusEntry         = ENVMON_MIB . '.1.4.1';
    my $OID_EnvMonSupplyStatusEntry      = ENVMON_MIB . '.1.5.1';

    my $Nagios = $_[0];

    my $SNMPSession;
    my $SNMPError;
    my @RequestData;
    my $RequestResult;

    my $Output = "";
    my @VoltageIdsPresent;
    my @TemperatureIdsPresent;
    my @FanIdsPresent;
    my @SupplyIdsPresent;

    # Start new SNMP session
    ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
        -hostname  => $Nagios->opts->hostname,
        -community => $Nagios->opts->community,
        -version   => $Nagios->opts->snmpver,
        -port      => $Nagios->opts->port,
        -timeout   => $Nagios->opts->timeout
    );

    if ( defined($SNMPSession) ) {
        $RequestResult = $SNMPSession->get_entries( -columns => [ENVMON_MIB] );

        if ( defined $RequestResult ) {
            my $Oid;

            #Recovering environment ids checking their state
            foreach $Oid ( keys %{$RequestResult} ) {
                if ( $Oid =~ /$OID_EnvMonVoltageStatusEntry\.7\.(\d+)/ ) {
                    $VoltageIdsPresent[ $#VoltageIdsPresent + 1 ] = $1;
                }
                if ( $Oid =~ /$OID_EnvMonTemperatureStatusEntry\.6\.(\d+)/ ) {
                    $TemperatureIdsPresent[ $#TemperatureIdsPresent + 1 ] = $1;
                }
                if ( $Oid =~ /$OID_EnvMonFanStatusEntry\.3\.(\d+)/ ) {
                    $FanIdsPresent[ $#FanIdsPresent + 1 ] = $1;
                }
                if ( $Oid =~ /$OID_EnvMonSupplyStatusEntry\.3\.(\d+)/ ) {
                    $SupplyIdsPresent[ $#SupplyIdsPresent + 1 ] = $1;
                }
            }
            $Output = "ENVIRONMENTAL DATA\n";

            if ( $#VoltageIdsPresent >= 0 ) {
                $Output .= "\nEnvMonVoltageStatus";
            }
            foreach (@VoltageIdsPresent) {
                my $VoltageId = $_;
                $Output .= "\nVoltage Id: $VoltageId\t";
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonVoltageStatusEntry . ".1." . $VoltageId
                        }
                    )
                  )
                {
                    # index defined
                    $Output .=
                      "Index: "
                      . $RequestResult->{ $OID_EnvMonVoltageStatusEntry . ".1."
                          . $VoltageId }
                      . "\t";
                }
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonVoltageStatusEntry . ".2." . $VoltageId
                        }
                    )
                  )
                {
                    # description defined
                    $Output .=
                      "Description: "
                      . $RequestResult->{ $OID_EnvMonVoltageStatusEntry . ".2."
                          . $VoltageId }
                      . "\t";
                }
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonVoltageStatusEntry . ".3." . $VoltageId
                        }
                    )
                  )
                {
                    # value defined
                    $Output .=
                      "Value: "
                      . $RequestResult->{ $OID_EnvMonVoltageStatusEntry . ".3."
                          . $VoltageId }
                      . "mV\t";
                }
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonVoltageStatusEntry . ".4." . $VoltageId
                        }
                    )
                  )
                {
                    # thresholdlow defined
                    $Output .=
                      "Threshold Low: "
                      . $RequestResult->{ $OID_EnvMonVoltageStatusEntry . ".4."
                          . $VoltageId }
                      . "\t";
                }
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonVoltageStatusEntry . ".5." . $VoltageId
                        }
                    )
                  )
                {
                    # thresholdlow defined
                    $Output .=
                      "Description: "
                      . $RequestResult->{ $OID_EnvMonVoltageStatusEntry . ".5."
                          . $VoltageId }
                      . "\t";
                }
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonVoltageStatusEntry . ".6." . $VoltageId
                        }
                    )
                  )
                {
                    # last shutdown defined
                    $Output .= 'Last shutdown: '
                      . ENVMON_STATES->[
                      $RequestResult->{
                          "$OID_EnvMonVoltageStatusEntry.6.$VoltageId"}
                      ]
                      . ' ('
                      . $RequestResult->{
                        "$OID_EnvMonVoltageStatusEntry.6.$VoltageId"}
                      . ")\t";
                }
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonVoltageStatusEntry . ".7." . $VoltageId
                        }
                    )
                  )
                {
                    # state defined
                    $Output .=
                      'State: '
                      . $RequestResult->{
                        "$OID_EnvMonVoltageStatusEntry.7.$VoltageId"}
                      . ' ('
                      . ENVMON_STATES->[
                      $RequestResult->{
                          "$OID_EnvMonVoltageStatusEntry.7.$VoltageId"}
                      ]
                      . ': '
                      . ENVMON_STATE_DESC->[
                      $RequestResult->{
                          "$OID_EnvMonVoltageStatusEntry.7.$VoltageId"}
                      ]
                      . ")\t";
                }
            }
            if ( $#TemperatureIdsPresent >= 0 ) {
                $Output .= "\nEnvMonTemperatureStatus";
            }
            foreach (@TemperatureIdsPresent) {
                my $TemperatureId = $_;
                $Output .= "\nSensor Id: $TemperatureId\t";
                if (
                    defined(
                        $RequestResult->{
                                $OID_EnvMonTemperatureStatusEntry . ".1."
                              . $TemperatureId
                        }
                    )
                  )
                {
                    # index defined
                    $Output .=
                      "Index: "
                      . $RequestResult->{ $OID_EnvMonTemperatureStatusEntry
                          . ".1."
                          . $TemperatureId }
                      . "\t";
                }
                if (
                    defined(
                        $RequestResult->{
                                $OID_EnvMonTemperatureStatusEntry . ".2."
                              . $TemperatureId
                        }
                    )
                  )
                {
                    # description defined
                    $Output .=
                      "Description: "
                      . $RequestResult->{ $OID_EnvMonTemperatureStatusEntry
                          . ".2."
                          . $TemperatureId }
                      . "\t";
                }
                if (
                    defined(
                        $RequestResult->{
                                $OID_EnvMonTemperatureStatusEntry . ".3."
                              . $TemperatureId
                        }
                    )
                  )
                {
                    # value defined
                    $Output .=
                      "Value: "
                      . $RequestResult->{ $OID_EnvMonTemperatureStatusEntry
                          . ".3."
                          . $TemperatureId }
                      . "C\t";
                }
                if (
                    defined(
                        $RequestResult->{
                                $OID_EnvMonTemperatureStatusEntry . ".4."
                              . $TemperatureId
                        }
                    )
                  )
                {
                    # threshold defined
                    $Output .=
                      "Threshold: "
                      . $RequestResult->{ $OID_EnvMonTemperatureStatusEntry
                          . ".4."
                          . $TemperatureId }
                      . "\t";
                }
                if (
                    defined(
                        $RequestResult->{
                                $OID_EnvMonTemperatureStatusEntry . ".5."
                              . $TemperatureId
                        }
                    )
                  )
                {
                    # last shutdown defined
                    $Output .=
                      "Last Shutdown: "
                      . $RequestResult->{ $OID_EnvMonTemperatureStatusEntry
                          . ".5."
                          . $TemperatureId }
                      . "\t";
                }
                if (
                    defined(
                        $RequestResult->{
                                $OID_EnvMonTemperatureStatusEntry . ".6."
                              . $TemperatureId
                        }
                    )
                  )
                {
                    # state defined
                    $Output .=
                      'State: '
                      . $RequestResult->{
                        "$OID_EnvMonTemperatureStatusEntry.6.$TemperatureId"}
                      . ' ('
                      . ENVMON_STATES->[
                      $RequestResult->{
                          "$OID_EnvMonTemperatureStatusEntry.6.$TemperatureId"}
                      ]
                      . ': '
                      . ENVMON_STATE_DESC->[
                      $RequestResult->{
                          "$OID_EnvMonTemperatureStatusEntry.6.$TemperatureId"}
                      ]
                      . ")\t";
                }
            }
            if ( $#FanIdsPresent >= 0 ) {
                $Output .= "\nEnvMonFanStatus";
            }
            foreach (@FanIdsPresent) {
                my $FanId = $_;
                $Output .= "\nFan Id: $FanId\t";
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonFanStatusEntry . ".1." . $FanId
                        }
                    )
                  )
                {
                    # index defined
                    $Output .=
                      "Index: "
                      . $RequestResult->{ $OID_EnvMonFanStatusEntry . ".1."
                          . $FanId }
                      . "\t";
                }
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonFanStatusEntry . ".2." . $FanId
                        }
                    )
                  )
                {
                    # description defined
                    $Output .=
                      "Description: "
                      . $RequestResult->{ $OID_EnvMonFanStatusEntry . ".2."
                          . $FanId }
                      . "\t";
                }
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonFanStatusEntry . ".3." . $FanId
                        }
                    )
                  )
                {
                    # state defined
                    $Output .=
                        'State: '
                      . $RequestResult->{"$OID_EnvMonFanStatusEntry.3.$FanId"}
                      . ' ('
                      . ENVMON_STATES
                      ->[ $RequestResult->{"$OID_EnvMonFanStatusEntry.3.$FanId"}
                      ]
                      . ': '
                      . ENVMON_STATE_DESC
                      ->[ $RequestResult->{"$OID_EnvMonFanStatusEntry.3.$FanId"}
                      ]
                      . ")\t";
                }
            }
            if ( $#SupplyIdsPresent >= 0 ) {
                $Output .= "\nEnvMonSupplyStatus";
            }
            foreach (@SupplyIdsPresent) {
                my $SupplyId = $_;
                $Output .= "\nSupply Id: $SupplyId\t";
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonSupplyStatusEntry . ".1." . $SupplyId
                        }
                    )
                  )
                {
                    # index defined
                    $Output .=
                      "Index: "
                      . $RequestResult->{ $OID_EnvMonSupplyStatusEntry . ".1."
                          . $SupplyId }
                      . "\t";
                }
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonSupplyStatusEntry . ".2." . $SupplyId
                        }
                    )
                  )
                {
                    # description defined
                    $Output .=
                      "Description: "
                      . $RequestResult->{ $OID_EnvMonSupplyStatusEntry . ".2."
                          . $SupplyId }
                      . "\t";
                }
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonSupplyStatusEntry . ".3." . $SupplyId
                        }
                    )
                  )
                {
                    # state defined
                    $Output .=
                      'State: '
                      . $RequestResult->{
                        "$OID_EnvMonSupplyStatusEntry.3.$SupplyId"}
                      . ' ('
                      . ENVMON_STATES->[
                      $RequestResult->{
                          "$OID_EnvMonSupplyStatusEntry.3.$SupplyId"}
                      ]
                      . ': '
                      . ENVMON_STATE_DESC->[
                      $RequestResult->{
                          "$OID_EnvMonSupplyStatusEntry.3.$SupplyId"}
                      ]
                      . ")\t";
                }
            }

        }
        else {
            $SNMPError = $SNMPSession->error();
            $_[1] =
                "Error '$SNMPError' requesting envmon data "
              . "from agent $Nagios->{opts}->{hostname}:$Nagios->{opts}->{port} "
              . "using protocol $Nagios->{opts}->{snmpver} "
              . "and community string **hidden for security**";
            return UNKNOWN;
        }

        $SNMPSession->close();
    }
    else {
        # Error starting SNMP session;
        $PluginOutput = "Error '$SNMPError' starting session";
        return UNKNOWN;
    }
    $_[1] = $Output;
    return OK;
}

# Performs whole check:
# Input: Nagios-compatible plugin object
# Output: Plugin output string
# Return value: Plugin return value

sub PerformCheck() {
    my $OID_EnvMonVoltageStatusEntry     = ENVMON_MIB . '.1.2.1';
    my $OID_EnvMonTemperatureStatusEntry = ENVMON_MIB . '.1.3.1';
    my $OID_EnvMonFanStatusEntry         = ENVMON_MIB . '.1.4.1';
    my $OID_EnvMonSupplyStatusEntry      = ENVMON_MIB . '.1.5.1';

    my $Nagios = $_[0];

    my $SNMPSession;
    my $SNMPError;
    my @RequestColumns;
    my $RequestResult;
    my $WarningOutput  = "";
    my $CriticalOutput = "";
    my $PluginOutput;
    my $PluginReturnValue = UNKNOWN;
    my $PerformanceData;

    my @VoltageIdsPresent;
    my @VoltageIds;
    my @TemperatureIdsPresent;
    my @TemperatureIds;
    my @FanIdsPresent;
    my @SupplyIdsPresent;

    my @WarningStates  = split( /,/, $Nagios->opts->warning );
    my @CriticalStates = split( /,/, $Nagios->opts->critical );

    # Start new SNMP session
    ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
        -hostname  => $Nagios->opts->hostname,
        -community => $Nagios->opts->community,
        -version   => $Nagios->opts->snmpver,
        -port      => $Nagios->opts->port,
        -timeout   => $Nagios->opts->timeout
    );
    if ( defined($SNMPSession) ) {

        $RequestResult = $SNMPSession->get_entries( -columns => [ENVMON_MIB] );

        my $Oid;

        #Recovering environment ids checking their state
        foreach $Oid ( keys %{$RequestResult} ) {
            if ( $Oid =~ /$OID_EnvMonVoltageStatusEntry\.7\.(\d+)/ ) {
                $VoltageIdsPresent[ $#VoltageIdsPresent + 1 ] = $1;
            }
            if ( $Oid =~ /$OID_EnvMonTemperatureStatusEntry\.6\.(\d+)/ ) {
                $TemperatureIdsPresent[ $#TemperatureIdsPresent + 1 ] = $1;
            }
            if ( $Oid =~ /$OID_EnvMonFanStatusEntry\.3\.(\d+)/ ) {
                $FanIdsPresent[ $#FanIdsPresent + 1 ] = $1;
            }
            if ( $Oid =~ /$OID_EnvMonSupplyStatusEntry\.3\.(\d+)/ ) {
                $SupplyIdsPresent[ $#SupplyIdsPresent + 1 ] = $1;
            }
        }
        my $voltage;
        my $temperature;
        my $fan;
        my $supply;
        my $SomeEnvironmentDefined = 1;
        if (   ( !defined( $Nagios->opts->voltage ) )
            && ( !defined( $Nagios->opts->temperature ) )
            && ( !defined( $Nagios->opts->fan ) )
            && ( !defined( $Nagios->opts->supply ) ) )
        {
            $voltage                = 'all';
            $temperature            = 'all';
            $fan                    = 'all';
            $supply                 = 'all';
            $SomeEnvironmentDefined = 0;
        }
        else {
            if ( defined( $Nagios->opts->voltage ) ) {
                $voltage = $Nagios->opts->voltage;
            }
            if ( defined( $Nagios->opts->temperature ) ) {
                $temperature = $Nagios->opts->temperature;
            }
            if ( defined( $Nagios->opts->fan ) ) {
                $fan = $Nagios->opts->fan;
            }
            if ( defined( $Nagios->opts->supply ) ) {
                $supply = $Nagios->opts->supply;
            }

        }

        # Voltage management
        if ( defined($voltage) ) {
            my $VoltageValue;
            if ( $voltage eq 'all' ) {    #All voltages are checked
                @VoltageIds = @VoltageIdsPresent;
                if ( $#VoltageIds eq -1 ) {    #no voltages present
                    if ( $SomeEnvironmentDefined eq 1 )
                    {    #Environment argument defined by user
                        $SNMPSession->close();
                        $_[1] = "Error. No environmental data for voltages";
                        return UNKNOWN;
                    }
                }
            }
            else {
                @VoltageIds = split( /,/, $voltage );
            }
            foreach (@VoltageIds) {
                my $VoltageId = $_;
                my $VoltageState =
                  $RequestResult->{ $OID_EnvMonVoltageStatusEntry . ".7."
                      . $VoltageId };
                if ( !defined($VoltageState) ) {
                    $SNMPSession->close();
                    $_[1] = "Error recovering voltage with id $VoltageId";
                    return UNKNOWN;
                }
                my $VoltageDesc;
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonVoltageStatusEntry . ".2." . $VoltageId
                        }
                    )
                  )
                {    #description defined
                    $VoltageDesc =
                      $RequestResult->{ $OID_EnvMonVoltageStatusEntry . ".2."
                          . $VoltageId };
                }
                else {
                    $SNMPSession->close();
                    $_[1] =
                      "Error recovering voltage description with id $VoltageId";
                    return UNKNOWN;
                }
                for ( my $i = 0 ; $i <= $#CriticalStates ; $i++ ) {
                    if ( $VoltageState eq $CriticalStates[$i] ) {
                        $CriticalOutput .= "Sensor '$VoltageDesc'";
                        if (
                            $RequestResult->{
                                    $OID_EnvMonVoltageStatusEntry . ".3."
                                  . $VoltageId
                            }
                          )
                        {    #value defined
                            $CriticalOutput .=
                              "with value = "
                              . $RequestResult->{ $OID_EnvMonVoltageStatusEntry
                                  . ".3."
                                  . $VoltageId }
                              . "mV";
                        }
                        $CriticalOutput .=
                            ' is in '
                          . ENVMON_STATES->[$VoltageState]
                          . ' state ('
                          . ENVMON_STATE_DESC->[$VoltageState] . '); ';
                        last;
                    }
                }
                if ( $CriticalOutput eq '' ) {
                    for ( my $i = 0 ; $i <= $#WarningStates ; $i++ ) {
                        if ( $VoltageState eq $WarningStates[$i] ) {
                            $WarningOutput .= "Sensor '$VoltageDesc'";
                            if (
                                $RequestResult->{
                                        $OID_EnvMonVoltageStatusEntry . ".3."
                                      . $VoltageId
                                }
                              )
                            {    #value defined
                                $WarningOutput .=
                                  "with value = "
                                  . $RequestResult
                                  ->{   $OID_EnvMonVoltageStatusEntry . ".3."
                                      . $VoltageId };
                            }
                            $CriticalOutput .=
                                ' is in '
                              . ENVMON_STATES->[$VoltageState]
                              . ' state ('
                              . ENVMON_STATE_DESC->[$VoltageState] . '); ';
                            last;

                        }

                    }
                }
            }
        }

        # Temperature management
        if ( defined($temperature) ) {
            if ( $temperature eq 'all' ) {    #All temperatures are checked
                @TemperatureIds = @TemperatureIdsPresent;
                if ( $#TemperatureIds eq -1 ) {    #no temperatures present
                    if ( $SomeEnvironmentDefined eq 1 )
                    {    #Environment argument defined by user
                        $SNMPSession->close();
                        $_[1] = "Error. No environmental data for temperatures";
                        return UNKNOWN;
                    }
                }
            }
            else {
                @TemperatureIds = split( /,/, $temperature );
            }
            foreach (@TemperatureIds) {
                my $TemperatureId = $_;
                my $TemperatureState =
                  $RequestResult->{ $OID_EnvMonTemperatureStatusEntry . ".6."
                      . $TemperatureId };
                if ( !defined($TemperatureState) ) {
                    $SNMPSession->close();
                    $_[1] =
                      "Error recovering temperature with id $TemperatureId";
                    return UNKNOWN;
                }
                my $TemperatureDesc;
                if (
                    defined(
                        $RequestResult->{
                                $OID_EnvMonTemperatureStatusEntry . ".2."
                              . $TemperatureId
                        }
                    )
                  )
                {    #description defined
                    $TemperatureDesc =
                      $RequestResult->{ $OID_EnvMonTemperatureStatusEntry
                          . ".2."
                          . $TemperatureId };
                }
                else {
                    $SNMPSession->close();
                    $_[1] =
"Error recovering temperature description with id $TemperatureId";
                    return UNKNOWN;
                }
                for ( my $i = 0 ; $i <= $#CriticalStates ; $i++ ) {
                    if ( $TemperatureState eq $CriticalStates[$i] ) {
                        $CriticalOutput .= "Sensor '$TemperatureDesc'";
                        if (
                            $RequestResult->{
                                    $OID_EnvMonTemperatureStatusEntry . ".3."
                                  . $TemperatureId
                            }
                          )
                        {    #value defined
                            $CriticalOutput .=
                              "with value = "
                              . $RequestResult
                              ->{   $OID_EnvMonTemperatureStatusEntry . ".3."
                                  . $TemperatureId };
                        }
                        $CriticalOutput .=
                            ' is in '
                          . ENVMON_STATES->[$TemperatureState]
                          . ' state ('
                          . ENVMON_STATE_DESC->[$TemperatureState] . '); ';
                        last;
                    }
                }
                if ( $CriticalOutput eq '' ) {
                    for ( my $i = 0 ; $i <= $#WarningStates ; $i++ ) {
                        if ( $TemperatureState eq $WarningStates[$i] ) {
                            $WarningOutput .= "Sensor '$TemperatureDesc'";
                            if (
                                $RequestResult->{
                                    $OID_EnvMonTemperatureStatusEntry . ".3."
                                      . $TemperatureId
                                }
                              )
                            {    #value defined
                                $WarningOutput .=
                                  "with value = "
                                  . $RequestResult
                                  ->{ $OID_EnvMonTemperatureStatusEntry . ".3."
                                      . $TemperatureId }
                                  . "Celsius";
                            }
                            $WarningOutput .=
                                ' is in '
                              . ENVMON_STATES->[$TemperatureState]
                              . ' state ('
                              . ENVMON_STATE_DESC->[$TemperatureState] . '); ';
                            last;

                        }

                    }
                }
            }

        }

        # Fan management
        if ( defined($fan) ) {

            #my $TemperatureValue;
            my @FanIds;
            if ( $fan eq 'all' ) {    #All fans are checked
                @FanIds = @FanIdsPresent;
                if ( $#FanIds eq -1 ) {    #no fans present
                    if ( $SomeEnvironmentDefined eq 1 )
                    {                      #Environment argument defined by user
                        $SNMPSession->close();
                        $_[1] = "Error. No environmental data for fans";
                        return UNKNOWN;
                    }
                }
            }
            else {
                @FanIds = split( /,/, $fan );
            }
            foreach (@FanIds) {
                my $FanId = $_;
                my $FanState =
                  $RequestResult->{ $OID_EnvMonFanStatusEntry . ".3."
                      . $FanId };
                if ( !defined($FanState) ) {
                    $SNMPSession->close();
                    $_[1] = "Error recovering fan with id $FanId";
                    return UNKNOWN;
                }
                my $FanDesc;
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonFanStatusEntry . ".2." . $FanId
                        }
                    )
                  )
                {    #description defined
                    $FanDesc =
                      $RequestResult->{ $OID_EnvMonFanStatusEntry . ".2."
                          . $FanId };
                }
                else {
                    $SNMPSession->close();
                    $_[1] = "Error recovering fan description with id $FanId";
                    return UNKNOWN;
                }
                for ( my $i = 0 ; $i <= $#CriticalStates ; $i++ ) {
                    if ( $FanState eq $CriticalStates[$i] ) {
                        $CriticalOutput .=
                            ' is in '
                          . ENVMON_STATES->[$FanState]
                          . ' state ('
                          . ENVMON_STATE_DESC->[$FanState] . '); ';
                        last;
                    }
                }
                if ( $CriticalOutput eq '' ) {
                    for ( my $i = 0 ; $i <= $#WarningStates ; $i++ ) {
                        if ( $FanState eq $WarningStates[$i] ) {
                            $WarningOutput .=
                                ' is in '
                              . ENVMON_STATES->[$FanState]
                              . ' state ('
                              . ENVMON_STATE_DESC->[$FanState] . '); ';
                            last;
                        }
                    }
                }
            }
        }

        # Power supply management
        if ( defined($supply) ) {
            my @SupplyIds;
            if ( $supply eq 'all' ) {    #All supply are checked
                @SupplyIds = @SupplyIdsPresent;
                if ( $#SupplyIds eq -1 ) {    #no supplies present
                    if ( $SomeEnvironmentDefined eq 1 )
                    {    #Environment argument defined by user
                        $SNMPSession->close();
                        $_[1] = "Error. No environmental data for supplies";
                        return UNKNOWN;
                    }
                }
            }
            else {
                @SupplyIds = split( /,/, $supply );
            }
            foreach (@SupplyIds) {
                my $SupplyId = $_;
                my $SupplyState =
                  $RequestResult->{ $OID_EnvMonSupplyStatusEntry . ".3."
                      . $SupplyId };
                if ( !defined($SupplyState) ) {
                    $SNMPSession->close();
                    $_[1] = "Error recovering supply with id $SupplyId";
                    return UNKNOWN;
                }
                my $SupplyDesc;
                if (
                    defined(
                        $RequestResult->{
                            $OID_EnvMonSupplyStatusEntry . ".2." . $SupplyId
                        }
                    )
                  )
                {    #description defined
                    $SupplyDesc =
                      $RequestResult->{ $OID_EnvMonSupplyStatusEntry . ".2."
                          . $SupplyId };
                }
                else {
                    $SNMPSession->close();
                    $_[1] =
                      "Error recovering supply description with id $SupplyId";
                    return UNKNOWN;
                }
                for ( my $i = 0 ; $i <= $#CriticalStates ; $i++ ) {
                    if ( $SupplyState eq $CriticalStates[$i] ) {
                        $CriticalOutput .=
                            ' is in '
                          . ENVMON_STATES->[$SupplyState]
                          . ' state ('
                          . ENVMON_STATE_DESC->[$SupplyState] . '); ';
                        last;
                    }
                }
                if ( $CriticalOutput eq '' ) {
                    for ( my $i = 0 ; $i <= $#WarningStates ; $i++ ) {
                        if ( $SupplyState eq $WarningStates[$i] ) {
                            $WarningOutput .=
                                ' is in '
                              . ENVMON_STATES->[$SupplyState]
                              . ' state ('
                              . ENVMON_STATE_DESC->[$SupplyState] . '); ';
                            last;
                        }
                    }
                }
            }
        }

        if ( $CriticalOutput ne '' ) {
            $PluginOutput      = $CriticalOutput;
            $PluginReturnValue = CRITICAL;
        }
        elsif ( $WarningOutput ne '' ) {
            $PluginOutput      = $WarningOutput;
            $PluginReturnValue = WARNING;
        }
        else {
            $PluginOutput =
              "Checked environmental sensor(s) return OK state(s)";
            $PluginReturnValue = OK;
        }

        #Perfdata
        if ( $#VoltageIds >= 0 || $#TemperatureIds >= 0 ) {
            my $VoltageId;
            my $VoltageValue;
            my $VoltageDesc;
            my $TemperatureId;
            my $TemperatureValue;
            my $TemperatureDesc;
            $PerformanceData = "";

            if ( $#VoltageIds >= 0 ) {
                foreach $VoltageId (@VoltageIds) {
                    if (
                        defined(
                            $RequestResult->{
                                "$OID_EnvMonVoltageStatusEntry.3.$VoltageId"}
                        )
                      )
                    {
                        $VoltageValue = $RequestResult->{
                            "$OID_EnvMonVoltageStatusEntry.3.$VoltageId"};
                        $VoltageValue =
                          $VoltageValue / 1000;    #Normalice value (mV -> V)
                        if (
                            defined $RequestResult->{
                                "$OID_EnvMonVoltageStatusEntry.2.$VoltageId"}
                          )
                        {
                            $PerformanceData .= " '"
                              . $RequestResult->{
                                "$OID_EnvMonVoltageStatusEntry.2.$VoltageId"}
                              . "'=${TemperatureValue}Celsius;;;"
                              . $RequestResult->{
                                "$OID_EnvMonVoltageStatusEntry.4.$VoltageId"}
                              . ';';
                        }
                        else {
                            $PerformanceData .=
                              " 'Voltage sensor $VoltageId'=${VoltageValue}V;;;"
                              . $RequestResult->{
                                "$OID_EnvMonVoltageStatusEntry.4.$VoltageId"}
                              . ';';
                        }
                    }
                }
            }

            if ( $#TemperatureIds >= 0 ) {
                foreach $TemperatureId (@TemperatureIds) {
                    if (
                        defined(
                            $RequestResult->{
"$OID_EnvMonTemperatureStatusEntry.3.$TemperatureId"
                            }
                        )
                      )
                    {
                        $TemperatureValue =
                          $RequestResult->{
                            "$OID_EnvMonTemperatureStatusEntry.3.$TemperatureId"
                          };
                        if (
                            defined $RequestResult->{
"$OID_EnvMonTemperatureStatusEntry.2.$TemperatureId"
                            }
                          )
                        {
                            $PerformanceData .= " '"
                              . $RequestResult->{
"$OID_EnvMonTemperatureStatusEntry.2.$TemperatureId"
                              }
                              . "'=${TemperatureValue}Celsius;;;;"
                              . $RequestResult->{
"$OID_EnvMonTemperatureStatusEntry.4.$TemperatureId"
                              };
                        }
                        else {
                            $PerformanceData .=
" 'Temperature sensor $TemperatureId'=$TemperatureValue"
                              . "Celsius;;;;"
                              . $RequestResult->{
"$OID_EnvMonTemperatureStatusEntry.4.$TemperatureId"
                              };
                        }
                    }
                }
            }
            $PluginOutput .= " |$PerformanceData";
        }

    }
    else {
        # Error starting SNMP session;
        $PluginOutput = "Error '$SNMPError' starting session";
    }

    #Return result
    $_[1] = $PluginOutput;
    return $PluginReturnValue;
}
