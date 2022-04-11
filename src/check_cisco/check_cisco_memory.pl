#!/usr/bin/perl -w

# check_cisco_memory Nagios Plugin
# Checks the used and fragmented memory  on a  CISCO_MEMORY_POOL_MIB SNMP compliant device.
# Type check_cisco_memory --help for getting more info and examples.
#
# This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
# It may be used, redistributed and/or modified under the terms of the GNU 
# General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).
#
# HISTORY
#
# v0.3b: Modified the method for calculating fragmentation percent


# MODULE DECLARATION

use strict;

use Monitoring::Plugin;
use Net::SNMP qw(SNMP_VERSION_2C);



# FUNCTION DECLARATION

sub CreateNagiosManager ();
sub ManageArguments ();
sub PerformCheck ();


# CONSTANT DEFINITION

use constant CISCO_MEMORY_POOL_MIB => '.1.3.6.1.4.1.9.9.48';
use constant CISCO_MEMORY_POOL_ENTRY => '.1.1.1';
use constant CISCO_MEMORY_POOL_NAME => '.2';
use constant CISCO_MEMORY_POOL_USED => '.5';
use constant CISCO_MEMORY_POOL_FREE => '.6';
use constant CISCO_MEMORY_POOL_LARGEST_FREE => '.7';

use constant MODE_TEST => 1;
use constant MODE_CHECK => 2;

use constant NAME => 	'check_cisco_memory';
use constant VERSION => '0.3b';
use constant USAGE => 	"Usage:\n".
			"check_cisco_memory -H <hostname> -p <memory pool id> -w <warning value> -c <critical value>\n".
			"\t\t[-C <SNMP Community>] [-e <SNMP Version>]\n".
			"\t\t[-u <SNMP security name>] [-a <SNMP authentication protocol> -A <SNMP authentication pass phrase>] [-x <SNMP privacy protocol> -X <SNMP privacy pass phrase>]\n".
			"\t\t[-P <SNMP port>] [-t <SNMP timeout>]\n".
			"\t\t[-V <version>]\n";
use constant BLURB => 	"This plugin checks the memory usage on a  CISCO_MEMORY_POOL_MIB SNMP compliant device.\n";
use constant LICENSE => "This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY\n".
			"It may be used, redistributed and/or modified under the terms of the GNU\n".
			"General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).\n";
use constant EXAMPLE => "\n\n".
			"Example:\n".
			"\n".
			"check_cisco_memory -H 192.168.0.1 -p 1 -w 80,60 -c 95,80\n".
			"\n".
			"Checks the pool id 1 memory usage and fragmented memory flag on a CISCO_MEMORY_POOL_MIB\n" .
			"compliant device using 'public' as community string and default port 161.\n" .
			"Plugin returns WARNING if memory usage is above 80% or fragmented memory is above 60%,\n" .
			"or CRITICAL if memory usage is above 95% or fragmented memory is above 80%.\n".
			"In other case it returns OK if check has been successfully performed.\n";


# VARIABLE DEFINITION

my $Nagios;
my $Error;
my $PluginMode;
my $PluginReturnValue , my $PluginOutput='';


# MAIN FUNCTION

# Get command line arguments
$Nagios = &CreateNagiosManager(USAGE, VERSION, BLURB, LICENSE, NAME, EXAMPLE);
eval {$Nagios->getopts};

if (!$@) {
	if (&ManageArguments($Nagios, $Error, $PluginMode)) {
		# Argument checking passed
		if ($PluginMode == MODE_TEST) {
			$PluginReturnValue = &TestHost($Nagios, $PluginOutput);
			$PluginOutput = "TEST MODE\n\n" . $PluginOutput;
		}
		else {
			$PluginReturnValue = &PerformCheck($Nagios, $PluginOutput);
		}
	}
	else {
		# Error checking arguments
		$PluginOutput = $Error;
		$PluginReturnValue = UNKNOWN;
	}
	$Nagios->nagios_exit($PluginReturnValue ,$PluginOutput);
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
	# Add argument resource id
	$Nagios->add_arg(spec => 'poolid|p=s',
				help => 'Memory pool id',
				required => 0);
					
	# Add argument community
	$Nagios->add_arg(spec => 'community|C=s',
				help => 'SNMP agent community (default: public)',
				default => 'public',
				required => 0);				
	# Add argument version
	$Nagios->add_arg(spec => 'snmpver|E=s',
				help => 'SNMP protocol version (default: 2)',
				default => '2',
				required => 0);				
	# Add argument port
	$Nagios->add_arg(spec => 'port|P=i',
				help => 'SNMP agent port (default: 161)',
				default => 161,
				required => 0);
	# Add argument snmp user  (version 3)
	$Nagios->add_arg(spec => 'snmpuser|u=s',
				help => 'SNMPv3 username',				
				required => 0);						
	# Add argument snmp authentication protocol (version 3)
	$Nagios->add_arg(spec => 'snmpauthprotocol|a=s',
				help => 'SNMPv3 authentication protocol (default: MD5)',
				default => 'MD5',				
				required => 0);										
	# Add argument snmp authentication pass phrase (version 3)
	$Nagios->add_arg(spec => 'snmpauthpassword|A=s',
				help => 'SNMPv3 authentication pass phrase',				
				required => 0);						
	# Add argument snmp encryption protocol (version 3)
	$Nagios->add_arg(spec => 'snmpprivprotocol|x=s',
				help => 'SNMPv3 privacy protocol (default: DES)',
				default => 'DES',				
				required => 0);										
	# Add argument snmp privace pass phrase (version 3)
	$Nagios->add_arg(spec => 'snmpprivpassword|X=s',
				help => 'SNMPv3 privacy pass phrase',				
				required => 0);	
				
	# Add argument warning
	$Nagios->add_arg(spec => 'warning|w=s',
				help => "Warning range list with format <memory usage>,<fragmented memory>",
				required => 0);
	# Add argument critical
	$Nagios->add_arg(spec => 'critical|c=s',
				help => "Critical range list with format <memory usage>,<fragmented memory>",
				required => 0);
								
	# Return value
	return $Nagios;
}


# Checks argument values and sets some default values
# Input: Nagios Plugin object
# Output: Error description string
# Return value: True if arguments ok, false if not

sub ManageArguments() {
	my $Nagios = $_[0];
	my @IfRange;
	my $ArgOK;
	my $ThresholdsFormat;
	
	# Check if agent port number is > 0
	if ( $Nagios->opts->port <= 0 ) {
		$_[3] = "Invalid SNMP agent port: must be greater than zero";
		return 0;
	}
	# Check plugin test mode
	if ( (defined($Nagios->opts->warning)) && (defined($Nagios->opts->critical))) {
		$_[2] = MODE_CHECK;
			# Check warning value list
		if ( $Nagios->opts->warning !~ /^\d+,\d+$/) {
			$_[1] = "Invalid warning threshold list: must be a comma separated used and fragmented memory thresholds.";
			return 0;
		}
	
		# Check critical value list
		if ( $Nagios->opts->critical !~/^(\d+,)*\d+$/) {
			$_[1] = "Invalid critical threshold list: must be a comma separated used and fragmented memory thresholds.";
			return 0;
		}
	}
	else {
		if ( !defined($Nagios->opts->warning) && !defined($Nagios->opts->critical)) {
			$_[2] = MODE_TEST;
		
		}
		else {
			$_[1] = "Invalid argument set";
			return 0;		
		}
	}
	return 1;
}

# Checks if host supports CISCO_MEMORY_POOL_MIB related info.
# If true, it returns info about environmental sensors
# Input: Nagios Plugin object
# Output: Test output string
# Return value: OK if test passed, UNKNOWN if not.

sub TestHost() {
	my $SNMPSession;
	my $SNMPError;
	my $Output="";
	my $PluginReturnValue;
	my $OID_ciscoMemoryPoolUsed = CISCO_MEMORY_POOL_MIB . CISCO_MEMORY_POOL_ENTRY .  CISCO_MEMORY_POOL_USED;
	my $OID_ciscoMemoryPoolFree = CISCO_MEMORY_POOL_MIB . CISCO_MEMORY_POOL_ENTRY .  CISCO_MEMORY_POOL_FREE;
	my $OID_ciscoMemoryPoolName = CISCO_MEMORY_POOL_MIB . CISCO_MEMORY_POOL_ENTRY .  CISCO_MEMORY_POOL_NAME;
	my $OID_ciscoMemoryPoolLargestFree = CISCO_MEMORY_POOL_MIB . CISCO_MEMORY_POOL_ENTRY .  CISCO_MEMORY_POOL_LARGEST_FREE;
		# Start new SNMP session
	#~ ($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $Nagios->opts->hostname, -community => $Nagios->opts->community, -version => $Nagios->opts->snmpver, -port => $Nagios->opts->port, -timeout => $Nagios->opts->timeout);
	if (defined($Nagios->opts->snmpauthpassword) ) { #SNMP v3
		if (defined($Nagios->opts->snmpprivpassword)) { #SNMP v3 with encryption			
			($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $Nagios->opts->hostname, 
									-version => '3', 
									-port => $Nagios->opts->port, 
									-username		=> $Nagios->opts->snmpuser, 
									-authpassword => $Nagios->opts->snmpauthpassword, 
									-authprotocol => $Nagios->opts->snmpauthprotocol, 
									-privpassword => $Nagios->opts->snmpprivpassword,
									-privprotocol => $Nagios->opts->snmpprivprotocol, 
									-timeout => $Nagios->opts->timeout);
		}
		else { #SNMP v3 without encryption
			($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $Nagios->opts->hostname, 
									-version => '3', 
									-port => $Nagios->opts->port, 
									-username		=> $Nagios->opts->snmpuser, 
									-authpassword => $Nagios->opts->snmpauthpassword, 
									-authprotocol => $Nagios->opts->snmpauthprotocol, 
									-timeout => $Nagios->opts->timeout);
			}
	}
	else { # Not SNMP v3
		($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $Nagios->opts->hostname, 
									-community => $Nagios->opts->community, 
									-version => $Nagios->opts->snmpver, 
									-port => $Nagios->opts->port, 
									-timeout => $Nagios->opts->timeout);
	}
	#~ ($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $Nagios->opts->hostname, -community => $Nagios->opts->community, -version => $Nagios->opts->snmpver, -port => $Nagios->opts->port, -timeout => $Nagios->opts->timeout);
	
	if (defined($SNMPSession)) {
		my $RequestResultIndex = $SNMPSession->get_entries(-columns => [ $OID_ciscoMemoryPoolName]);
		my $RequestResult = $SNMPSession->get_entries(-columns => [ CISCO_MEMORY_POOL_MIB . CISCO_MEMORY_POOL_ENTRY]);
		if (!defined($RequestResult) && !defined($RequestResultIndex)) {
			
			$SNMPError = $SNMPSession->error();
			if(defined($SNMPError) && ($SNMPError ne '')) {
				$_[1] = "SNMP Error: $SNMPError ";
			}
			else {
				$_[1] = "Empty data set recovered. Probably device didn't support CISCO-MEMORY_POOL_MIB";
				}
			$SNMPSession->close();
			return UNKNOWN;	
		}
		my $id;
		my $entId;
		my $Oid;
		my $status;
		my $desc="";
		$Output = "CISCO MEMORY DATA\n";
		
		foreach  $Oid (keys %{$RequestResultIndex}) {
			$id = (split(/\./, $Oid))[-1];
			$desc = $RequestResult->{$OID_ciscoMemoryPoolName.".$id"};
			
			$Output .= "Memory pool id: $id\t" .
					"Memory pool name: $desc\t" .
					"Memory free: ".$RequestResult->{$OID_ciscoMemoryPoolFree.".$id"}."\t" .
					"Memory Used: ".$RequestResult->{$OID_ciscoMemoryPoolUsed.".$id"}."\t" .
					"Memory largest free block = ".$RequestResult->{$OID_ciscoMemoryPoolLargestFree.".$id"}."\n";
		}
		$PluginReturnValue = OK;
		$SNMPSession->close();
	}
	else {
		$PluginReturnValue = UNKNOWN;
		$Output = "Test failed. No response from host.";

	}		
	$_[1]=$Output;
	
	return $PluginReturnValue;
}


# Performs whole check: 
# Input: Nagios Plugin object
# Output: Plugin output string
# Return value: Plugin return value

sub PerformCheck() {
	my $OID_ciscoMemoryPoolUsed = CISCO_MEMORY_POOL_MIB . CISCO_MEMORY_POOL_ENTRY .  CISCO_MEMORY_POOL_USED;
	my $OID_ciscoMemoryPoolFree = CISCO_MEMORY_POOL_MIB . CISCO_MEMORY_POOL_ENTRY .  CISCO_MEMORY_POOL_FREE;
	my $OID_ciscoMemoryPoolName = CISCO_MEMORY_POOL_MIB . CISCO_MEMORY_POOL_ENTRY .  CISCO_MEMORY_POOL_NAME;
	my $OID_ciscoMemoryPoolLargestFree = CISCO_MEMORY_POOL_MIB . CISCO_MEMORY_POOL_ENTRY .  CISCO_MEMORY_POOL_LARGEST_FREE;
	
	my $poolId = 1;
	
	my $Nagios = $_[0];
	
	my $SNMPSession;
	my $SNMPError;
	my @RequestItems;
	my $RequestResult;
	
	my $MemoryUsage;
	my $Interval;
	
	my $PluginOutput;
	my $PluginReturnValue = UNKNOWN;
	my $PerformanceData;		
	
	# Start new SNMP session
	if (defined($Nagios->opts->snmpauthpassword) ) { 
		# SNMP v3
		if (defined($Nagios->opts->snmpprivpassword)) { 
			# SNMP v3 with encryption			
			($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $Nagios->opts->hostname, 
									-version => '3', 
									-port => $Nagios->opts->port, 
									-username		=> $Nagios->opts->snmpuser, 
									-authpassword => $Nagios->opts->snmpauthpassword, 
									-authprotocol => $Nagios->opts->snmpauthprotocol, 
									-privpassword => $Nagios->opts->snmpprivpassword,
									-privprotocol => $Nagios->opts->snmpprivprotocol, 
									-timeout => $Nagios->opts->timeout);
		}
		else { 
			# SNMP v3 without encryption
			($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $Nagios->opts->hostname, 
									-version => '3', 
									-port => $Nagios->opts->port, 
									-username		=> $Nagios->opts->snmpuser, 
									-authpassword => $Nagios->opts->snmpauthpassword, 
									-authprotocol => $Nagios->opts->snmpauthprotocol, 
									-timeout => $Nagios->opts->timeout);
			}
	}
	else { 
		# SNMP v1 or v2c
		($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $Nagios->opts->hostname, 
									-community => $Nagios->opts->community, 
									-version => $Nagios->opts->snmpver, 
									-port => $Nagios->opts->port, 
									-timeout => $Nagios->opts->timeout);
	}
	
	if (defined($SNMPSession)) {
 		# Define data to retrieve
		my @arrayCritical = split(/,/,$Nagios->opts->critical.',dummy'); 
		my @arrayWarning = split(/,/,$Nagios->opts->warning.',dummy'); 
		
		$poolId = $Nagios->opts->poolid if defined $Nagios->opts->poolid;
		$OID_ciscoMemoryPoolName .=  '.' .$poolId ;
 		$OID_ciscoMemoryPoolUsed .=  '.' .$poolId ;
 		$OID_ciscoMemoryPoolFree .=  '.' .$poolId ;
		$OID_ciscoMemoryPoolLargestFree .=  '.' .$poolId ;
		
 		push (@RequestItems, $OID_ciscoMemoryPoolFree);
 		push (@RequestItems, $OID_ciscoMemoryPoolUsed);
 		push (@RequestItems, $OID_ciscoMemoryPoolName);
		push (@RequestItems, $OID_ciscoMemoryPoolLargestFree);
		
		# Go for it
		if (defined ($RequestResult = $SNMPSession->get_request(-varbindlist => \@RequestItems))) {
			if ($RequestResult->{$OID_ciscoMemoryPoolFree} =~ /^\d+$/ && $RequestResult->{$OID_ciscoMemoryPoolUsed} =~ /^\d+$/ ) {
				# Numeric values retrieved for storage variables
				my $MemoryUsage = $RequestResult->{$OID_ciscoMemoryPoolUsed};
				my $MemoryFree = $RequestResult->{$OID_ciscoMemoryPoolFree};
				my $MemoryUsagePercent = ($MemoryUsage)*100/($MemoryFree + $MemoryUsage);
				
				my $WarningOutput ="";
				my $CriticalOutput ="";
				my $OkOutput ="";
				
				# Check thresholds and set plugin output
				$PluginReturnValue = $Nagios->check_threshold(check => $MemoryUsagePercent, warning => $arrayWarning[0], critical => $arrayCritical[0]);			
	
				my $description = "'$RequestResult->{$OID_ciscoMemoryPoolName}'" ;
				if ( $PluginReturnValue == CRITICAL ) {
					$CriticalOutput .= sprintf($description. ' memory usage (%.1f%%) is above %d%%.', $MemoryUsagePercent, $arrayCritical[0]);
				}
				elsif ( $PluginReturnValue == WARNING ) {
					$WarningOutput .= sprintf($description.' memory usage (%.1f%%) is above %d%%.', $MemoryUsagePercent, $arrayWarning[0]);
				}
				else {
					$OkOutput .= sprintf($description.' memory usage = %.1f%% (%d of %d bytes)', $MemoryUsagePercent, $MemoryUsage, $MemoryFree+$MemoryUsage);
				}
				
				#Set used memory performance data
				$PerformanceData = sprintf('MemUsed=%.1f%%;%d;%d;0;100', $MemoryUsagePercent, $arrayWarning[0], $arrayCritical[0]);
				
				# Fragmented memory
				my $MemoryPoolLargestFree = $RequestResult->{$OID_ciscoMemoryPoolLargestFree};
				#my $MemoryFragmentedPercent = (1- (($MemoryPoolLargestFree) / ($MemoryFree+$MemoryUsage)))*100;
				my $MemoryFragmentedPercent = (1 - ($MemoryPoolLargestFree / $MemoryFree))*100;
				
				$PluginReturnValue = $Nagios->check_threshold(check => $MemoryFragmentedPercent, warning => $arrayWarning[1], critical => $arrayCritical[1]);			
				if ( $PluginReturnValue == CRITICAL ) {
					if ($CriticalOutput ne '') {
						$CriticalOutput .= ' and' ;
					}
					else {
						$CriticalOutput = $description;
						}
					$CriticalOutput .= sprintf(' fragmented memory flag (%.1f%%) is above %d%%.', $MemoryFragmentedPercent, $arrayCritical[1]);
				}
				elsif ( $PluginReturnValue == WARNING ) {
					if ($WarningOutput ne '') {
						$WarningOutput .= ' and';
					}
					else {
						$WarningOutput = $description;
						}
					$WarningOutput .= sprintf(' fragmented memory flag (%.1f%%) is above %d%%.', $MemoryFragmentedPercent, $arrayWarning[1]);
				}
				else {
					if ($OkOutput ne '') {
						$OkOutput .= ' and' ;						
					}
					else {
						$OkOutput = $description;
					}
					$OkOutput .= sprintf(' fragmented memory flag = %.1f%% (Largest block free %d bytes)', $MemoryFragmentedPercent, $MemoryPoolLargestFree);
				}
				
				#Set fragmented memory flag performance data
				$PerformanceData .= sprintf(' Fragmentation=%.1f%%;%d;%d;0;100', $MemoryFragmentedPercent, $arrayWarning[1], $arrayCritical[1]);
				
				
				if ($CriticalOutput ne '') {
					$PluginReturnValue = CRITICAL;	
					$PluginOutput = $CriticalOutput;
				}
				else {
					if ($WarningOutput ne '') {
						$PluginReturnValue = WARNING;	
						$PluginOutput = $WarningOutput;	
					}
					else {
						if ($PluginReturnValue eq UNKNOWN) { 
							$PluginOutput="";
						}
						else { 
							# OK
							$PluginOutput=$OkOutput;
						}
					}
				}

				$PluginOutput .= ' | ' . $PerformanceData;
			}
			else {
				$PluginOutput = "No data found for pool '$Nagios->{opts}->{poolid}'";
			}
		}
		else {
			$SNMPError = $SNMPSession->error();
        	$PluginOutput = "Error '$SNMPError' retrieving info ".
                        	"from agent $Nagios->{opts}->{hostname}:$Nagios->{opts}->{port} ".
                        	"using protocol $Nagios->{opts}->{snmpver} ";
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