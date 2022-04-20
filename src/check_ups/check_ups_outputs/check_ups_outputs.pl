#!/usr/bin/perl -w

# check_forwarding_rate Nagios-compatible plugin
#
# Checks the forwarding rate (as defined in RFC 2285)
# on a MIB2 Interfaces SNMP compliant device.
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

use constant MIB_UPS_OUTPUT => '1.3.6.1.2.1.33.1.4';

use constant NAME    => 'check_ups_outputs';
use constant VERSION => '1.0';
use constant USAGE => "Usage:\n"
  . "check_up_outputs -H <hostname>\n"
  . "\t\t-w [<voltage range>],[<current range>],[<power range>],[<load range>]\n"
  . "\t\t-c [<voltage range>],[<current range>],[<power range>],[<load range>]\n"
  . "\t\t[-o <output list>]\n"
  . "\t\t[-p <UPS power rating>]\n"
  . "\t\t[-C <SNMP Community>] [-E <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]\n"
  . "\t\t[-V <version>]\n"
  . "\t\t[-f]\n";
use constant BLURB =>
  "Checks the output levels (voltage, current, power and/or load percent)\n"
  . "on a RFC1628 (UPS-MIB) SNMP compliant device";
use constant LICENSE =>
  "This check plugin is free software, and comes with ABSOLUTELY NO WARRANTY\n"
  . "It may be used, redistributed and/or modified under the terms of the MIT\n"
  . " General Public Licence (see https://opensource.org/licenses/MIT).\n";
use constant EXAMPLE => "\n\n"
  . "Example:\n" . "\n"
  . "check_ups_outputs -H 192.168.0.101 -o 1,2,3 -w 210:240,,,\\~:70 -c 200:250,,,\\~:90\n"
  . "Checks the 1 to 3 output levels of a UPS-MIB SNMP compliant device\n"
  . "with IP address 192.168.0.101.\n"
  . "Plugin returns WARNING if voltage is out of  210 to 240 volts range\n"
  . "or the output load exceeds 70%, and returns CRITICAL if voltage is out of\n"
  . "200 to 250 volts range or load exceeds 90%. In other case it returns OK.\n"
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

    # Add argument output
    $Nagios->add_arg(
        spec     => 'output|o=s',
        help     => 'Output lines list (default: check all outputs)',
        required => 0
    );

    # Add argument power rating
    $Nagios->add_arg(
        spec     => 'power|p=i',
        help     => 'Power Rating <UPS power rating, in watts>',
        required => 0
    );

    # Add argument warning
    $Nagios->add_arg(
        spec => 'warning|w=s',
        help =>
"Warning range list with format [<voltage>],[<current>],[<power>],[<load>]",
        required => 1
    );

    # Add argument critical
    $Nagios->add_arg(
        spec => 'critical|c=s',
        help =>
"Critical range list with format [<voltage>],[<current>],[<power>],[<load>]",
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

    # Check if agent power rating is >0
    if ( defined $Nagios->opts->power ) {
        if ( $Nagios->opts->power <= 0 ) {
            $_[1] = "Invalid Power Rating: must be greater than zero";
            return 0;
        }
    }

    # Check output list
    if ( defined $Nagios->opts->output ) {
        if ( $Nagios->opts->output =~ /^\d+(,\d+)*$/ ) {
            my @outputLines = split( /,/, $Nagios->opts->output );
            my $output;
            for ( $i = 0 ; $i <= $#outputLines ; $i++ ) {
                $output = $outputLines[$i];
                if ( $output <= 0 ) {
                    $_[1] =
                      "Invalid Output Number line: must be greater than zero";
                    return 0;
                }
            }
        }
        else {
            $_[1] = "Invalid Output range";
            return 0;
        }
    }
    my $commas = $Nagios->opts->warning =~ tr/,//;

    #@arrayWarningRanges;

    if ( $commas != 3 ) {
        $_[1] = "Invalid list Format. Three commas are expected.";
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
        for ( $i = 0 ; $i <= 3 ; $i++ ) {
            if ( $arrayWarningRanges[$i] !~ /^(@?(\d+|(\d+|~):(\d*)))?$/ ) {
                $_[1] = "Invalid Warning Range in $arrayWarningRanges[$i]";
                return 0;
            }
        }
    }
    $commas = $Nagios->opts->critical =~ tr/,//;

    #@arrayCriticalRanges;

    #print $c;
    if ( $commas != 3 ) {
        $_[1] = "Invalid list Format. Three commas are expected.";
        return 0;
    }
    else {
        $i        = 0;
        $firstpos = 0;
        my $critical = $Nagios->opts->critical;
        while ( $critical =~ /[,]/g ) {
            $secondpos = pos $critical;
            if ( $secondpos - $firstpos == 1 ) {

                #print "Cambio el formato critical\n";
                #$arrayCriticalRanges[$i] = "~:";
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
        for ( $i = 0 ; $i <= 3 ; $i++ ) {
            if ( $arrayCriticalRanges[$i] !~ /^(@?(\d+|(\d+|~):(\d*)))?$/ ) {
                $_[1] = "ee$arrayCriticalRanges[$i]\n";
                $_[1] = $Nagios->opts->critical;

                #$_[1] = "Invalid Critical Range in $arrayCriticalRanges[$i]";
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

    #my $OID_IfCount = MIB2_INTERFACES . '.1.0';
    #my $OID_IfOutUnicastPackets = MIB2_INTERFACES . '.2.1.17';
    #my $OID_IfOutNonUnicastPackets = MIB2_INTERFACES . '.2.1.18';

    my $Nagios = $_[0];

    my $SNMPSession;
    my $SNMPError;
    my @RequestColumns;
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
    my @fields         = ( "Voltage", "Current", "True power", "Percent Load" );

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
        # Set thresold range
        #@arrayCriticalRanges = split(/,/, $Nagios->opts->critical);
        #@arrayWarningRanges = split(/,/, $Nagios->opts->warning);

    # Perform SNMP request
    #my $TableRef = $SNMPSession->get_table(-baseoid => "1.3.6.1.2.1.33.1.4.4");

        my $TableRef =
          $SNMPSession->get_table( -baseoid => MIB_UPS_OUTPUT . ".4" );
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

            if ( !defined( $Nagios->opts->output ) ) {    #All Output Lines
                my $NumLines = $SNMPSession->get_request(
                    -varbindlist => [ MIB_UPS_OUTPUT . ".3" ] );
                $NumLines = $$NumLines{ MIB_UPS_OUTPUT . ".3" };
                $length   = @FieldsToProcess;
                for ( $i = 1 ; $i <= $NumLines ; $i++ ) {
                    for ( $j = 0 ; $j < $length ; $j++ ) {

                        #for ($j=2;$j<=5;$j++){
                        if (
                            defined(
                                $$TableRef{
                                    MIB_UPS_OUTPUT . ".4.1."
                                      . ( $FieldsToProcess[$j] + 2 ) . ".$i"
                                }
                            )
                          )
                        {
                            $field =
                              $$TableRef{ MIB_UPS_OUTPUT . ".4.1."
                                  . ( $FieldsToProcess[$j] + 2 )
                                  . ".$i" };
                            if ( ( $FieldsToProcess[$j] + 2 ) == 3 )
                            {    # Field 'current' must be divided by 10
                                $field = $field / 10;
                            }

                            elsif ( defined( $Nagios->opts->power )
                                && ( ( $FieldsToProcess[$j] + 2 ) == 5 ) )
                            {
                                my $upsOutPower =
                                  $$TableRef{ MIB_UPS_OUTPUT . ".4.1.4.$i" };
                                if ( !defined($upsOutPower) ) {
                                    $_[1] =
"Error in True power of output $i calculating percent load";
                                    return UNKNOWN;
                                }
                                else {
                                    $field = int(
                                        (
                                            (
                                                $upsOutPower /
                                                  $Nagios->opts->power
                                            ) * 100
                                        ) + 0.5
                                    );
                                }
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
                                  "All Values in all Outputs are in range.";
                            }
                            else {
                                if ( $PluginReturnValue eq CRITICAL ) {
                                    @ranges = @arrayCriticalRanges;

#$CriticalOutput .= "Output $i: Campo $fields[$j-2] = ".$field." (is not a valid range)\n"; #(valid range ";
                                }
                                else {
                                    if ( $PluginReturnValue eq WARNING ) {
                                        @ranges = @arrayWarningRanges;

#$WarningOutput .= "Output $i: Campo $fields[$j-2] = ".$field." (is not a valid range)\n"; #(valid range ";
                                    }
                                }

                                #print Dumper(@ranges);
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

                                    #print Dumper(@limits);
                                    my $minMessage = "";
                                    my $maxMessage = "";

                                    #my $message="";
                                    #print "Valid range is";
                                    if ( $limits[0] ne "~" ) {
                                        $minMessage = " <$limits[0]";
                                    }
                                    if ( defined( $limits[1] ) ) {
                                        $maxMessage = " >$limits[1]";
                                    }
                                    if (    length($minMessage)
                                        and length($maxMessage) )
                                    {
                                        $message =
"Output #$i: $fields[$FieldsToProcess[$j]] = $field (valid range is ";
                                        $message = $minMessage . " and"
                                          . $maxMessage . "); ";
                                    }
                                    else {
                                        $message =
"Output #$i: $fields[$FieldsToProcess[$j]] = $field (valid range is $minMessage$maxMessage); ";
                                    }

                                }
                                else {
                                    my $doubledot =
                                      $ranges[ $FieldsToProcess[$j] ] =~ tr/://;

                            #print "Dos puntos = $doubledot en $ranges[$j-2]\n";
                                    my @limits = split( /:/,
                                        $ranges[ $FieldsToProcess[$j] ] );

                                    #print "$ranges[$j-2]\n";
                                    #print Dumper(@ranges);
                                    my $k = $j - 3;

                                  #print "Indice $k y ranges = $ranges[$j-2]\n";
                                  #print Dumper(@limits);
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
"Output #$i: $fields[$FieldsToProcess[$j]] = $field (valid range is ";
                                        $message .= $minMessage . " and"
                                          . $maxMessage . "); ";
                                    }
                                    else {
                                        $message =
"Output #$i: $fields[$FieldsToProcess[$j]] = $field (valid range is $minMessage$maxMessage); ";
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
                            $PluginOutput      = "Error. Output $i not found.";
                            $_[1]              = $PluginOutput;
                            return $PluginReturnValue;
                        }
                    }

                }
            }
            else {    # Output list
                my @OutputLines = split( /,/, $Nagios->opts->output );
                $length = @OutputLines;

                #print Dumper(@OutputLines);
                #print MIB_UPS_OUTPUT.".4.1.$j.$OutputLines[$i]\n";
                my $outputLine;
                my $lengthFields = @FieldsToProcess;
                for ( $i = 0 ; $i < $length ; $i++ ) {
                    $outputLine = $OutputLines[$i];

                    #print "outputline = $outputLine\n";
                    for ( $j = 0 ; $j < $lengthFields ; $j++ ) {
                        if (
                            defined(
                                $$TableRef{
                                        MIB_UPS_OUTPUT . ".4.1."
                                      . ( $FieldsToProcess[$j] + 2 )
                                      . ".$outputLine"
                                }
                            )
                          )
                        {
                            $field =
                              $$TableRef{ MIB_UPS_OUTPUT . ".4.1."
                                  . ( $FieldsToProcess[$j] + 2 )
                                  . ".$outputLine" };
                            if ( ( $FieldsToProcess[$j] + 2 ) == 3 )
                            {    # Field 'current' must be divided by 10
                                $field = $field / 10;
                            }

                            elsif ( defined( $Nagios->opts->power )
                                && ( ( $FieldsToProcess[$j] + 2 ) == 5 ) )
                            {
                                my $upsOutPower = $$TableRef{ MIB_UPS_OUTPUT
                                      . ".4.1.4.$outputLine" };
                                if ( !defined($upsOutPower) ) {
                                    $_[1] =
"Error in True power of output $outputLine calculating percent load";
                                    return UNKNOWN;
                                }
                                else {
                                    $field = int(
                                        (
                                            (
                                                $upsOutPower /
                                                  $Nagios->opts->power
                                            ) * 100
                                        ) + 0.5
                                    );
                                }
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
                                  "All Values in all Outputs are in range.";
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
                                    my $minMessage = "";
                                    my $maxMessage = "";
                                    if ( $limits[0] ne "~" ) {
                                        $minMessage = " <$limits[0]";
                                    }
                                    if ( defined( $limits[1] ) ) {
                                        $maxMessage = " >$limits[1]";
                                    }
                                    if (    length($minMessage)
                                        and length($maxMessage) )
                                    {
                                        $message =
"Output #$outputLine: $fields[$FieldsToProcess[$j]] = $field (valid range is ";
                                        $message .= $minMessage . " and"
                                          . $maxMessage . "); ";
                                    }
                                    else {
                                        $message =
"Output #$outputLine: $fields[$FieldsToProcess[$j]] = $field (valid range is $minMessage$maxMessage); ";
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
"Output #$outputLine: $fields[$FieldsToProcess[$j]] = $field (valid range is ";
                                        $message .= $minMessage . " and"
                                          . $maxMessage . "); ";

                                    }
                                    else {
                                        $message =
"Output #$outputLine: $fields[$j-2] = $field (valid range is $minMessage$maxMessage); ";
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
                            #print "No existe output\n";
                            #si no existe debo marcar alg�n error??
                            $PluginReturnValue = UNKNOWN;
                            $PluginOutput =
                              "Error. Output $OutputLines[$i] not found.";
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
                    $PluginOutput = "All Values in all Outputs are in range.";
                    $PluginReturnValue = OK;
                }
            }
        }

        #Performance Data

        if ( !defined( $Nagios->opts->output ) ) {    #All Output Lines
            my $NumLines = $SNMPSession->get_request(
                -varbindlist => [ MIB_UPS_OUTPUT . ".3" ] );
            $NumLines = $$NumLines{ MIB_UPS_OUTPUT . ".3" };
            for ( $i = 1 ; $i <= $NumLines ; $i++ ) {

                if (   ( $arrayCriticalRanges[0] ne '' )
                    || ( $arrayWarningRanges[0] ne '' ) )
                {
                    $field = $$TableRef{ MIB_UPS_OUTPUT . ".4.1.2.$i" };
                    $perfdata .= "'Out$i$fields[0]'=$field" . "V;;;; ";
                }
                if (   ( $arrayCriticalRanges[1] ne '' )
                    || ( $arrayWarningRanges[1] ne '' ) )
                {
                    $field = $$TableRef{ MIB_UPS_OUTPUT . ".4.1.3.$i" } / 10;

                    $perfdata .= "'Out$i$fields[1]'=$field" . "A;;;; ";
                }
                if (   ( $arrayCriticalRanges[2] ne '' )
                    || ( $arrayWarningRanges[2] ne '' ) )
                {
                    $field = $$TableRef{ MIB_UPS_OUTPUT . ".4.1.4.$i" };
                    $perfdata .= "'Out$i$fields[2]'=$field" . "W;;;; ";
                }
                if (   ( $arrayCriticalRanges[3] ne '' )
                    || ( $arrayWarningRanges[3] ne '' ) )
                {
                    if ( defined( $Nagios->opts->power ) ) {
                        my $upsOutPower =
                          $$TableRef{ MIB_UPS_OUTPUT . ".4.1.4.$i" };
                        $field = int(
                            ( ( $upsOutPower / $Nagios->opts->power ) * 100 ) +
                              0.5 );
                    }
                    else {
                        $field = $$TableRef{ MIB_UPS_OUTPUT . ".4.1.5.$i" };
                    }

                    $perfdata .= "'Out$i$fields[3]'=$field" . "%;;;; ";
                }
            }
        }
        else {
            my @OutputLines = split( /,/, $Nagios->opts->output );
            my $length      = @OutputLines;
            my $outputLine;
            for ( $i = 0 ; $i < $length ; $i++ ) {
                $outputLine = $OutputLines[$i];
                if (   ( $arrayCriticalRanges[0] ne '' )
                    || ( $arrayWarningRanges[0] ne '' ) )
                {
                    $field =
                      $$TableRef{ MIB_UPS_OUTPUT . ".4.1.2.$outputLine" };
                    $perfdata .= "'Out$outputLine$fields[0]'=$field" . "V;;;; ";
                }
                if (   ( $arrayCriticalRanges[1] ne '' )
                    || ( $arrayWarningRanges[1] ne '' ) )
                {
                    $field =
                      ( $$TableRef{ MIB_UPS_OUTPUT . ".4.1.3.$outputLine" } ) /
                      10;
                    $perfdata .= "'Out$outputLine$fields[1]'=$field" . "A;;;; ";
                }
                if (   ( $arrayCriticalRanges[2] ne '' )
                    || ( $arrayWarningRanges[2] ne '' ) )
                {
                    $field =
                      $$TableRef{ MIB_UPS_OUTPUT . ".4.1.4.$outputLine" };
                    $perfdata .= "'Out$outputLine$fields[2]'=$field" . "W;;;; ";
                }
                if (   ( $arrayCriticalRanges[3] ne '' )
                    || ( $arrayWarningRanges[3] ne '' ) )
                {
                    if ( defined( $Nagios->opts->power ) ) {
                        my $upsOutPower =
                          $$TableRef{ MIB_UPS_OUTPUT . ".4.1.4.$outputLine" };
                        $field = int(
                            ( ( $upsOutPower / $Nagios->opts->power ) * 100 ) +
                              0.5 );
                    }
                    else {
                        $field =
                          $$TableRef{ MIB_UPS_OUTPUT . ".4.1.5.$outputLine" };
                    }
                    $perfdata .= "'Out$outputLine$fields[3]'=$field" . "%;;;; ";
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
