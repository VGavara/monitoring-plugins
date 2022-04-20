#!/usr/bin/perl -w

# check_cisco_cpu Nagios-compatible plugin
# Checks the CPU load (in percent) on a CISCO-PROCESS-MIB
# or OLD-CISCO-CPU-MIB SNMP compliant device.
# Type check_cisco_cpu --help for getting more info and examples.
#
# This check plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
# It may be used, redistributed and/or modified under the terms of the MIT
# General Public Licence (see https://opensource.org/licenses/MIT).
#
# HISTORY
#
# V04b: Support for cpmCPUTotal5sec, cpmCPUTotal1min and cpmCPUTotal5min OIDs,
#       deprecated by Cisco but still present in some devices
# V03b: Fixed bug when showing the CPU description
#       Support to OLD-CISCO-CPU-MIB devices

# MODULE DECLARATION

use strict;

use Monitoring::Plugin;
use Net::SNMP qw(SNMP_VERSION_2C);

# FUNCTION DECLARATION

sub CreateNagiosManager ();
sub ManageArguments ();
sub PerformOldCPUMibCheck ();
sub PerformProcessMibCheck ();

# CONSTANT DEFINITION

use constant NOSUCHOBJECT   => 'noSuchObject';
use constant NOSUCHINSTANCE => 'noSuchInstance';

use constant OLD_CISCO_CPU_MIB      => '.1.3.6.1.4.1.9.2.1';
use constant CISCO_PROCESS_MIB      => '.1.3.6.1.4.1.9.9.109';
use constant CISCO_ENTPHYSICALDESCR => '1.3.6.1.2.1.47.1.1.1.1.2';

use constant MODE_TEST  => 1;
use constant MODE_CHECK => 2;

use constant NAME    => 'check_cisco_cpu';
use constant VERSION => '0.4b';
use constant USAGE => "Usage:\n"
  . "check_cisco_cpu -H <hostname> -r <Resource id> [-i <interval>] [-d] -w <warning value> -c <critical value>\n"
  . "\t\t[-C <SNMP Community>] [-e <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]\n"
  . "\t\t[-U <SNMP authentication user> -a <SNMP authentication protocol> -A <SNMP authentication pass phrase>\n"
  . "\t\t[-x <SNMP privacy protocol> -X <SNMP privacy pass phrase>] ]\n"
  . "\t\t[-V <version>]\n";
use constant BLURB =>
"This plugin checks the CPU load on a on a Cisco CISCO-PROCESS-MIB or OLD-CISCO-CPU-MIB SNMP compliant device.\n";
use constant LICENSE =>
  "This check plugin is free software, and comes with ABSOLUTELY NO WARRANTY\n"
  . "It may be used, redistributed and/or modified under the terms of the MIT\n"
  . "General Public Licence (see https://opensource.org/licenses/MIT).\n";
use constant EXAMPLE => "\n\n"
  . "Example:\n" . "\n"
  . "check_cisco_cpu -H 192.168.0.1 -r 1 -i 1m -w 80 -c 95\n" . "\n"
  . "Checks the last minute CPU load on a CPU module with id 1 on\n"
  . "a CISCO-PROCESS-MIB SNMP compliant device \n"
  . "using 'public' as community string and default port 161.\n"
  . "Plugin returns WARNING if last minute CPU load is above 80%,\n"
  . "or CRITICAL if last minute CPU load is above 95%.\n"
  . "In other case it returns OK if check has been successfully performed.\n"
  . "\n"
  . "check_cisco_cpu -H 192.168.0.1 -E 3 -U admin -a MD5 -A authpass -x DES -X encryptpass -i 5m -w 85 -c 95\n"
  . "\n"
  . "Checks the last five minutes CPU load on a OLD-CISCO-CPU-MIB SNMP compliant device\n"
  . "using SNMP v3 with default port 161, authentication user 'admin',\n"
  . "authentication protocol 'MD5', authenticacion pass phrase 'authpass',\n"
  . "encryption protocol DES and encryption pass phrase 'encryptpass' .\n"
  . "Plugin returns WARNING if last five minutes CPU load is above 85%,\n"
  . "or CRITICAL if last five minutes CPU load is above 95%.\n"
  . "In other case it returns OK if check has been successfully performed.\n";

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
    if ( &ManageArguments( $Nagios, $Error, $PluginMode ) ) {

        # Argument checking passed
        if ( $PluginMode == MODE_TEST ) {
            $PluginReturnValue = &TestHost( $Nagios, $PluginOutput );
            $PluginOutput      = "TEST MODE\n\n" . $PluginOutput;
        }
        else {
            if ( defined $Nagios->opts->resourceid ) {

                # Resource ID defined: checking a CISCO-PROCESS-MIB device
                $PluginReturnValue =
                  &PerformProcessMibCheck( $Nagios, $PluginOutput );
            }
            else {
                # Checking a OLD-CISCO-CPU-MIB device
                $PluginReturnValue =
                  &PerformOldCPUMibCheck( $Nagios, $PluginOutput );
            }
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

    # Add argument interval
    $Nagios->add_arg(
        spec => 'interval|i=s',
        help =>
'CPU interval: 5s (last 5 seconds, only available for CISCO-PROCESS-MIB devices), 1m (last 1 minute, default), 5m (last 5 minutes)',
        default  => '1m',
        required => 0
    );

    # Add argument resource
    $Nagios->add_arg(
        spec => 'resourceid|r=i',
        help =>
'CPU id (for CISCO-PROCESS-MIB compliant devices). Omit this argument for checking OLD-CISCO-CPU-MIB devices.',
        required => 0
    );

    # Add argument resource
    $Nagios->add_arg(
        spec => 'deprecated|d',
        help =>
'Use deprecated CISCO-PROCESS-MIB cpmCPUTotal5sec, cpmCPUTotal1min and cpmCPUTotal5min OIDs.',
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

    # Add argument snmp user
    $Nagios->add_arg(
        spec     => 'snmpuser|U=s',
        help     => 'SNMP username (version 3)',
        required => 0
    );

    # Add argument snmp authentication protocol (version 3)
    $Nagios->add_arg(
        spec     => 'snmpauthprotocol|a=s',
        help     => 'SNMP authentication protocol (version 3)',
        required => 0
    );

    # Add argument snmp authentication pass phrase (version 3)
    $Nagios->add_arg(
        spec     => 'snmpauthpassword|A=s',
        help     => 'SNMP authentication pass phrase (version 3)',
        required => 0
    );

    # Add argument snmp encryption protocol (version 3)
    $Nagios->add_arg(
        spec     => 'snmpprivprotocol|x=s',
        help     => 'SNMP encryption protocol (version 3)',
        required => 0
    );

    # Add argument snmp privace pass phrase (version 3)
    $Nagios->add_arg(
        spec     => 'snmpprivpassword|X=s',
        help     => 'SNMP privace pass phrase (version 3)',
        required => 0
    );

    # Add argument warning
    $Nagios->add_arg(
        spec     => 'warning|w=i',
        help     => "Warning threshold",
        required => 0
    );

    # Add argument critical
    $Nagios->add_arg(
        spec     => 'critical|c=i',
        help     => "Critical threshold",
        required => 0
    );

    # Return value
    return $Nagios;
}

# Checks argument values and sets some default values
# Input: Nagios-compatible plugin object
# Output: Error description string
# Return value: True if arguments ok, false if not

sub ManageArguments() {
    my $Nagios = $_[0];
    my @IfRange;
    my $ArgOK;
    my $ThresholdsFormat;

    # SNMP v3 auth
    if (   defined( $Nagios->opts->snmpuser )
        && defined( $Nagios->opts->snmpauthprotocol )
        && defined( $Nagios->opts->snmpauthpassword ) )
    {
        # Encryption
        if ( defined( $Nagios->opts->snmpprivprotocol )
            && !defined( $Nagios->opts->snmpprivpassword ) )
        {
            $_[1] =
"SNMP error. If privace protocol is defined , privace pass phrase must be defined.";
            return 0;
        }
        elsif ( !defined( $Nagios->opts->snmpprivprotocol )
            && defined( $Nagios->opts->snmpprivpassword ) )
        {
            $_[1] =
"SNMP error. If privace pass phrase is defined , privace protocol must be defined.";
            return 0;
        }
    }
    else {
        if (   defined( $Nagios->opts->snmpuser )
            || defined( $Nagios->opts->snmpauthprotocol )
            || defined( $Nagios->opts->snmpauthpassword ) )
        {
            $_[1] =
"SNMP error. If authenticacion is defined ,authentication user, authenticacion protocol and authentication pass phrase must be defined.";
            return 0;
        }
    }

    # Check if agent port number is > 0
    if ( $Nagios->opts->port <= 0 ) {
        $_[1] = "Invalid SNMP agent port: must be greater than zero";
        return 0;
    }

    # Check interval value
    if (   $Nagios->opts->interval ne '5s'
        && $Nagios->opts->interval ne '1m'
        && $Nagios->opts->interval ne '5m' )
    {
        $_[1] =
            'Invalid interval value: '
          . $Nagios->opts->interval
          . ". Valid interval values are 5s (for CISCO-PROCESS-MIB devices), 1m and 5m.";
        return 0;
    }
    elsif ( $Nagios->opts->interval eq '5s'
        && !defined $Nagios->opts->resourceid )
    {
        $_[1] =
            'Invalid interval value: '
          . $Nagios->opts->interval
          . ". Valid interval values for OLD-CISCO-CPU-MIB devices are 1m and 5m.";
        return 0;
    }

    # Check plugin test mode
    if (   defined( $Nagios->opts->warning )
        && defined( $Nagios->opts->critical ) )
    {
        $_[2] = MODE_CHECK;
    }
    else {
        if (   !defined( $Nagios->opts->warning )
            && !defined( $Nagios->opts->critical ) )
        {
            $_[2] = MODE_TEST;

        }
        else {
            $_[1] =
"Invalid argument set. You must define, at least, warning and critical arguments in check mode or none of these in test mode.";
            return 0;
        }
    }

    return 1;
}

# Checks if host supports CISCO-PROCESS-MIB related info.
# If true, it returns info about environmental sensors
# Input: Nagios-compatible plugin object
# Output: Test output string
# Return value: OK if test passed, UNKNOWN if not.

sub TestHost() {
    my $SNMPSession;
    my $SNMPError;
    my $Output = "";
    my $PluginReturnValue;
    my $OID_occAvgBusy1              = OLD_CISCO_CPU_MIB . '.57.0';
    my $OID_occAvgBusy5              = OLD_CISCO_CPU_MIB . '.58.0';
    my $OID_cpmCPUTotalPhysicalIndex = CISCO_PROCESS_MIB . '.1.1.1.1.2';
    my $OID_cpmCPUTotalEntry         = CISCO_PROCESS_MIB . '.1.1.1.1';
    my $OID_cpmCPUTotal5sec          = $OID_cpmCPUTotalEntry . '.3.';
    my $OID_cpmCPUTotal1min          = $OID_cpmCPUTotalEntry . '.4.';
    my $OID_cpmCPUTotal5min          = $OID_cpmCPUTotalEntry . '.5.';
    my $OID_cpmCPUTotal5secRev       = $OID_cpmCPUTotalEntry . '.6.';
    my $OID_cpmCPUTotal1minRev       = $OID_cpmCPUTotalEntry . '.7.';
    my $OID_cpmCPUTotal5minRev       = $OID_cpmCPUTotalEntry . '.8.';

    if ( defined( $Nagios->opts->snmpauthprotocol ) ) {

        # SNMP v3
        if ( defined( $Nagios->opts->snmpprivprotocol ) ) {

            # SNMP v3 with encryption
            ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
                -hostname     => $Nagios->opts->hostname,
                -version      => '3',
                -port         => $Nagios->opts->port,
                -username     => $Nagios->opts->snmpuser,
                -authpassword => $Nagios->opts->snmpauthpassword,
                -authprotocol => $Nagios->opts->snmpauthprotocol,
                -privpassword => $Nagios->opts->snmpprivpassword,
                -privprotocol => $Nagios->opts->snmpprivprotocol,
                -timeout      => $Nagios->opts->timeout
            );
        }
        else {
            # SNMP v3 without encryption
            ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
                -hostname     => $Nagios->opts->hostname,
                -version      => '3',
                -port         => $Nagios->opts->port,
                -username     => $Nagios->opts->snmpuser,
                -authpassword => $Nagios->opts->snmpauthpassword,
                -authprotocol => $Nagios->opts->snmpauthprotocol,
                -timeout      => $Nagios->opts->timeout
            );
        }
    }
    else {
        # SNMP v1 or v2c
        ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
            -hostname  => $Nagios->opts->hostname,
            -community => $Nagios->opts->community,
            -version   => $Nagios->opts->snmpver,
            -port      => $Nagios->opts->port,
            -timeout   => $Nagios->opts->timeout
        );
    }

    if ( defined($SNMPSession) ) {
        my $RequestResult;

        # Try to recover CPU via OLD_CISCO_CPU_MIB
        $RequestResult = $SNMPSession->get_request(
            -varbindlist => [ $OID_occAvgBusy1, $OID_occAvgBusy5 ] );
        if (
            defined $RequestResult
            && (   $RequestResult->{$OID_occAvgBusy1} ne NOSUCHOBJECT
                || $RequestResult->{$OID_occAvgBusy5} ne NOSUCHOBJECT )
          )
        {
            $Output =
                "CISCO CPU DATA (from OLD_CISCO_CPU_MIB)\n"
              . 'CPU avgBusy1: '
              . ( $RequestResult->{$OID_occAvgBusy1} eq NOSUCHOBJECT ? '-'
                : $RequestResult->{$OID_occAvgBusy1} )
              . "\t"
              . 'CPU avgBusy5: '
              . ( $RequestResult->{$OID_occAvgBusy5} eq NOSUCHOBJECT ? '-'
                : $RequestResult->{$OID_occAvgBusy5} )
              . "\n";
        }
        else {
            # Try to recover CPU via CISCO_PROCESS_MIB
            my $RequestResultIndex;
            my $RequestResultDesc;

            $RequestResult =
              $SNMPSession->get_entries( -columns => [$OID_cpmCPUTotalEntry] );
            $RequestResultIndex = $SNMPSession->get_entries(
                -columns => [$OID_cpmCPUTotalPhysicalIndex] );

            $RequestResultDesc =
              $SNMPSession->get_entries( -columns => [CISCO_ENTPHYSICALDESCR] );
            if ( !defined($RequestResult) && !defined($RequestResultIndex) ) {
                $SNMPError = $SNMPSession->error();
                if ( defined($SNMPError) && ( $SNMPError ne '' ) ) {
                    $_[1] = "SNMP Error: $SNMPError ";
                }
                else {
                    $_[1] = "No CPU data found";
                }
                $SNMPSession->close();
                return UNKNOWN;
            }

            my $id;
            my $entId;
            my $Oid;
            my $status;
            my $desc = "";
            $Output = "CISCO CPU DATA (from CISCO_PROCESS_MIB)\n";

            foreach $Oid ( keys %{$RequestResultIndex} ) {
                $id    = ( split( /\./, $Oid ) )[-1];
                $entId = $RequestResultIndex->{$Oid};
                $desc =
                  $RequestResultDesc->{ CISCO_ENTPHYSICALDESCR . ".$entId" }
                  if defined $RequestResultDesc->{ CISCO_ENTPHYSICALDESCR
                      . ".$entId" };
                $Output .= "CPU id: $id\t" . "CPU description: $desc\t";

                if (   defined $RequestResult->{ $OID_cpmCPUTotal5secRev . $id }
                    && $RequestResult->{ $OID_cpmCPUTotal1minRev . $id }
                    && $RequestResult->{ $OID_cpmCPUTotal5minRev . $id } )
                {
                    $Output .=
                        "CPU Load5sec: "
                      . $RequestResult->{ $OID_cpmCPUTotal5secRev . $id } . "\t"
                      . "CPU Load1min: "
                      . $RequestResult->{ $OID_cpmCPUTotal1minRev . $id } . "\t"
                      . "CPU Load5min: "
                      . $RequestResult->{ $OID_cpmCPUTotal5minRev . $id }
                      . "\n";
                }
                elsif (defined $RequestResult->{ $OID_cpmCPUTotal5sec . $id }
                    && $RequestResult->{ $OID_cpmCPUTotal1min . $id }
                    && $RequestResult->{ $OID_cpmCPUTotal5min . $id } )
                {
                    $Output .=
                        "CPU Load5sec: "
                      . $RequestResult->{ $OID_cpmCPUTotal5sec . $id } . "\t"
                      . "CPU Load1min: "
                      . $RequestResult->{ $OID_cpmCPUTotal1min . $id } . "\t"
                      . "CPU Load5min: "
                      . $RequestResult->{ $OID_cpmCPUTotal5min . $id } . "\t"
                      . "(from depreacted OIDs, use -d option to run script in deprecated mode)\n";
                }
                else {
                    $Output .= "No CPU usage info found\n";
                }
            }
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

# Performs whole check on OLD-CISCO-CPU-MIB devices:
# Input: Nagios-compatible plugin object
# Output: Plugin output string
# Return value: Plugin return value

sub PerformOldCPUMibCheck() {
    my $OID_occAvgBusy1 = OLD_CISCO_CPU_MIB . '.57.0';
    my $OID_occAvgBusy5 = OLD_CISCO_CPU_MIB . '.58.0';
    my $Nagios          = $_[0];

    my $SNMPSession;
    my $SNMPError;
    my @RequestItems;
    my $RequestResult;

    my $value;
    my $Interval;
    my $Variable;

    my $PluginOutput;
    my $PluginReturnValue = UNKNOWN;
    my $PerformanceData;

    if ( defined( $Nagios->opts->snmpauthprotocol ) ) {

        # SNMP v3
        if ( defined( $Nagios->opts->snmpprivprotocol ) ) {

            # SNMP v3 with encryption
            ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
                -hostname     => $Nagios->opts->hostname,
                -version      => '3',
                -port         => $Nagios->opts->port,
                -username     => $Nagios->opts->snmpuser,
                -authpassword => $Nagios->opts->snmpauthpassword,
                -authprotocol => $Nagios->opts->snmpauthprotocol,
                -privpassword => $Nagios->opts->snmpprivpassword,
                -privprotocol => $Nagios->opts->snmpprivprotocol,
                -timeout      => $Nagios->opts->timeout
            );
        }
        else {
            # SNMP v3 without encryption
            ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
                -hostname     => $Nagios->opts->hostname,
                -version      => '3',
                -port         => $Nagios->opts->port,
                -username     => $Nagios->opts->snmpuser,
                -authpassword => $Nagios->opts->snmpauthpassword,
                -authprotocol => $Nagios->opts->snmpauthprotocol,
                -timeout      => $Nagios->opts->timeout
            );
        }
    }
    else {
        # SNMP v1 or v2c
        ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
            -hostname  => $Nagios->opts->hostname,
            -community => $Nagios->opts->community,
            -version   => $Nagios->opts->snmpver,
            -port      => $Nagios->opts->port,
            -timeout   => $Nagios->opts->timeout
        );
    }

    if ( defined($SNMPSession) ) {

        # Get data
        if ( $Nagios->opts->interval eq '1m' ) {
            $RequestResult =
              $SNMPSession->get_request( -varbindlist => [$OID_occAvgBusy1] );
            $value    = $RequestResult->{$OID_occAvgBusy1};
            $Interval = 'Last-minute';
            $Variable = 'avgBusy1';
        }
        elsif ( $Nagios->opts->interval eq '5m' ) {
            $RequestResult =
              $SNMPSession->get_request( -varbindlist => [$OID_occAvgBusy5] );
            $value    = $RequestResult->{$OID_occAvgBusy5};
            $Interval = 'Last-5-minutes';
            $Variable = 'avgBusy5';
        }

        if ( defined $RequestResult ) {

            # Check thresholds and set plugin output
            if ( !defined $value ) {
                $PluginOutput =
                  "CPU interval ($Nagios->{opts}->{interval}) not defined";
            }
            else {
                $PluginReturnValue = $Nagios->check_threshold(
                    check    => $value,
                    warning  => $Nagios->opts->warning,
                    critical => $Nagios->opts->critical
                );

                $PluginOutput =
                  "$Interval average of CPU busy percentage: $value%";
                if ( $PluginReturnValue == CRITICAL ) {
                    $PluginOutput .=
                      " (Critical threshold is $Nagios->{opts}->{critical}%)";
                }
                elsif ( $PluginReturnValue == WARNING ) {
                    $PluginOutput .=
                      " (Warning threshold is $Nagios->{opts}->{warning}%)";
                }

                #Set performance data
                $PerformanceData =
"$Variable=$value%;$Nagios->{opts}->{warning};$Nagios->{opts}->{critical};0;100";
                $PluginOutput .= ' | ' . $PerformanceData;
            }
        }
        else {
            $SNMPError = $SNMPSession->error();
            $PluginOutput =
                "Error '$SNMPError' retrieving info "
              . "from agent $Nagios->{opts}->{hostname}:$Nagios->{opts}->{port} "
              . "using protocol $Nagios->{opts}->{snmpver} ";
        }

        # Close SNMP session
        $SNMPSession->close;
    }
    else {
        $PluginOutput = "Error '$SNMPError' starting session";
    }

    #Return result
    $_[1] = $PluginOutput;
    return $PluginReturnValue;
}

# Performs whole check on CISCO-PROCESS-MIB devices:
# Input: Nagios-compatible plugin object
# Output: Plugin output string
# Return value: Plugin return value

sub PerformProcessMibCheck() {
    my $OID_cpmCPUTotalEntry         = CISCO_PROCESS_MIB . '.1.1.1.1.';
    my $OID_cpmCPUTotalPhysicalIndex = $OID_cpmCPUTotalEntry . '2';
    my $OID_cpmCPUTotal5sec          = $OID_cpmCPUTotalEntry . '3.';
    my $OID_cpmCPUTotal1min          = $OID_cpmCPUTotalEntry . '4.';
    my $OID_cpmCPUTotal5min          = $OID_cpmCPUTotalEntry . '5.';
    my $OID_cpmCPUTotal5secRev       = $OID_cpmCPUTotalEntry . '6.';
    my $OID_cpmCPUTotal1minRev       = $OID_cpmCPUTotalEntry . '7.';
    my $OID_cpmCPUTotal5minRev       = $OID_cpmCPUTotalEntry . '8.';
    my $Nagios                       = $_[0];

    my $SNMPSession;
    my $SNMPError;
    my @RequestItems;
    my $RequestResult;

    my $Interval;
    my $Variable;
    my $value;

    my $PluginOutput;
    my $PluginReturnValue = UNKNOWN;
    my $PerformanceData;

    if ( defined( $Nagios->opts->snmpauthprotocol ) ) {

        # SNMP v3
        if ( defined( $Nagios->opts->snmpprivprotocol ) ) {

            # SNMP v3 with encryption
            ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
                -hostname     => $Nagios->opts->hostname,
                -version      => '3',
                -port         => $Nagios->opts->port,
                -username     => $Nagios->opts->snmpuser,
                -authpassword => $Nagios->opts->snmpauthpassword,
                -authprotocol => $Nagios->opts->snmpauthprotocol,
                -privpassword => $Nagios->opts->snmpprivpassword,
                -privprotocol => $Nagios->opts->snmpprivprotocol,
                -timeout      => $Nagios->opts->timeout
            );
        }
        else {
            # SNMP v3 without encryption
            ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
                -hostname     => $Nagios->opts->hostname,
                -version      => '3',
                -port         => $Nagios->opts->port,
                -username     => $Nagios->opts->snmpuser,
                -authpassword => $Nagios->opts->snmpauthpassword,
                -authprotocol => $Nagios->opts->snmpauthprotocol,
                -timeout      => $Nagios->opts->timeout
            );
        }
    }
    else {
        # SNMP v1 or v2c
        ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
            -hostname  => $Nagios->opts->hostname,
            -community => $Nagios->opts->community,
            -version   => $Nagios->opts->snmpver,
            -port      => $Nagios->opts->port,
            -timeout   => $Nagios->opts->timeout
        );
    }

    if ( defined($SNMPSession) ) {

        # Get data
        push( @RequestItems,
            "$OID_cpmCPUTotalPhysicalIndex.$Nagios->{opts}->{resourceid}" );
        if ( $Nagios->opts->interval eq '5s' ) {
            defined $Nagios->opts->{deprecated}
              ? push( @RequestItems,
                $OID_cpmCPUTotal5sec . $Nagios->opts->resourceid )
              : push( @RequestItems,
                $OID_cpmCPUTotal5secRev . $Nagios->opts->resourceid );
            $Interval = "Last-5-seconds";
            $Variable = "Load5sec";
        }
        elsif ( $Nagios->opts->interval eq '1m' ) {
            defined $Nagios->opts->{deprecated}
              ? push( @RequestItems,
                $OID_cpmCPUTotal1min . $Nagios->opts->resourceid )
              : push( @RequestItems,
                $OID_cpmCPUTotal1minRev . $Nagios->opts->resourceid );
            $Interval = "Last-1-minute";
            $Variable = "Load1min";
        }
        elsif ( $Nagios->opts->interval eq '5m' ) {
            defined $Nagios->opts->{deprecated}
              ? push( @RequestItems,
                $OID_cpmCPUTotal5min . $Nagios->opts->resourceid )
              : push( @RequestItems,
                $OID_cpmCPUTotal5minRev . $Nagios->opts->resourceid );
            $Interval = "Last-5-minutes";
            $Variable = "Load5min";
        }

        if (
            defined(
                $RequestResult =
                  $SNMPSession->get_request( -varbindlist => \@RequestItems )
            )
          )
        {
            # Check thresholds and set plugin output
            my $RequestResultDesc =
              $SNMPSession->get_entries( -columns => [CISCO_ENTPHYSICALDESCR] );

            my $desc = $RequestResultDesc->{
                CISCO_ENTPHYSICALDESCR . '.'
                  . $RequestResult->{
"$OID_cpmCPUTotalPhysicalIndex.$Nagios->{opts}->{resourceid}"
                  }
            };
            $desc = '' if !defined($desc);

            $value = $RequestResult->{ $RequestItems[1] };

            if ( $value eq NOSUCHINSTANCE ) {
                $SNMPSession->close;
                $_[1] =
                    "CPU with id "
                  . $Nagios->opts->resourceid
                  . " doesn't exist.";
                return $PluginReturnValue;
            }
            elsif ( $value eq NOSUCHOBJECT ) {
                $SNMPSession->close;
                $_[1] =
"CPU data not available. Maybe deprecated mode doesn't matching with device?";
                return $PluginReturnValue;
            }

            $PluginReturnValue = $Nagios->check_threshold(
                check    => $value,
                warning  => $Nagios->opts->warning,
                critical => $Nagios->opts->critical
            );

            $PluginOutput = $Interval . ' CPU load (' . $desc . ')';
            if ( $PluginReturnValue == CRITICAL ) {
                $PluginOutput .=
                  " ($value%) is above $Nagios->{opts}->{critical}%.";
            }
            elsif ( $PluginReturnValue == WARNING ) {
                $PluginOutput .=
                  " ($value%) is above $Nagios->{opts}->{warning}%.";
            }
            else {
                $PluginOutput .= " = $value%";
            }

            #Set performance data
            $PerformanceData =
"$Variable=$value%;$Nagios->{opts}->{warning};$Nagios->{opts}->{critical};0;100 ";
            $PluginOutput .= ' | ' . $PerformanceData;
        }
        else {
            $SNMPError = $SNMPSession->error();
            $PluginOutput =
                "Error '$SNMPError' retrieving info "
              . "from agent $Nagios->{opts}->{hostname}:$Nagios->{opts}->{port} "
              . "using protocol $Nagios->{opts}->{snmpver} ";
        }

        # Close SNMP session
        $SNMPSession->close;
    }
    else {
        $PluginOutput = "Error '$SNMPError' starting session";
    }

    #Return result
    $_[1] = $PluginOutput;
    return $PluginReturnValue;
}
