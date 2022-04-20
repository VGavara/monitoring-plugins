#!/usr/bin/perl -w

# check_ups_inputs Nagios-compatible plugin
#
# Checks the input levels (frequency, voltage, current and/or power )
# on a RFC1628 (UPS-MIB) SNMP compliant device
#
# Type check_ups_inputs --help for getting more info and examples.
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

use constant MIB_UPS_INPUT => '1.3.6.1.2.1.33.1.3';

use constant NAME    => 'check_ups_inputs';
use constant VERSION => '1.0';
use constant USAGE => "Usage:\n"
  . "check_up_inputs -H <hostname>\n"
  . "\t\t-w [<frequency range>],[<voltage range>],[<current range>],[<power range>]\n"
  . "\t\t-c [<frequency range>],[<voltage range>],[<current range>],[<power range>]\n"
  . "\t\t[-i <input list>]\n"
  . "\t\t[-C <SNMP Community>] [-E <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]\n"
  . "\t\t[-V <version>]\n";
use constant BLURB =>
  "Checks the input levels (frequency, voltage, current and/or power)\n"
  . "on a RFC1628 (UPS-MIB) SNMP compliant device";
use constant LICENSE =>
  "This check plugin is free software, and comes with ABSOLUTELY NO WARRANTY\n"
  . "It may be used, redistributed and/or modified under the terms of the MIT\n"
  . " General Public Licence (see https://opensource.org/licenses/MIT).\n";
use constant EXAMPLE => "\n\n"
  . "Example:\n" . "\n"
  . "check_ups_inputs -H 192.168.0.101 -i 1,2,3 -w ,210:240,,\\~:3000 -c ,200:250,,\\~:4000\n"
  . "Checks the 1 to 3 input levels of a UPS-MIB SNMP compliant device\n"
  . "with IP address 192.168.0.101.\n"
  . "Plugin returns WARNING if voltage is out of  210 to 240 volts range\n"
  . "or the output power exceeds 3000W, and returns CRITICAL if voltage is out of\n"
  . "200 to 250 volts range or power exceeds 4000W. In other case it returns OK.\n"
  . "\n"
  . "Ranges are defined as [@]start:end\n"
  . "Notes:\n" . "\n"
  . "1. start <= end\n"
  . "2. start and ':' is not required if start=0\n"
  . "3. if range is of format 'start:' and end is not specified, assume end is infinity\n"
  . "4. to specify negative infinity, use '~'\n"
  . "5. alert is raised if metric is outside start and end range (inclusive of endpoints)\n"
  . "6. if range starts with '\@', then alert if inside this range (inclusive of endpoints)\n"
  . "\n"
  . "Example ranges:\n" . "\n" . "\n"
  . "10 \t\t\t Generate alert if x < 0 or > 10, (outside the range of {0 .. 10}) \n"
  . "10: \t\t\t Generate alert if x < 10, (outside {10 .. 8}) \n"
  . "~:10 \t\t\t Generate alert if x > 10, (outside the range of {-8 .. 10}) \n"
  . "10:20 \t\t\t Generate alert if x < 10 or > 20, (outside the range of {10 .. 20}) \n"
  . "\@10:20 \t\t\t Generate alert if x = 10 and = 20, (inside the range of {10 .. 20}) \n"
  . "\n"
  . "Note: Symbol '~' in bash is equivalent to the global variable  \$HOME. Make sure to escape\n"
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

    # Add argument input
    $Nagios->add_arg(
        spec     => 'input|i=s',
        help     => 'Input lines list (default: check all inputs)',
        required => 0
    );

    # Add argument warning
    $Nagios->add_arg(
        spec => 'warning|w=s',
        help =>
"Warning range list with format [<frequency>],[<voltage>],[<current>],[<power>]",
        required => 1
    );

    # Add argument critical
    $Nagios->add_arg(
        spec => 'critical|c=s',
        help =>
"Critical range list with format [<frequency>],[<voltage>],[<current>],[<power>]",
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
    my $ArgOK;
    my $ThresholdsFormat;
    my $i;
    my $Range;

    # Check if agent port number is > 0
    if ( $Nagios->opts->port <= 0 ) {
        $_[1] = "Invalid SNMP agent port: must be greater than zero";
        return 0;
    }

    # Check input list
    if ( defined $Nagios->opts->input ) {
        if ( $Nagios->opts->input =~ /^\d+(,\d+)*$/ ) {
            my @inputLines = split( /,/, $Nagios->opts->input );
            my $input;
            for ( $i = 0 ; $i <= $#inputLines ; $i++ ) {
                $input = $inputLines[$i];
                if ( $input <= 0 ) {
                    $_[1] =
                      "Invalid input Number line: must be greater than zero";
                    return 0;
                }
            }
        }
        else {
            $_[1] = "Invalid input range";
            return 0;
        }
    }

    # Check warning range list
    # Dummy value added and then popped to avoid split discarding
    # undef values and the end of the string
    @arrayWarningRanges = split( /,/, $Nagios->opts->warning . ',dummy' );
    pop @arrayWarningRanges;
    if ( @arrayWarningRanges == 4 ) {
        foreach $Range (@arrayWarningRanges) {
            if ( $Range !~ /^(@?(\d+|(\d+|~):(\d*)))?$/ ) {
                $_[1] = "Invalid warning range: '$Range'";
                return 0;
            }
        }
    }
    else {
        $_[1] = 'Invalid warning range list';
        return 0;
    }

    # Check critical range list
    # Dummy value added and then popped to avoid split discarding
    # undef values and the end of the string
    @arrayCriticalRanges = split( /,/, $Nagios->opts->critical . ',dummy' );
    pop @arrayCriticalRanges;
    if ( @arrayCriticalRanges == 4 ) {
        foreach $Range (@arrayCriticalRanges) {
            if ( $Range !~ /^(@?(\d+|(\d+|~):(\d*)))?$/ ) {
                $_[1] = "Invalid critical range: '$Range'";
                return 0;
            }
        }
    }
    else {
        $_[1] = 'Invalid critical range list';
        return 0;
    }

    return 1;
}

# Performs whole check:
# Input: Nagios-compatible plugin object
# Output: Plugin output string
# Return value: Plugin return value

sub PerformCheck() {

    my $OID_upsInputNumLines  = MIB_UPS_INPUT . '.2';
    my $OID_upsInputEntry     = MIB_UPS_INPUT . '.3.1';
    my $OID_upsInputFrequency = MIB_UPS_INPUT . '.3.1.2';
    my $OID_upsInputVoltage   = MIB_UPS_INPUT . '.3.1.3';
    my $OID_upsInputCurrent   = MIB_UPS_INPUT . '.3.1.4';
    my $OID_upsInputTruePower = MIB_UPS_INPUT . '.3.1.5';

    my $Nagios = $_[0];

    my $SNMPSession;
    my $SNMPError;

    #my @RequestColumns;
    my $RequestResult;

    my $PluginOutput      = "";
    my $PluginReturnValue = UNKNOWN;
    my $i;
    my $j;
    my $field;
    my @FieldsToProcess;
    my $CriticalOutput = "";
    my $WarningOutput  = "";
    my $perfdata       = "";
    my @fields         = ( "Frequency", "Voltage", "Current", "True power" );

    # Start new SNMP session
    ( $SNMPSession, $SNMPError ) = Net::SNMP->session(
        -hostname  => $Nagios->opts->hostname,
        -community => $Nagios->opts->community,
        -version   => $Nagios->opts->snmpver,
        -port      => $Nagios->opts->port,
        -timeout   => $Nagios->opts->timeout
    );

#($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => "192.168.6.120", -community => "public", -version => 1);
    if ( !defined($SNMPSession) ) {

        #SNMP Get error
        $PluginOutput = "Error '$SNMPError' starting session";
    }
    else {
        # Perform SNMP request

        my $TableRef =
          $SNMPSession->get_table( -baseoid => MIB_UPS_INPUT . ".3" );
        $SNMPError = $SNMPSession->error();
        if ( !defined($TableRef) ) {

            # SNMP query error
            $PluginOutput =
                "Error '$SNMPError' retrieving info "
              . "from agent $Nagios->{opts}->{hostname}:$Nagios->{opts}->{port} "
              . "using protocol $Nagios->{opts}->{snmpver} "
              . "and community string **hidden for security**\n"
              ;    # '$Nagios->{opts}->{community}'";
        }
        else {
            my @ranges;
            my $length;

            $j = 0;
            for ( $i = 0 ; $i <= 3 ; $i++ ) {    #

                if (   ( $arrayCriticalRanges[$i] ne '' )
                    || ( $arrayWarningRanges[$i] ne '' ) )
                {
                    if ( $arrayCriticalRanges[$i] eq '' ) {
                        $arrayCriticalRanges[$i] = "~:";
                    }
                    if ( $arrayWarningRanges[$i] eq '' ) {
                        $arrayWarningRanges[$i] = "~:";
                    }
                    $FieldsToProcess[$j] = $i;
                    $j++;
                }
            }

            if ( !defined( $Nagios->opts->input ) ) {    #All input Lines
                my $NumLines = $SNMPSession->get_request(
                    -varbindlist => [$OID_upsInputNumLines] );
                $NumLines = $$NumLines{$OID_upsInputNumLines};
                if ( $NumLines <= 0 ) {
                    $_[1] = "No input lines.";
                    return UNKNOWN;
                }
                $length = @FieldsToProcess;
                for ( $i = 1 ; $i <= $NumLines ; $i++ ) {
                    for ( $j = 0 ; $j < $length ; $j++ ) {

                        if (
                            defined(
                                $$TableRef{
                                    "$OID_upsInputEntry."
                                      . ( $FieldsToProcess[$j] + 2 ) . ".$i"
                                }
                            )
                          )
                        {
                            $field =
                              $$TableRef{ "$OID_upsInputEntry."
                                  . ( $FieldsToProcess[$j] + 2 )
                                  . ".$i" };
                            if (   ( ( $FieldsToProcess[$j] + 2 ) == 2 )
                                || ( ( $FieldsToProcess[$j] + 2 ) == 4 ) )
                            { # Fields 'frequency' and'current' must be divided by 10
                                $field = $field / 10;
                            }

                            $PluginReturnValue = $Nagios->check_threshold(
                                check   => $field,
                                warning =>
                                  $arrayWarningRanges[ $FieldsToProcess[$j] ],
                                critical =>
                                  $arrayCriticalRanges[ $FieldsToProcess[$j] ]
                            );

                            #print "Return value = $PluginReturnValue\n";

                            if ( $PluginReturnValue eq OK ) {
                                $PluginOutput =
                                  "All Values in all Inputs are in range.";
                            }
                            else {
                                if ( $PluginReturnValue eq CRITICAL ) {
                                    @ranges = @arrayCriticalRanges;
                                }
                                else {
                                    if ( $PluginReturnValue eq WARNING ) {
                                        @ranges = @arrayWarningRanges;
                                    }
                                }
                                my $message = "";
                                my $doubledot =
                                  $ranges[ $FieldsToProcess[$j] ] =~ tr/://;

                                if (
                                    (
                                        substr $ranges[ $FieldsToProcess[$j] ],
                                        0, 1
                                    ) eq "\@"
                                  )
                                {
                                    my @limits = split(
                                        /:/,
                                        (
                                            substr
                                              $ranges[ $FieldsToProcess[$j] ],
                                            1,
                                            length(
                                                $ranges[ $FieldsToProcess[$j] ]
                                            )
                                        )
                                    );
                                    my $minMessage = "";
                                    my $maxMessage = "";
                                    if ( !$doubledot ) {
                                        $minMessage = " >=0 or <= $limits[0]";
                                    }
                                    else {
                                        if ( $limits[0] ne "~" ) {
                                            $minMessage = " <$limits[0]";
                                        }
                                        if ( defined( $limits[1] ) ) {
                                            $maxMessage = " >$limits[1]";
                                        }
                                    }
                                    if (    length($minMessage)
                                        and length($maxMessage) )
                                    {
                                        $message =
"Input #$i: $fields[$FieldsToProcess[$j]] = $field (valid range is ";
                                        $message = $minMessage . " or"
                                          . $maxMessage . "); ";
                                    }
                                    else {
                                        $message =
"Input #$i: $fields[$FieldsToProcess[$j]] = $field (valid range is $minMessage$maxMessage); ";
                                    }

                                }
                                else {
                                    my $doubledot =
                                      $ranges[ $FieldsToProcess[$j] ] =~ tr/://;
                                    my @limits = split( /:/,
                                        $ranges[ $FieldsToProcess[$j] ] );
                                    my $minMessage = "";
                                    my $maxMessage = "";

                                    if ( !$doubledot ) {
                                        $minMessage = " >=0 and <= $limits[0]";
                                    }
                                    else {
                                        if ( $limits[0] ne "~" ) {
                                            $minMessage = " >=$limits[0]";
                                        }
                                        if ( defined( $limits[1] ) ) {
                                            $maxMessage = " <=$limits[1]";
                                        }
                                    }
                                    if (    length($minMessage)
                                        and length($maxMessage) )
                                    {
                                        $message =
"Input #$i: $fields[$FieldsToProcess[$j]] = $field (valid range is ";
                                        $message .= $minMessage . " and"
                                          . $maxMessage . "); ";
                                    }
                                    else {
                                        $message =
"Input #$i: $fields[$FieldsToProcess[$j]] = $field (valid range is $minMessage$maxMessage); ";
                                    }

                                }

                                #print "mensaje = $message\n";
                                if ( $PluginReturnValue eq CRITICAL ) {
                                    $CriticalOutput .= $message;
                                }
                                else {
                                    if ( $PluginReturnValue eq WARNING ) {
                                        $WarningOutput .= $message;
                                    }
                                }

                            }
                        }
                        else {
                            $PluginReturnValue = UNKNOWN;
                            $PluginOutput      = "Error. Input $i not found.";
                            $_[1]              = $PluginOutput;
                            return $PluginReturnValue;
                        }
                    }

                }
            }
            else {    # Output list
                my @inputLines = split( /,/, $Nagios->opts->input );
                $length = @inputLines;
                my $inputLine;
                my $lengthFields = @FieldsToProcess;
                for ( $i = 0 ; $i < $length ; $i++ ) {
                    $inputLine = $inputLines[$i];
                    for ( $j = 0 ; $j < $lengthFields ; $j++ ) {
                        if (
                            defined(
                                $$TableRef{
                                        "$OID_upsInputEntry."
                                      . ( $FieldsToProcess[$j] + 2 )
                                      . ".$inputLine"
                                }
                            )
                          )
                        {
                            $field =
                              $$TableRef{ "$OID_upsInputEntry."
                                  . ( $FieldsToProcess[$j] + 2 )
                                  . ".$inputLine" };
                            if (   ( ( $FieldsToProcess[$j] + 2 ) == 4 )
                                || ( ( $FieldsToProcess[$j] + 2 ) == 2 ) )
                            { # Fields 'frequency' and 'current' must be divided by 10
                                $field = $field / 10;
                            }

                            $PluginReturnValue = $Nagios->check_threshold(
                                check   => $field,
                                warning =>
                                  $arrayWarningRanges[ $FieldsToProcess[$j] ],
                                critical =>
                                  $arrayCriticalRanges[ $FieldsToProcess[$j] ]
                            );
                            if ( $PluginReturnValue eq OK ) {
                                $PluginOutput =
                                  "All Values in all Inputs are in range.";
                            }
                            else {
                                if ( $PluginReturnValue eq CRITICAL ) {
                                    @ranges = @arrayCriticalRanges;
                                }
                                else {
                                    if ( $PluginReturnValue eq WARNING ) {
                                        @ranges = @arrayWarningRanges;
                                    }
                                }
                                my $message = "";
                                if (
                                    (
                                        substr $ranges[ $FieldsToProcess[$j] ],
                                        0, 1
                                    ) eq "\@"
                                  )
                                {
                                    my @limits = split(
                                        /:/,
                                        (
                                            substr
                                              $ranges[ $FieldsToProcess[$j] ],
                                            1,
                                            length(
                                                $ranges[ $FieldsToProcess[$j] ]
                                            )
                                        )
                                    );
                                    my $doubledot =
                                      $ranges[ $FieldsToProcess[$j] ] =~ tr/://;
                                    my $minMessage = "";
                                    my $maxMessage = "";
                                    if ( !$doubledot ) {
                                        $minMessage = " >=0 or <= $limits[0]";
                                    }
                                    else {
                                        if ( $limits[0] ne "~" ) {
                                            $minMessage = " <$limits[0]";
                                        }
                                        if ( defined( $limits[1] ) ) {
                                            $maxMessage = " >$limits[1]";
                                        }
                                    }
                                    if (    length($minMessage)
                                        and length($maxMessage) )
                                    {
                                        $message =
"Input #$inputLine: $fields[$FieldsToProcess[$j]] = $field (valid range is ";
                                        $message .= $minMessage . " or"
                                          . $maxMessage . "); ";
                                    }
                                    else {
                                        $message =
"Input #$inputLine: $fields[$FieldsToProcess[$j]] = $field (valid range is $minMessage$maxMessage); ";
                                    }

                                }
                                else {
                                    my $doubledot =
                                      $ranges[ $FieldsToProcess[$j] ] =~ tr/://;
                                    my @limits = split( /:/,
                                        $ranges[ $FieldsToProcess[$j] ] );
                                    my $minMessage = "";
                                    my $maxMessage = "";

                                    if ( !$doubledot ) {
                                        $minMessage = " >=0 and <= $limits[0]";
                                    }
                                    else {
                                        if ( $limits[0] ne "~" ) {
                                            $minMessage = " >=$limits[0]";
                                        }
                                        if ( defined( $limits[1] ) ) {
                                            $maxMessage = " <=$limits[1]";
                                        }
                                    }
                                    if (    length($minMessage)
                                        and length($maxMessage) )
                                    {
                                        $message =
"Input #$inputLine: $fields[$FieldsToProcess[$j]] = $field (valid range is ";
                                        $message .= $minMessage . " and"
                                          . $maxMessage . "); ";

                                    }
                                    else {
                                        $message =
"Input #$inputLine: $fields[$j-2] = $field (valid range is $minMessage$maxMessage); ";
                                    }
                                }
                                if ( $PluginReturnValue eq CRITICAL ) {
                                    $CriticalOutput .= $message;
                                }
                                else {
                                    if ( $PluginReturnValue eq WARNING ) {
                                        $WarningOutput .= $message;
                                    }
                                }
                            }
                        }
                        else {
                            $PluginReturnValue = UNKNOWN;
                            $PluginOutput =
                              "Error. Input $inputLines[$i] not found.";
                            $_[1] = $PluginOutput;
                            return $PluginReturnValue;
                        }
                    }
                }

            }
            if ( $CriticalOutput ne '' ) {
                $PluginOutput      = $CriticalOutput;
                $PluginReturnValue = CRITICAL;
            }
            else {
                if ( $WarningOutput ne '' ) {
                    $PluginOutput      = $WarningOutput;
                    $PluginReturnValue = WARNING;
                }
                else {
                    $PluginOutput = "All Values in all inputs are in range.";
                    $PluginReturnValue = OK;
                }
            }
        }

        #Performance Data

        if ( !defined( $Nagios->opts->input ) ) {    #All Output Lines
            my $NumLines = $SNMPSession->get_request(
                -varbindlist => [$OID_upsInputNumLines] );
            $NumLines = $$NumLines{$OID_upsInputNumLines};
            for ( $i = 1 ; $i <= $NumLines ; $i++ ) {

                if (   ( $arrayCriticalRanges[0] ne '' )
                    || ( $arrayWarningRanges[0] ne '' ) )
                {
                    $field = $$TableRef{ $OID_upsInputFrequency . ".$i" } / 10;
                    $perfdata .= "'In$i$fields[0]'=$field" . "Hz;;;; ";
                }
                if (   ( $arrayCriticalRanges[1] ne '' )
                    || ( $arrayWarningRanges[1] ne '' ) )
                {
                    $field = $$TableRef{ $OID_upsInputVoltage . ".$i" };

                    $perfdata .= "'In$i$fields[1]'=$field" . "V;;;; ";
                }
                if (   ( $arrayCriticalRanges[2] ne '' )
                    || ( $arrayWarningRanges[2] ne '' ) )
                {
                    $field = $$TableRef{ $OID_upsInputCurrent . ".$i" } / 10;
                    $perfdata .= "'In$i$fields[2]'=$field" . "A;;;; ";
                }
                if (   ( $arrayCriticalRanges[3] ne '' )
                    || ( $arrayWarningRanges[3] ne '' ) )
                {
                    $field = $$TableRef{ $OID_upsInputTruePower . ".$i" };
                    $perfdata .= "'In$i$fields[3]'=$field" . "W;;;; ";
                }
            }
        }
        else {
            my @inputLines = split( /,/, $Nagios->opts->input );
            my $length     = @inputLines;
            my $inputLine;
            for ( $i = 0 ; $i < $length ; $i++ ) {
                $inputLine = $inputLines[$i];
                if (   ( $arrayCriticalRanges[0] ne '' )
                    || ( $arrayWarningRanges[0] ne '' ) )
                {
                    $field =
                      $$TableRef{ $OID_upsInputFrequency . ".$inputLine" } / 10;
                    $perfdata .= "'In$inputLine$fields[0]'=$field" . "Hz;;;; ";
                }
                if (   ( $arrayCriticalRanges[1] ne '' )
                    || ( $arrayWarningRanges[1] ne '' ) )
                {
                    $field = $$TableRef{ $OID_upsInputVoltage . ".$inputLine" };

                    $perfdata .= "'In$inputLine$fields[1]'=$field" . "V;;;; ";
                }
                if (   ( $arrayCriticalRanges[2] ne '' )
                    || ( $arrayWarningRanges[2] ne '' ) )
                {
                    $field =
                      $$TableRef{ $OID_upsInputCurrent . ".$inputLine" } / 10;
                    $perfdata .= "'In$inputLine$fields[2]'=$field" . "A;;;; ";
                }
                if (   ( $arrayCriticalRanges[3] ne '' )
                    || ( $arrayWarningRanges[3] ne '' ) )
                {
                    $field =
                      $$TableRef{ $OID_upsInputTruePower . ".$inputLine" };
                    $perfdata .= "'In$inputLine$fields[3]'=$field" . "W;;;; ";
                }
            }

        }
        $PluginOutput .= "| $perfdata";

        # Close SNMP session
        $SNMPSession->close;
    }

    #Return result
    $_[1] = $PluginOutput;
    return $PluginReturnValue;
}
