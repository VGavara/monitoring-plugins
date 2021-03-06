#!/usr/bin/perl -w

# check_cisco_fru_module Nagios-compatible plugin
#
# Checks the operational state of the modules on a
# CISCO-ENTITY-FRU-CONTROL-MIB  compliant device
#
# This check plugin is free software, and comes with ABSOLUTELY
# NO WARRANTY. It may be used, redistributed and/or modified under
# the terms of the MIT General Public License (see
# https://opensource.org/licenses/MIT).
#
# HISTORY
#
# v.0.4b: Improved plugin output in test and check mode; coding style changes.
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

#sub PerformCheck ();

# CONSTANT DEFINITION

use constant FRU_CEFSMODULEOPERSTATUS => '1.3.6.1.4.1.9.9.117.1.2.1.1.2';
use constant FRU_ENTPHYSICALDESCR     => '1.3.6.1.2.1.47.1.1.1.1.2';

use constant FRU_MODULE_STATUS => [
    '',                       'Unknown',
    'Ok',                     'Disabled',
    'OkButDiagFailed',        'Boot',
    'SelfTest',               'Failed',
    'Missing',                'MismatchWithParent',
    'MismatchConfig',         'DiagFailed',
    'Dormant',                'OutOfServiceAdmin',
    'OutOfServiceEnvTemp',    'PoweredDown',
    'PoweredUp',              'PowerDenied',
    'PowerCycled',            'OkButPowerOverWarning',
    'OkButPowerOverCritical', 'SyncInProgress',
    'Upgrading',              'OkButAuthFailed'
];

use constant FRU_MODULE_STATUS_DESC => [
    '',
    'Module is not in one of other states',
    'Module is operational.',
    'Module is administratively disabled.',
    'Module is operational but there is some diagnostic information available.',
    'Module is currently in the process of bringing up image.'
      . 'After boot, it starts its operational software and transitions '
      . 'to the appropriate state.',
    'Module is performing selfTest.',
    'Module has failed due to some condition not stated above.',
    'Module has been provisioned, but it is missing',
    'Module is not compatible with parent entity.'
      . 'Module has not been provisioned and wrong type of module is plugged in.'
      . 'This state can be cleared by plugging in the appropriate module.',
'Module is not compatible with the current configuration. Module was correctly'
      . 'provisioned earlier, however the module was replaced by an incompatible module.'
      . 'This state can be resolved by clearing the configuration, '
      . 'or replacing with the appropriate module.',
    'Module diagnostic test failed due to some hardware failure.',
'Module is waiting for an external or internal event to become operational.',
    'Module is administratively set to be powered on but out of service.',
    'Module is powered on but out of service, due to '
      . 'environmental temperature problem. An out-o-service module consumes less power'
      . 'thus will cool down the board.',
    'Module is in powered down state.',
    'Module is in powered up state.',
'System does not have enough power in power budget to power on this module.',
    'Module is being power cycled.',
    'Module is drawing more power than allocated to this module.'
      . 'The module is still operational but may go into a failure state.'
      . 'This state may be caused by misconfiguration of'
      . 'power requirements (especially for inline power).',
    'Module is drawing more power than this module is designed to handle.'
      . 'The module is still operational but may go into a failure state and could '
      . 'potentially take the system down. This state may be caused by gross misconfiguration '
      . 'of power requirements (especially for inline power).',
    'Synchronization in progress.'
      . 'In a high availability system there will be 2 control modules, active and standby.'
      . 'This transitional state specifies the synchronization of data between the'
      . 'active and standby modules.',
    'Module is upgrading.',
    'Module is operational but did not pass hardware integrity verification.'
];

use constant SNMP_MAX_MSG_SIZE => 5120;

use constant MODE_TEST  => 1;
use constant MODE_CHECK => 2;

use constant NAME    => 'check_cisco_fru_module';
use constant VERSION => '0.4b';
use constant USAGE =>
"Usage:\ncheck_cisco_fru_module -H <hostname> [-e <module id list>] [-w <warning list> -c <critical list>]\n"
  . "\t\t[-C <SNMP Community>]  [-E <SNMP Version>] [-P <SNMP port>]\n"
  . "\t\t[-V <version>]\n";
use constant BLURB =>
  "This plugin checks the operational state of the modules\n"
  . "on a CISCO-ENTITY-FRU-CONTROL-MIB compliant device.";
use constant LICENSE =>
  "This check plugin is free software, and comes with ABSOLUTELY\n"
  . "no WARRANTY. It may be used, redistributed and/or modified under\n"
  . "the terms of the MIT General Public License\n"
  . "(see https://opensource.org/licenses/MIT).\n";
use constant EXAMPLE => "\n\n"
  . "Example:\n" . "\n"
  . "check_cisco_fru_module -H 192.168.0.12\n" . "\n"
  . "Test Mode that checks the compatibility of the plugin on a host with address 192.168.0.12\n"
  . "using SNMP protocol version 1 and 'public' as community\n"
  . "Plugin returns OK if it is a CISCO-ENTITY-FRU-CONTROL-MIB compliant device and can recover modules data. Also, a list of all modules\n"
  . "with id, status and description is returned. If it is not compatible returns UNKNOWN\n"
  . "\n"
  . "check_cisco_fru_module -H 192.168.0.12 -e 275,276 -w 4,19,23 -c 7,8,20\n"
  . "\n"
  . "Checks, on a CISCO-ENTITY-FRU-CONTROL-MIB compliant device with IP address 192.168.0.12,\n"
  . "if any of the modules passed through their id with the -e argument\n"
  . "are in any of the states passed in -w and -c argument.\n"
  . "It returns CRITICAL if any module (275 or 276 module id) has a state with id 7, 8 or 20, \n"
  . "WARNING if any module has a state with id 4,19 or 23, and in other case returns OK\n"
  . "The operational id state of a module is:\n"
  . "\t1:unknown\n"
  . "\t2:ok\n"
  . "\t3:disabled\n"
  . "\t4:okButDiagFailed\n"
  . "\t5:boot\n"
  . "\t6:selfTest\n"
  . "\t7:failed\n"
  . "\t8:missing\n"
  . "\t9:mismatchWithParent\n"
  . "\t10:mismatchConfig\n"
  .

  "\t11:diagFailed\n"
  . "\t12:dormant\n"
  . "\t13:outOfServiceAdmin\n"
  . "\t14:outOfServiceEnvTemp\n"
  . "\t15:poweredDown\n"
  . "\t16:poweredUp\n"
  . "\t17:powerDenied\n"
  . "\t18:powerCycled\n"
  . "\t19:okButPowerOverWarning\n"
  . "\t20:okButPowerOverCritical\n"
  . "\t21:syncInProgress\n"
  . "\t22:upgrading\n"
  . "\t23:okButAuthFailed";

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
        help     => "Module id list <idModule>(,<idModule>)*",
        required => 0
    );

    # Add argument warning
    $Nagios->add_arg(
        spec => 'warning|w=s',
        help =>
          "Warning thresholds in the format <idModuleState>(,<idModuleState>)*",
        required => 0
    );

    # Add argument critical
    $Nagios->add_arg(
        spec => 'critical|c=s',
        help =>
          "Critical threshold in the format <idModuleState>(,<idModuleState>)*",
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
        && ( !defined $Nagios->opts->critical ) )
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
                    $_[1] = "Invalid warning state id number";
                    return 0;
                }
            }
        }
        else {
            $_[1] = "Invalid warning Type expression";
            return 0;
        }

        #Check Critical Types Number
        if ( $Nagios->opts->critical =~ /^\d+(,\d+)*$/ ) {   #One or more digits
            @CriticalTypes = split( /,/, $Nagios->opts->critical );
            foreach $CriticalType (@CriticalTypes) {
                if ( $CriticalType < 0 || $CriticalType > 65535 ) {
                    $_[1] = "Invalid critical Type number";
                    return 0;
                }
            }
        }
        else {
            $_[1] = "Invalid critical Type expression";
            return 0;
        }
        if ( $Nagios->opts->ids !~ /^\d+(,\d+)*$/ ) {
            $_[1] = "Invalid module ids expression";
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

# Checks if host supports modules data on CISCO-ENTITY-FRU-CONTROL-MIB .
# If OK, it returns info about modules
# Input: Nagios-compatible plugin object
# Output: Test output string
# Return value: OK if test passed, UNKNOWN if not.

sub TestHost() {
    my $SNMPSession;
    my $SNMPError;
    my $Output = "";
    my $PluginReturnValue;

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
          $SNMPSession->get_entries( -columns => [FRU_CEFSMODULEOPERSTATUS] );
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
        $Output = "CISCO MODULES DATA\n";
        foreach $Oid ( keys %{$RequestResultIndex} ) {
            $id     = ( split( /\./, $Oid ) )[-1];
            $status = FRU_MODULE_STATUS->[ $RequestResultIndex->{$Oid} ];
            $desc   = $RequestResultDesc->{ FRU_ENTPHYSICALDESCR . ".$id" }
              if defined $RequestResultDesc->{ FRU_ENTPHYSICALDESCR . ".$id" };
            $Output .=
                "Module id: $id\tModule status: "
              . $RequestResultIndex->{$Oid}
              . " ($status)\tModule description: $desc \n";
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

    my @ModuleIds;
    my $ModuleId;
    my $ModuleStatus;

    my @CriticalStates = split( /,/, $Nagios->opts->critical );
    my @WarningStates  = split( /,/, $Nagios->opts->warning );
    my $CriticalOutput = "";
    my $WarningOutput  = "";

    my $PluginOutput;
    my $PluginReturnValue = UNKNOWN;

    my $RequestResult;
    my $ModuleName;

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
        @ModuleIds = split( /,/, $Nagios->opts->ids );
        foreach $ModuleId (@ModuleIds) {
            $RequestResult = $SNMPSession->get_request(
                -varbindlist => [ FRU_CEFSMODULEOPERSTATUS . ".$ModuleId" ] );
            if ( !defined($RequestResult) ) {
                $SNMPSession->close();
                $_[1] = "No module with id $ModuleId found";
                return UNKNOWN;
            }

            $ModuleStatus =
              $$RequestResult{ FRU_CEFSMODULEOPERSTATUS . ".$ModuleId" };
            if ( $ModuleStatus !~ /^\d+$/ ) {
                $SNMPSession->close();
                $_[1] =
                  "No such instance ($ModuleId) currently exists at this OID";
                return UNKNOWN;
            }

            $RequestResult = $SNMPSession->get_request(
                -varbindlist => [ FRU_ENTPHYSICALDESCR . ".$ModuleId" ] );
            if (
                ( !defined($RequestResult) )
                || ( $$RequestResult{ FRU_ENTPHYSICALDESCR . ".$ModuleId" } =~
                    m/No Such/ )
              )
            {
                $SNMPSession->close();
                $_[1] = "Error recovering module name with id $ModuleId";
                return UNKNOWN;
            }

            $ModuleName =
              $$RequestResult{ FRU_ENTPHYSICALDESCR . ".$ModuleId" };
            for ( my $i = 0 ; $i <= $#CriticalStates ; $i++ ) {
                if ( $ModuleStatus == $CriticalStates[$i] ) {
                    $CriticalOutput .= "$ModuleName: "
                      . FRU_MODULE_STATUS_DESC->[$ModuleStatus] . '; ';
                    last;
                }
            }
            if ( $CriticalOutput eq '' ) {    #No critical state
                for ( my $i = 0 ; $i <= $#WarningStates ; $i++ ) {
                    if ( $ModuleStatus == $WarningStates[$i] ) {
                        $WarningOutput .= "$ModuleName: "
                          . FRU_MODULE_STATUS_DESC->[$ModuleStatus] . '; ';
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
                if ( @ModuleIds == 1 ) {
                    $PluginOutput = "Module '$ModuleName' status is "
                      . FRU_MODULE_STATUS->[$ModuleStatus];
                }
                else {
                    $PluginOutput = "All checked modules are OK.";
                }
            }
        }

        #Close Session
        $SNMPSession->close();
    }

    #Return result
    $_[1] = $PluginOutput;
    return $PluginReturnValue;
}
