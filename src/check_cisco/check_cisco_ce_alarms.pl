#!/usr/bin/perl -w

# check_cisco_ce_alarms Nagios Plugin
# Checks the alarms on a CISCO-CONTENT-ENGINE-MIB compliant device
# Type check_cisco_ce_alarms --help for getting more info and examples.
#
# This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
# It may be used, redistributed and/or modified under the terms of the GNU 
# General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).
#
# Vicente Gavara, Boreal labs
#
# HISTORY
#
# v.0.1b: Initial release.
#
# TODO
#
# Improve argument checking (warning and critical lists)


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

use constant CONTENT_ENGINE_MIB => '.1.3.6.1.4.1.9.9.178';
use constant CEE_ALARM_CRITICAL_COUNT_OID => CONTENT_ENGINE_MIB . '.1.6.2.1.0';
use constant CEE_ALARM_MAJOR_COUNT_OID => CONTENT_ENGINE_MIB . '.1.6.2.2.0';
use constant CEE_ALARM_MINOR_COUNT_OID => CONTENT_ENGINE_MIB . '.1.6.2.3.0';

use constant NAME => 	'check_cisco_ce_alarms';
use constant VERSION => '0.1b';
use constant USAGE => 	"Usage:\n".
						"check_cisco_ce_alarms -H <hostname>\n" .
							"\t\t[-C <SNMP Community>] [-e <SNMP Version>] [-P <SNMP port>] [-t <SNMP timeout>]\n" .
							"\t\t[-w <alarm level list> -c <alarm level list>]\n" .
							"\t\t[-V <version>]\n";
use constant BLURB => 	"This plugin checks the alarms on a CISCO-CONTENT-ENGINE-MIB compliant device.";
use constant LICENSE => "This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY\n".
						"It may be used, redistributed and/or modified under the terms of the GNU\n".
						"General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).\n";
use constant EXAMPLE => "\n\n".
						"Examples:\n".
						"\n".
						"check_cisco_ce_alarms -H 192.168.0.4\n".
						"\n".
						"If available, displays info of the device with address 192.168.0.4\n".
						"using SNMP protocol version 1 and 'public' as community\n".
						"(useful for checking compatibility)\n".
						"\n".
						"check_cisco_ce_alarms -H 192.168.0.4 -w M,N -c C\n".
						"Checks content engine alarms on host 192.168.0.4\n".
						"using SNMP protocol version 1 and 'public' as community.\n".
						"Plugin returns CRITICAL if there is any critical (c) active alarm\n".
						"and WARNING if there's any minor (n) or major (m) active alarm.\n".
						"In other case it returns OK if check has been performed or UNKNOWN";



# VARIABLE DEFINITION

my $Nagios;
my $Error;
my $PluginMode;
my $PluginReturnValue, my $PluginOutput='';


# MAIN FUNCTION

# Get command line arguments
$Nagios = &CreateNagiosManager(USAGE, VERSION, BLURB, LICENSE, NAME, EXAMPLE);
eval {$Nagios->getopts};

if (!$@) {
	# Command line parsed
	if (&CheckArguments($Nagios, $Error, $PluginMode)) {
		# Argument checking passed
		$PluginReturnValue = &PerformCheck($Nagios, $PluginOutput)
	}
	else {
		# Error checking arguments
		$PluginOutput = $Error;
		$PluginReturnValue = UNKNOWN;
	}
	$Nagios->nagios_exit($PluginReturnValue,$PluginOutput);
}
else {
	# Error parsing command line
	$Nagios->nagios_exit(UNKNOWN,$@);
}

		
	
# FUNCTION DEFINITIONS

# Creates and configures a Nagios plugin object
# Input: strings (usage, version, blurb, license, name and example) to configure argument parsing functionality
# Return value: reference to a Nagios plugin object

sub CreateNagiosManager() {
	# Create GetOpt object
	my $Nagios = Monitoring::Plugin->new(usage => $_[0], version =>  $_[1], blurb =>  $_[2], license =>  $_[3], plugin =>  $_[4], extra =>  $_[5]);
	
	# Add argument hostname
	$Nagios->add_arg(spec => 'hostname|H=s',
				help => 'SNMP agent hostname or IP address',
				required => 1);				
					
	# Add argument community
	$Nagios->add_arg(spec => 'community|C=s',
				help => 'SNMP agent community (default: public)',
				default => 'public',
				required => 0);				
	# Add argument version
	$Nagios->add_arg(spec => 'snmpver|e=s',
				help => 'SNMP protocol version (default: 1)',
				default => '1',
				required => 0);				
	# Add argument port
	$Nagios->add_arg(spec => 'port|P=i',
				help => 'SNMP agent port (default: 161)',
				default => 161,
				required => 0);

	
	# Add argument warning
	$Nagios->add_arg(spec => 'warning|w=s',
				help => "Comma separated alarm criticity identifiers list. ".
						"Valid criticity identifiers are C (critical), M (major) and N (minor)",
				required => 0);
	# Add argument critical
	$Nagios->add_arg(spec => 'critical|c=s',
				help => "Comma separated alarm criticity identifiers list. ".
						"Valid criticity identifiers are C (critical), M (major) and N (minor)",
				required => 0);
								
	# Return value
	return $Nagios;
}


# Checks argument values and sets some default values
# Input: Nagios Plugin object
# Output: Error description string, Plugin mode
# Return value: True if arguments ok, false if not

sub CheckArguments() {
	my $Nagios = $_[0];
	
	# Check if agent port number is > 0
	if ( $Nagios->opts->port <= 0 ) {
		$_[1] = "Invalid SNMP agent port: must be greater than zero";
		return 0;
	}

	# Check warning value list
	if ( defined($Nagios->opts->warning) && ($Nagios->opts->warning !~ /^([CMN],)*[CMN]$/) ) {
		$_[1] = "Invalid warning list: must be a comma separated alarm criticity id (C, M or N) list";
		return 0;
	}

	# Check critical value list
	if ( defined($Nagios->opts->critical) && ($Nagios->opts->critical !~ /^([CMN],)*[CMN]$/) ) {
		$_[1] = "Invalid critical threshold list: must be a comma separated alarm criticity id (C, M or N) list";
		return 0;
	}
	
	return 1;
}


# Performs whole check: 
# Input: Nagios Plugin object
# Output: Plugin output string
# Return value: Plugin return value

sub PerformCheck() {
	my $Nagios = $_[0];
	
	my $SNMPSession;
	my $SNMPError;
	my $RequestResult;
	my $PluginOutput = '';
	my $PluginReturnValue = UNKNOWN;
	
	# Start new SNMP session
	($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $Nagios->opts->hostname, -community => $Nagios->opts->community, -version => $Nagios->opts->snmpver, -port => $Nagios->opts->port, -timeout => $Nagios->opts->timeout);
	if ( defined $SNMPSession ) {
		$RequestResult = $SNMPSession->get_request(-varbindlist => [CEE_ALARM_CRITICAL_COUNT_OID, CEE_ALARM_MAJOR_COUNT_OID, CEE_ALARM_MINOR_COUNT_OID]);
		
		if ( $RequestResult ) {
			# Data successfully retrieved. Check if exists active alarms
			if ( $RequestResult->{&CEE_ALARM_CRITICAL_COUNT_OID} > 0 ) {
				$PluginOutput = "Critical active alarms: $RequestResult->{&CEE_ALARM_CRITICAL_COUNT_OID}";
			}
			if ( $RequestResult->{&CEE_ALARM_MAJOR_COUNT_OID} > 0 ) {
				$PluginOutput .= ', ' if $PluginOutput ne '';
				$PluginOutput .= "Major active alarms: $RequestResult->{&CEE_ALARM_MAJOR_COUNT_OID}";
			}
			if ( $RequestResult->{&CEE_ALARM_MINOR_COUNT_OID} > 0 ) {
				$PluginOutput .= ', ' if $PluginOutput ne '';
				$PluginOutput .= "Minor active alarms: $RequestResult->{&CEE_ALARM_MINOR_COUNT_OID}";
			}
			
			if ( $PluginOutput eq '' ) {
				# No active alarms present
				$PluginOutput = 'No active alarms';
				$PluginReturnValue = OK;
			}
			else {
				# Active alarms present
				if ( defined $Nagios->opts->critical ) {
					# Check if critical condition is fetch
					if ( ($RequestResult->{&CEE_ALARM_CRITICAL_COUNT_OID} > 0 && $Nagios->opts->critical =~ /C/) ||
						 ($RequestResult->{&CEE_ALARM_MAJOR_COUNT_OID} > 0 && $Nagios->opts->critical =~ /M/) ||
						 ($RequestResult->{&CEE_ALARM_MINOR_COUNT_OID} > 0 && $Nagios->opts->critical =~ /N/) ) {
						 	$PluginReturnValue = CRITICAL;
						 }
				}
				if ( $PluginReturnValue == UNKNOWN && defined $Nagios->opts->warning ) {
					# No critical condition fetch, check if warning condition is fetch
					if ( ($RequestResult->{&CEE_ALARM_CRITICAL_COUNT_OID} > 0 && $Nagios->opts->warning =~ /C/) ||
						 ($RequestResult->{&CEE_ALARM_MAJOR_COUNT_OID} > 0 && $Nagios->opts->warning =~ /M/) ||
						 ($RequestResult->{&CEE_ALARM_MINOR_COUNT_OID} > 0 && $Nagios->opts->warning =~ /N/) ) {
						 	$PluginReturnValue = WARNING;
						 }					
				}
				if ( $PluginReturnValue == UNKNOWN ) {
					# Neither critical nor warning conditions fetch
					$PluginReturnValue = OK;
				}
			}
		}
		else {
			$PluginOutput = 'Error recovering content engine alarm counters';
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