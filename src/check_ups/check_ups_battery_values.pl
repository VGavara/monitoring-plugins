#!/usr/bin/perl -w

# check_ups_battery_values Nagios-compatible plugin
#
# Checks the battery values (as defined in RFC1628)
# on a UPS-MIB SNMP compliant device.
# Type check_packet_throughput --help for getting more info and examples.
#
# This check plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
# It may be used, redistributed and/or modified under the terms of the MIT
# General Public Licence (see https://opensource.org/licenses/MIT).

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

use constant NAME    => 'check_ups_battery_values';
use constant VERSION => '1.0';
use constant USAGE => "Usage:\n"
  . "check_ups_battery_values -H <hostname>\n"
  . "\t\t-w [<voltage range>],[<current range>],[<temperature range>]\n"
  . "\t\t-c [<voltage range>],[<current range>],[<temperature range>]\n"
  . "\t\t[-C <SNMP Community>] [-e <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]\n"
  . "\t\t[-V <version>]\n";
use constant BLURB =>
  "Checks the battery values (voltage, current and temperature)\n"
  . "on a RFC1628 (UPS-MIB) SNMP compliant device";
use constant LICENSE =>
  "This check plugin is free software, and comes with ABSOLUTELY NO WARRANTY\n"
  . "It may be used, redistributed and/or modified under the terms of the MIT\n"
  . " General Public Licence (see https://opensource.org/licenses/MIT).\n";
use constant EXAMPLE => "\n\n"
  . "Example:\n" . "\n"
  . "check_ups_battery_values -H 192.168.0.101 -w 210:240,,,\\~:40 -c 200:250,,\\~:50\n"
  . "Checks the voltage, current and temperature battery value levels of a UPS-MIB SNMP\n"
  . "compliant device with IP address 192.168.0.101.\n"
  . "Plugin returns WARNING if voltage is out of  210 to 240 volts range\n"
  . "or the temperature battery value exceeds 40�C, and returns CRITICAL if voltage is out of\n"
  . "200 to 250 volts range or temperature exceeds 50�C. In other case it returns OK.\n"
  . "\n"
  . "Ranges are defined as [@]start:end\n"
  . "Notes:\n" . "\n"
  . "1. start <= end\n" . "\n"
  . "2. start and ':' is not required if start=0\n" . "\n"
  . "3. if range is of format 'start:' and end is not specified, assume end is infinity\n"
  . "\n"
  . "4. to specify negative infinity, use '~'\n" . "\n"
  . "5. alert is raised if metric is outside start and end range (inclusive of endpoints)\n"
  . "\n"
  . "6. if range starts with '\@', then alert if inside this range (inclusive of endpoints)\n"
  . "\n"
  . "Example ranges:\n" . "\n" . "\n"
  . "10 \t\t\t\t Generate alert if x < 0 or > 10, (outside the range of {0 .. 10}) \n"
  . "10: \t\t\t\t Generate alert if x < 10, (outside {10 .. 8}) \n"
  . "~:10 \t\t\t Generate alert if x > 10, (outside the range of {-8 .. 10}) \n"
  . "10:20 \t\t\t Generate alert if x < 10 or > 20, (outside the range of {10 .. 20}) \n"
  . "\@10:20 \t\t\t Generate alert if x = 10 and = 20, (inside the range of {10 .. 20}) \n"
  . "\n"
  . "Note: Symbol '~' in bash is equivalent to the global variable \$HOME. Make sure to escape\n"
  . "this symbol with '\\' when type it in the command line. \n";

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
        spec => 'warning|w=s',
        help =>
          "Warning range list with format <voltage>,<current>,<temperature>",
        required => 1
    );

    # Add argument critical
    $Nagios->add_arg(
        spec => 'critical|c=s',
        help =>
          "Warning range list with format <voltage>,<current>,<temperature>",
        required => 1
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

    #my @IfRange;
    my $ArgOK;
    my $ThresholdsFormat;
    my $i;
    my $firstpos;
    my $secondpos;

    # Check if agent port number is > 0
    if ( $Nagios->opts->port <= 0 ) {
        $_[1] = "Invalid SNMP agent port: must be greater than zero";
        return 0;
    }

    # Check warning thresholds list
    my $commas = $Nagios->opts->warning =~ tr/,//;
    if ( $commas != 2 ) {
        $_[1] = "Invalid list Format. Twoo commas are expected.";
        return 0;
    }
    else {
        $i        = 0;
        $firstpos = 0;
        my $warning = $Nagios->opts->warning;
        while ( $warning =~ /[,]/g ) {
            $secondpos = pos $warning;
            if ( $secondpos - $firstpos == 1 ) {
                $arrayWarningRanges[$i] = "";
            }
            else {
                $arrayWarningRanges[$i] = substr $Nagios->opts->warning,
                  $firstpos, ( $secondpos - $firstpos - 1 );
            }
            $firstpos = $secondpos;
            $i++;
        }
        if ( length( $Nagios->opts->warning ) - $firstpos == 0 )
        {    #La coma es el ultimo elemento del string
            $arrayWarningRanges[$i] = "";
        }
        else {
            $arrayWarningRanges[$i] = substr $Nagios->opts->warning, $firstpos,
              ( length( $Nagios->opts->warning ) - $firstpos );
        }
        for ( $i = 0 ; $i <= 2 ; $i++ ) {
            if ( $arrayWarningRanges[$i] !~ /^(@?(\d+|(\d+|~):(\d*)))?$/ ) {
                $_[1] = "Invalid range in $arrayWarningRanges[$i]";
                return 0;
            }
        }
    }

    # Check critical thresholds list
    $commas = $Nagios->opts->critical =~ tr/,//;
    if ( $commas != 2 ) {
        $_[1] = "Invalid list Format. Two commas are expected.";
        return 0;
    }
    else {
        $i        = 0;
        $firstpos = 0;
        my $critical = $Nagios->opts->critical;
        while ( $critical =~ /[,]/g ) {
            $secondpos = pos $critical;
            if ( $secondpos - $firstpos == 1 ) {
                $arrayCriticalRanges[$i] = "";
            }
            else {
                $arrayCriticalRanges[$i] = substr $Nagios->opts->critical,
                  $firstpos, ( $secondpos - $firstpos - 1 );
            }
            $firstpos = $secondpos;
            $i++;
        }
        if ( length( $Nagios->opts->critical ) - $firstpos == 0 )
        {    #La coma es el ultimo elemento del string
            $arrayCriticalRanges[$i] = "";
        }
        else {
            $arrayCriticalRanges[$i] = substr $Nagios->opts->critical,
              $firstpos, ( length( $Nagios->opts->critical ) - $firstpos );
        }
        for ( $i = 0 ; $i <= 2 ; $i++ ) {
            if ( $arrayCriticalRanges[$i] !~ /^(@?(\d+|(\d+|~):(\d*)))?$/ ) {
                $_[1] = "Invalid range in $arrayCriticalRanges[$i]";
                return 0;
            }
        }
    }
    return 1;
}

# Performs whole check:
# Input: Nagios-compatible plugin object
# Output: Plugin output string
# Return value: Plugin return value

sub PerformCheck() {
    my $OID_UpsBatteryStatus      = UPS_MIB_BATTERY . '.1.0';
    my $OID_UpsBatteryVoltage     = UPS_MIB_BATTERY . '.5.0';
    my $OID_UpsBatteryCurrent     = UPS_MIB_BATTERY . '.6.0';
    my $OID_UpsBatteryTemperature = UPS_MIB_BATTERY . '.7.0';

    my $Nagios = $_[0];

    my $SNMPSession;
    my $SNMPError;
    my @RequestColumns;
    my $RequestResult;

    my $PluginOutput      = "";
    my $PluginReturnValue = UNKNOWN;

    my $OKOutput       = "";
    my $WarningOutput  = "";
    my $CriticalOutput = "";

    my $PluginReturnValueOfVoltage     = "";
    my $PluginReturnValueOfCurrent     = "";
    my $PluginReturnValueOfTemperature = "";

    my $upsBatteryTemperature;
    my $upsBatteryCurrent;
    my $upsBatteryVoltage;

    my $perfdata = "";

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
        my @oidRequest;
        push( @oidRequest, $OID_UpsBatteryStatus );
        my $RequestResult =
          $SNMPSession->get_request( -varbindlist => [$OID_UpsBatteryStatus] )
          ;    #\@oidRequest);
        my $upsBatteryStatus = $RequestResult->{$OID_UpsBatteryStatus};
        if ( !defined $RequestResult ) {    # SNMP query error
            $SNMPError = $SNMPSession->error();
            $PluginOutput =
                "Error '$SNMPError' retrieving info "
              . "from agent $Nagios->{opts}->{hostname}:$Nagios->{opts}->{port} "
              . "using protocol $Nagios->{opts}->{snmpver} "
              . "and community string **hidden for security**"
              ;    # '$Nagios->{opts}->{community}'";
        }
        else {
   #push (@oidRequest, $OID_UpsBatteryVoltage);
   #push (@oidRequest, $OID_UpsBatteryCurrent);
   #push (@oidRequest, $OID_UpsBatteryTemperature);
   #my $RequestResult = $SNMPSession->get_request(-varbindlist => \@oidRequest);

            $PluginReturnValue =
              OK;    #If there aren�t checked plugin will return ok status.

            # Voltaje:
            if ( $arrayWarningRanges[0] ne '' || $arrayCriticalRanges[0] ne '' )
            {
                my $RequestResult = $SNMPSession->get_request(
                    -varbindlist => [$OID_UpsBatteryVoltage] );
                $upsBatteryVoltage = $RequestResult->{$OID_UpsBatteryVoltage};
                if ( defined($upsBatteryVoltage) ) {
                    if ( $arrayCriticalRanges[0] eq '' ) {
                        $arrayCriticalRanges[0] = "~:";
                    }
                    if ( $arrayWarningRanges[0] eq '' ) {
                        $arrayWarningRanges[0] = "~:";
                    }

                    $PluginReturnValueOfVoltage = $Nagios->check_threshold(
                        check    => $upsBatteryVoltage,
                        warning  => $arrayWarningRanges[0],
                        critical => $arrayCriticalRanges[0]
                    );
                    if ( $PluginReturnValueOfVoltage eq OK ) {

#$OKOutput = $OKOutput . "Voltage Value in Battery is in range ($upsBatteryVoltage); ";

                        $OKOutput = $OKOutput
                          . "Voltage Value in Battery is in range ($upsBatteryVoltage in ";
                        if (   $arrayWarningRanges[0] ne '~:'
                            && $arrayCriticalRanges[0] ne '~:' )
                        {
                            $OKOutput = $OKOutput
                              . "ranges -> [$arrayWarningRanges[0]], [$arrayCriticalRanges[0]]). ";
                        }
                        elsif ( $arrayWarningRanges[0] ne '~:' ) {
                            $OKOutput = $OKOutput
                              . "range -> [$arrayWarningRanges[0]]). ";
                        }
                        elsif ( $arrayCriticalRanges[0] ne '~:' ) {
                            $OKOutput = $OKOutput
                              . "range -> [$arrayCriticalRanges[0]]). ";
                        }
                    }
                    elsif ( $PluginReturnValueOfVoltage eq WARNING ) {
                        $WarningOutput = $WarningOutput
                          . "Voltage Value in Battery is out of range ($upsBatteryVoltage in range -> [$arrayWarningRanges[0]]). ";
                    }
                    elsif ( $PluginReturnValueOfVoltage eq CRITICAL ) {
                        $CriticalOutput = $CriticalOutput
                          . "Voltage Value in Battery is out of range ($upsBatteryVoltage in range -> [$arrayCriticalRanges[0]]). ";
                    }
                }
                else {
                    #$PluginReturnValueOfVoltage = UNKNOWN;
                    $PluginReturnValue = UNKNOWN;
                    $PluginOutput      = "Error recovering values of Voltage..";
                    $_[1]              = $PluginOutput;
                    return $PluginReturnValue;
                }
            }

            # Current:
            if ( $arrayWarningRanges[1] ne '' || $arrayCriticalRanges[1] ne '' )
            {
                $RequestResult = $SNMPSession->get_request(
                    -varbindlist => [$OID_UpsBatteryCurrent] );
                $upsBatteryCurrent = $RequestResult->{$OID_UpsBatteryCurrent};
                if ( defined($upsBatteryCurrent) ) {
                    if ( $arrayCriticalRanges[1] eq '' ) {
                        $arrayCriticalRanges[1] = "~:";
                    }
                    if ( $arrayWarningRanges[1] eq '' ) {
                        $arrayWarningRanges[1] = "~:";
                    }

                    my $current = $upsBatteryCurrent /
                      10;    # Field 'current' must be divided by 10
                    $PluginReturnValueOfCurrent = $Nagios->check_threshold(
                        check    => $current,
                        warning  => $arrayWarningRanges[1],
                        critical => $arrayCriticalRanges[1]
                    );
                    if ( $PluginReturnValueOfCurrent eq OK ) {

   #$OKOutput = $OKOutput . "Current Value in Battery is in range ($current); ";

                        $OKOutput = $OKOutput
                          . "Current Value in Battery is in range ($current in ";
                        if (   $arrayWarningRanges[0] ne '~:'
                            && $arrayCriticalRanges[0] ne '~:' )
                        {
                            $OKOutput = $OKOutput
                              . "ranges -> [$arrayWarningRanges[1]], [$arrayCriticalRanges[1]]). ";
                        }
                        elsif ( $arrayWarningRanges[0] ne '~:' ) {
                            $OKOutput = $OKOutput
                              . "range -> [$arrayWarningRanges[1]]). ";
                        }
                        elsif ( $arrayCriticalRanges[0] ne '~:' ) {
                            $OKOutput = $OKOutput
                              . "range -> [$arrayCriticalRanges[1]]). ";
                        }
                    }
                    elsif ( $PluginReturnValueOfCurrent eq WARNING ) {
                        $WarningOutput = $WarningOutput
                          . "Current Value in Battery is out of range ($current in range -> [$arrayWarningRanges[1]]). ";
                    }
                    elsif ( $PluginReturnValueOfCurrent eq CRITICAL ) {
                        $CriticalOutput = $CriticalOutput
                          . "Current Value in Battery is out of range ($current in range -> [$arrayCriticalRanges[1]]). ";
                    }
                }
                else {
                    #$PluginReturnValueOfCurrent = UNKNOWN;
                    $PluginReturnValue = UNKNOWN;
                    $PluginOutput      = "Error recovering values of Current";
                    $_[1]              = $PluginOutput;
                    return $PluginReturnValue;
                }
            }

            # Temperature:
            if ( $arrayWarningRanges[2] ne '' || $arrayCriticalRanges[2] ne '' )
            {
                $RequestResult = $SNMPSession->get_request(
                    -varbindlist => [$OID_UpsBatteryTemperature] );
                $upsBatteryTemperature =
                  $RequestResult->{$OID_UpsBatteryTemperature};
                if ($upsBatteryTemperature) {
                    if ( $arrayCriticalRanges[2] eq '' ) {
                        $arrayCriticalRanges[2] = "~:";
                    }
                    if ( $arrayWarningRanges[2] eq '' ) {
                        $arrayWarningRanges[2] = "~:";
                    }

                    $PluginReturnValueOfTemperature = $Nagios->check_threshold(
                        check    => $upsBatteryTemperature,
                        warning  => $arrayWarningRanges[2],
                        critical => $arrayCriticalRanges[2]
                    );
                    if ( $PluginReturnValueOfTemperature eq OK ) {
                        $OKOutput = $OKOutput
                          . "Temperature Value in Battery is in range ($upsBatteryTemperature in ";
                        if (   $arrayWarningRanges[0] ne '~:'
                            && $arrayCriticalRanges[0] ne '~:' )
                        {
                            $OKOutput = $OKOutput
                              . "ranges -> [$arrayWarningRanges[2]], [$arrayCriticalRanges[2]]). ";
                        }
                        elsif ( $arrayWarningRanges[0] ne '~:' ) {
                            $OKOutput = $OKOutput
                              . "range -> [$arrayWarningRanges[2]]). ";
                        }
                        elsif ( $arrayCriticalRanges[0] ne '~:' ) {
                            $OKOutput = $OKOutput
                              . "range -> [$arrayCriticalRanges[2]]). ";
                        }
                    }
                    elsif ( $PluginReturnValueOfTemperature eq WARNING ) {
                        $WarningOutput = $WarningOutput
                          . "Temperature Value in Battery is out of range ($upsBatteryTemperature in range -> [$arrayWarningRanges[2]]). ";
                    }
                    elsif ( $PluginReturnValueOfTemperature eq CRITICAL ) {
                        $CriticalOutput = $CriticalOutput
                          . "Temperature Value in Battery is out of range ($upsBatteryTemperature in range -> [$arrayCriticalRanges[2]]). ";
                    }
                }
                else {
                    #$PluginReturnValueOfTemperature = UNKNOWN;
                    $PluginReturnValue = UNKNOWN;
                    $PluginOutput = "Error recovering values of Temperature";
                    $_[1]         = $PluginOutput;
                    return $PluginReturnValue;
                }
            }

        }

#~ if ($PluginReturnValueOfVoltage eq UNKNOWN || $PluginReturnValueOfCurrent eq UNKNOWN || $PluginReturnValueOfTemperature eq UNKNOWN) {
#~ # $PluginReturnValue = UNKNOWN;
#~ $PluginReturnValue = UNKNOWN;
#~ $PluginOutput = "Error recovering values";
#~ $_[1] = $PluginOutput;
#~ return $PluginReturnValue;
#~ }
#~ else {
        if ( $CriticalOutput ne '' ) {
            $PluginOutput      = $PluginOutput . $CriticalOutput;
            $PluginReturnValue = CRITICAL;
        }
        elsif ( $WarningOutput ne '' ) {
            $PluginOutput      = $PluginOutput . $WarningOutput;
            $PluginReturnValue = WARNING;
        }
        elsif ( $OKOutput ne '' ) {
            $PluginOutput      = $PluginOutput . $OKOutput;
            $PluginReturnValue = OK;
        }

        #Only show performance data for typed ranges
        if (   ( $arrayCriticalRanges[0] ne '' )
            || ( $arrayWarningRanges[0] ne '' ) )
        {
            $perfdata .= "'Battery Voltage'=$upsBatteryVoltage" . "V;;;;";
        }
        if (   ( $arrayCriticalRanges[1] ne '' )
            || ( $arrayWarningRanges[1] ne '' ) )
        {
            $perfdata .= "'Battery Current'=$upsBatteryCurrent" . "A;;;;";
        }
        if (   ( $arrayCriticalRanges[2] ne '' )
            || ( $arrayWarningRanges[2] ne '' ) )
        {
            $perfdata .=
              "'Battery Temperature'=$upsBatteryTemperature" . "C;;;;";
        }

        $PluginOutput .= "| $perfdata";

        #}

        # Close SNMP session
        $SNMPSession->close;
    }

    #Return result
    $_[1] = $PluginOutput;
    return $PluginReturnValue;
}
