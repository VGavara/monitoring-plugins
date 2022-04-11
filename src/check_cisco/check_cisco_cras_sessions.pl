#!/usr/bin/perl -w

# check_cisco_cras_sessions Nagios Plugin
#
# Checks the number of active sessions on a Cisco Remote Access Server 
# supporting the ciscoRemoteAccessMonitorMIB MIB.
# This nagios plugin is free software, and comes with ABSOLUTELY 
# NO WARRANTY. It may be used, redistributed and/or modified under 
# the terms of the GNU General Public Licence (see 
# http://www.fsf.org/licensing/licenses/gpl.txt).
#
# HISTORY
#
# v.0.1b: Initial release
#
# TODO
#


# MODULE DECLARATION

use strict;

use Monitoring::Plugin;
use Net::SNMP qw(SNMP_VERSION_2C);

# FUNCTION DECLARATION

sub createNagiosManager ();
sub checkArguments ();


# CONSTANT DEFINITION

use constant OID_MAXSESSIONSUPPORTABLE => '.1.3.6.1.4.1.9.9.392.1.1.1.0';

use constant OID_CRASACTIVITY => '.1.3.6.1.4.1.9.9.392.1.3';
use constant OID_CRASEMAILNUM => &OID_CRASACTIVITY . '.23.0';
use constant OID_CRASEMAILPEAK => &OID_CRASACTIVITY . '.25.0';
use constant OID_CRASIPSECNUM => &OID_CRASACTIVITY . '.26.0';
use constant OID_CRASIPSECPEAK => &OID_CRASACTIVITY . '.28.0';
use constant OID_CRASL2LNUM => &OID_CRASACTIVITY . '.29.0';
use constant OID_CRASL2LPEAK => &OID_CRASACTIVITY . '.31.0';
use constant OID_CRASLBNUM => &OID_CRASACTIVITY . '.32.0';
use constant OID_CRASLBPEAK => &OID_CRASACTIVITY . '.34.0';
use constant OID_CRASSVCNUM => &OID_CRASACTIVITY . '.35.0';
use constant OID_CRASSVCPEAK => &OID_CRASACTIVITY . '.37.0';
use constant OID_CRASWEBVPNNUM => &OID_CRASACTIVITY . '.38.0';
use constant OID_CRASWEBVPNPEAK => &OID_CRASACTIVITY . '.37.0';

use constant SESSION_NAMES => { CRASEMAIL => 'Email',
								CRASIPSEC => 'IPSec',
								CRASL2L => 'LAN to LAN',
								CRASLB => 'Load Balancing',
								CRASSVC => 'SSL VPN Client',
								CRASWEB => 'Web VPN'};
use constant SESSION_SHORT_NAMES => { CRASEMAIL => 'email',
										CRASIPSEC => 'ipsec',
										CRASL2L => 'l2l',
										CRASLB => 'lb',
										CRASSVC => 'svc',
										CRASWEB => 'webvpn'};
								
use constant SNMP_MAX_MSG_SIZE => 5120;

use constant NAME => 	'check_cisco_cras_sessions';
use constant VERSION => '0.1b';
use constant USAGE => 	"Usage:\ncheck_cisco_cras_sessions -H <hostname> [-w <warning threshold>] [-c <critical threshold>]\n".
						"\t\t[-C <SNMP Community>]  [E <SNMP Version>] [-P <SNMP port>]\n".
						"\t\t{[-s <session type> -S <session type> ...] [--percent]} [--total]\n".
						"\t\t[-V <version>]\n";
use constant BLURB => 	"This plugin checks the number of active sessions on a Cisco Remote Access Server\n".
						"supporting the ciscoRemoteAccessMonitorMIB MIB.";
use constant LICENSE => "This nagios plugin is free software, and comes with ABSOLUTELY\n".
						"no WARRANTY. It may be used, redistributed and/or modified under\n".
						"the terms of the GNU General Public Licence\n".
						"(see http://www.fsf.org/licensing/licenses/gpl.txt).\n";
use constant EXAMPLE => "\n\n".
						"Examples:\n".
						"check_cisco_cras_sessions -H 192.168.0.12\n".
						"\n".
						"Checks the number of sessions a host with address 192.168.0.12\n".
						"using SNMP protocol version 1 and 'public' as community\n".
						"Plugin returns always OK\n".
						"\n".
						"check_cisco_cras_sessions -H 192.168.0.12 -w 30 -c 50\n".
						"\n".
						"Similar to the previous example but returning WARNING if the number of sessions\n".
						"of any kind is higher than 30 and CRITICAL if it's higher than 50\n".
						"\n".
						"check_cisco_cras_sessions -H 192.168.0.12 -s email -s ipsec -w 30 -c 50\n".
						"\n".				
						"Similar to the previous example but just checking the Email and IPSec sessions.\n".
						"\n".
						"check_cisco_cras_sessions -H 192.168.0.12 -s email -s ipsec -T -w 30 -c 50 \n".
						"\n".
						"Similar to the previous example but totalizing the sessions, ie, returning WARNING\n".
						"if the sum of email and ipsec sessions is higher than 30 and CRITICAL if it's higher than 50\n" .
						"\n".
						"check_cisco_cras_sessions -H 192.168.0.12 -p -w 30 -c 50 \n".
						"\n".
						"Sessions of any kind are checked and their total is managed as percent over the device\n".
						"max supportable sessions. Thresholds and results are considered as percent\n";

								
# VARIABLE DEFINITION

my $nagios;
my $error;
my $pluginReturnValue, my $pluginOutput='';


# MAIN FUNCTION

# Get command line arguments
$nagios = &createNagiosManager(USAGE, VERSION, BLURB, LICENSE, NAME, EXAMPLE);
eval {$nagios->getopts};

if (!$@) {
	# Command line parsed
	if (&checkArguments($nagios, $error)) {
		# Argument checking passed
		$pluginReturnValue = &performCheck($nagios, $pluginOutput)	
	}
	else {
		# Error checking arguments
		$pluginOutput = $error;
		$pluginReturnValue = UNKNOWN;
	}
	$nagios->nagios_exit($pluginReturnValue,$pluginOutput);
}
else {
	# Error parsing command line
	$nagios->nagios_exit(UNKNOWN,$@);
}

		
	
# FUNCTION DEFINITIONS

# Creates and configures a Nagios plugin object
# Input: strings (usage, version, blurb, license, name and example) to configure argument parsing functionality
# Return value: reference to a Nagios plugin object

sub createNagiosManager() {
	# Create GetOpt object
	my $nagios = Monitoring::Plugin->new(usage => $_[0], version =>  $_[1], blurb =>  $_[2], license =>  $_[3], plugin =>  $_[4], extra =>  $_[5]);
	
	# Add argument hostname
	$nagios->add_arg(spec => 'hostname|H=s',
				help => 'SNMP agent hostname or IP address',
				required => 1);				
					
	# Add argument community
	$nagios->add_arg(spec => 'community|C=s',
				help => 'SNMP agent community (default: public)',
				default => 'public',
				required => 0);				
	# Add argument version
	$nagios->add_arg(spec => 'snmpver|E=s',
				help => 'SNMP protocol version (default: 2)',
				default => '2',
				required => 0);				
	# Add argument port
	$nagios->add_arg(spec => 'port|P=i',
				help => 'SNMP agent port (default: 161)',
				default => 161,
				required => 0);
	
	# Add argument session
	$nagios->add_arg(spec => 'session|s=s@',
				help => "Session type to check: email, ipsec, l2l (LAN to LAN), lb (load balancing), svc (SSL VPN client), webvpn. Can be defined multiple times",
				required => 0);
	
	# Add argument total
	$nagios->add_arg(spec => 'total|T',
				help => "Check is performed taking the sum of all sessions instead of every one",
				required => 0);
	
	# Add argument percent
	$nagios->add_arg(spec => 'percent|p',
				help => "Check is performed taking the percent of all sesions based on device max supportable sessions",
				required => 0);
					
	# Add argument warning
	$nagios->add_arg(spec => 'warning|w=s',
				help => "Warning threshold. Applies to any session type except if using the -t argument. In this case applies to the total of all sessions",
				required => 0);
	# Add argument critical
	$nagios->add_arg(spec => 'critical|c=s',
				help => "Critical threshold. Applies to any session type except if using the -t argument. In this case applies to the total of all sessions",
				required => 0);				
	
	# Return value
	return $nagios;
}


# Checks argument values and sets some default values
# Input: Nagios Plugin object
# Output: Error description string
# Return value: True if arguments ok, false if not

sub checkArguments() {
	my $nagios = $_[0];
	
	# Check SNMP port
	if ( $nagios->opts->port <= 0 ) {
		$_[1] = "Invalid SNMP agent port: must be greater than zero";
		return 0;
	}
	
	# Check if session takes a valid value
	if ( (defined $nagios->opts->session) ) {
		my $isValid;
		my $session;
		foreach $session (@{$nagios->opts->session}) {
			$isValid = 0;
			foreach my $validSession (values(%{&SESSION_SHORT_NAMES})) {
				if ( $session eq $validSession) {
					$isValid = 1;
					last;
				}
			}
			last if ! $isValid;
		}
		if ( ! $isValid ) {
			$_[1] = "Invalid session: '$session'";
			return 0;
		}
	}
	
	return 1;
}


# Performs whole check: 
# Input: Nagios Plugin object
# Output: Plugin output string
# Return value: Plugin return value

sub performCheck() {
 	my $nagios = $_[0];
  	my $pluginOutput;
 	my $pluginReturnValue = UNKNOWN;
 	my $SNMPSession;
 	my $SNMPError;
	
	
	# Start new SNMP session
 	($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $nagios->opts->hostname, 
													-community => $nagios->opts->community, 
													-version => $nagios->opts->snmpver, 
													-port => $nagios->opts->port, 
													-timeout => $nagios->opts->timeout,
													-maxmsgsize => SNMP_MAX_MSG_SIZE);
	
	if (!defined($SNMPSession)) {
		$pluginOutput = "Error '$SNMPError' starting session";
	}
 	else {
 		my @OIDs;
 		
        # Define the OIDs to recover
        if ( defined $nagios->opts->session ) {
        	foreach my $session ( @{$nagios->opts->session} ) {
        		if ( $session eq &SESSION_SHORT_NAMES->{CRASEMAIL} ) {
        			push @OIDs, &OID_CRASEMAILNUM;
				}
        		elsif ( $session eq &SESSION_SHORT_NAMES->{CRASIPSEC} ) {
        			push @OIDs, &OID_CRASIPSECNUM;
				}
        		elsif ( $session eq &SESSION_SHORT_NAMES->{CRASL2L} ) {
        			push @OIDs, &OID_CRASL2LNUM;
        		}
        		elsif ( $session eq &SESSION_SHORT_NAMES->{CRASLB} ) {
        			push @OIDs, &OID_CRASLBNUM;
        		}
        		elsif ( $session eq &SESSION_SHORT_NAMES->{CRASSVC} ) {
        			push @OIDs, &OID_CRASSVCNUM;
        		}
        		elsif ( $session eq &SESSION_SHORT_NAMES->{CRASWEB} ) {
        			push @OIDs, &OID_CRASWEBVPNNUM;
        		}
        	}
        }
        else {
        	push @OIDs, &OID_CRASEMAILNUM;
        	push @OIDs, &OID_CRASIPSECNUM;
        	push @OIDs, &OID_CRASL2LNUM;
        	push @OIDs, &OID_CRASLBNUM;
        	push @OIDs, &OID_CRASSVCNUM;
        	push @OIDs, &OID_CRASWEBVPNNUM;
        }
        if ( defined $nagios->opts->percent ) {
        	push @OIDs, &OID_MAXSESSIONSUPPORTABLE;
        }
        
        # Go for them
        if ( my $requestResult = $SNMPSession->get_request(-varbindlist => \@OIDs) ) {
        	# OID values successfully retrieved. Calculate sessions
        	my $sessions = 0;
        	my $sessionName = 0;
        	if ( defined $nagios->opts->total ) {
        		# Totalize sessions
        		$sessions += ($requestResult->{&OID_CRASEMAILNUM} or 0);
        		$sessions += ($requestResult->{&OID_CRASIPSECNUM} or 0);
        		$sessions += ($requestResult->{&OID_CRASL2LNUM} or 0);
        		$sessions += ($requestResult->{&OID_CRASLBNUM} or 0);
        		$sessions += ($requestResult->{&OID_CRASSVCNUM} or 0);
        		$sessions += ($requestResult->{&OID_CRASWEBVPNNUM} or 0);
        	}
        	else {
        		# Find the highest session value and its name
        		if ( defined $requestResult->{&OID_CRASEMAILNUM} && $requestResult->{&OID_CRASEMAILNUM} > $sessions ) {
       				$sessions = $requestResult->{&OID_CRASEMAILNUM};
       				$sessionName = &SESSION_NAMES->{CRASEMAIL};
        		}
        		if ( defined $requestResult->{&OID_CRASIPSECNUM} && $requestResult->{&OID_CRASIPSECNUM} > $sessions ) {
       				$sessions = $requestResult->{&OID_CRASIPSECNUM};
       				$sessionName = &SESSION_NAMES->{CRASIPSEC};
        		}        		
        		if ( defined $requestResult->{&OID_CRASL2LNUM} && $requestResult->{&OID_CRASL2LNUM} > $sessions ) {
       				$sessions = $requestResult->{&OID_CRASL2LNUM};
       				$sessionName = &SESSION_NAMES->{CRASL2L};
        		}  
        		if ( defined $requestResult->{&OID_CRASLBNUM} && $requestResult->{&OID_CRASLBNUM} > $sessions ) {
       				$sessions = $requestResult->{&OID_CRASLBNUM};
       				$sessionName = &SESSION_NAMES->{CRASLB};
        		} 
        		if ( defined $requestResult->{&OID_CRASSVCNUM} && $requestResult->{&OID_CRASSVCNUM} > $sessions ) {
       				$sessions = $requestResult->{&OID_CRASSVCNUM};
       				$sessionName = &SESSION_NAMES->{CRASSVC};
        		} 
        		if ( defined $requestResult->{&OID_CRASWEBVPNNUM} && $requestResult->{&OID_CRASWEBVPNNUM} > $sessions ) {
       				$sessions = $requestResult->{&OID_CRASWEBVPNNUM};
       				$sessionName = &SESSION_NAMES->{CRASWEB};
        		}       		    		
        	}
       		if ( defined $nagios->opts->percent) {
       			# Porcentuate sessions
       			$sessions = $sessions / $requestResult->{&OID_MAXSESSIONSUPPORTABLE} * 100;
       		}        	
        	
        	# Set plugin return value
        	if ( $nagios->opts->warning || $nagios->opts->critical ) {
        		$pluginReturnValue = $nagios->check_threshold($sessions);
        	}
        	else {
        		$pluginReturnValue = OK;
        	}
        	
        	# Set plugin output
        	if ( $pluginReturnValue == OK ) {
        		$pluginOutput = 'All session counters are in the expected range';
        	}
        	else {
        		if ( defined $nagios->opts->total ) {
        			$pluginOutput = sprintf('Total session counters (%i%s) are out of the expected range', $sessions, (defined($nagios->opts->percent)?'% over the device max supportable sessions':' sessions'));
        		}
        		else {
        			$pluginOutput = sprintf($sessionName . ' session counters (%i%s) are out of the expected range', $sessions, (defined($nagios->opts->percent)?'% over the device max supportable sessions':' sessions'));
        		}
        	}
        	
        	# Set perfdata
        	if ( defined $nagios->opts->total ) {
        		$nagios->add_perfdata(	label => 'Sessions', 
        								value => $sessions, 
        								uom => (defined($nagios->opts->percent)?'%':'sessions'));
        	}
        	else {
        		$nagios->add_perfdata(	label => &SESSION_NAMES->{CRASEMAIL}, 
        								value => ($nagios->opts->percent ? $requestResult->{&OID_CRASEMAILNUM}/$requestResult->{&OID_MAXSESSIONSUPPORTABLE}*100 : $requestResult->{&OID_CRASEMAILNUM}), 
        								uom => (defined($nagios->opts->percent)?'%':'sessions')) if defined $requestResult->{&OID_CRASEMAILNUM};
        		$nagios->add_perfdata(	label => &SESSION_NAMES->{CRASIPSEC}, 
        								value => ($nagios->opts->percent ? $requestResult->{&OID_CRASIPSECNUM}/$requestResult->{&OID_MAXSESSIONSUPPORTABLE}*100 : $requestResult->{&OID_CRASIPSECNUM}), 
        								uom => (defined($nagios->opts->percent)?'%':'sessions')) if defined $requestResult->{&OID_CRASIPSECNUM};
        		$nagios->add_perfdata(	label => &SESSION_NAMES->{CRASL2L}, 
        								value => ($nagios->opts->percent ? $requestResult->{&OID_CRASL2LNUM}/$requestResult->{&OID_MAXSESSIONSUPPORTABLE}*100 : $requestResult->{&OID_CRASL2LNUM}), 
        								uom => (defined($nagios->opts->percent)?'%':'sessions')) if defined $requestResult->{&OID_CRASL2LNUM};
        		$nagios->add_perfdata(	label => &SESSION_NAMES->{CRASLB}, 
        								value => ($nagios->opts->percent ? $requestResult->{&OID_CRASLBNUM}/$requestResult->{&OID_MAXSESSIONSUPPORTABLE}*100 : $requestResult->{&OID_CRASLBNUM}), 
        								uom => (defined($nagios->opts->percent)?'%':'sessions')) if defined $requestResult->{&OID_CRASLBNUM};
        		$nagios->add_perfdata(	label => &SESSION_NAMES->{CRASSVC}, 
        								value => ($nagios->opts->percent ? $requestResult->{&OID_CRASSVCNUM}/$requestResult->{&OID_MAXSESSIONSUPPORTABLE}*100 : $requestResult->{&OID_CRASSVCNUM}), 
        								uom => (defined($nagios->opts->percent)?'%':'sessions')) if defined $requestResult->{&OID_CRASSVCNUM};
        		$nagios->add_perfdata(	label => &SESSION_NAMES->{CRASWEB}, 
        								value => ($nagios->opts->percent ? $requestResult->{&OID_CRASWEBVPNNUM}/$requestResult->{&OID_MAXSESSIONSUPPORTABLE}*100 : $requestResult->{&OID_CRASWEBVPNNUM}), 
        								uom => (defined($nagios->opts->percent)?'%':'sessions')) if defined $requestResult->{&OID_CRASWEBVPNNUM};
        	}
        }
        else {
        	$pluginOutput = 'Error \'' . $SNMPSession->error() . '\' getting SNMP data';
        }
		
		$SNMPSession->close();
	}
	
 	#Return result
 	$_[1] = $pluginOutput;
 	return $pluginReturnValue;
 }