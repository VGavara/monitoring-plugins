#!/usr/bin/perl -w

# check_cisco_sensor Nagios Plugin
#
# Checks sensors values on a CISCO_SENSOR_MIB compliant device
#
# This nagios plugin is free software, and comes with ABSOLUTELY 
# NO WARRANTY. It may be used, redistributed and/or modified under 
# the terms of the GNU General Public Licence (see 
# http://www.fsf.org/licensing/licenses/gpl.txt).

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

use constant OID_ENTSENSORVALUEENTRY => '1.3.6.1.4.1.9.9.91.1.1.1.1';
use constant OID_ENTPHYSICALDESC =>	'1.3.6.1.2.1.47.1.1.1.1.2';

use constant SENSOR_STATUS_OK => 1;
use constant SENSOR_STATUS_UNAVAILABLE => 2;
use constant SENSOR_STATUS_NONOPERATIONAL => 3;
use constant SENSOR_STATUS_NAMES => ('', 'Ok', 'Unavailable', 'Nonoperational');
use constant SENSOR_STATUS_DESCS => ( '', 
									  'The agent can read the sensor value.',
									  'Agent presently can not report the sensor value.',
									  'Agent believes the sensor is broken. The sensor could have a hard failure (disconnected wire), or a soft failure such as out-of-range, jittery, or wildly fluctuating readings.'
									);
use constant SENSOR_TYPES => 	('', 'Other', 'Unknown', 'VoltsAC', 'VoltsDC', 'Amperes', 'Watts', 'Hertz', 'Celsius', 'PercentRH', 'Rpm', 'Cmm', 'Truthvalue', 'SpecialEnum', 'Dbm');
use constant SENSOR_SCALES => 	('', 'Yocto', 'Zepto', 'Atto', 'Femto', 'Pico', 'Nano', 'Micro', 'Mili', 'Unit', 'Kilo', 'Mega', 'Giga', 'Tera', 'Exa', 'Peta', 'Zetta', 'Yotta');

use constant MODE_TEST => 	1;
use constant MODE_CHECK => 	2;

use constant NAME => 		'check_cisco_sensor';
use constant VERSION => 	'0.4b';
use constant USAGE => 		"Usage:\ncheck_cisco_sensor -H <hostname> [-e <sensor id>] [-l <sensor label name>]\n".
							"\t\t[-w <warning thresold> -c <critical thresold>]\n".
							"\t\t[-C <SNMP Community>]  [E <SNMP Version>] [-P <SNMP port>]\n".
							"\t\t[-V <version>]\n";
use constant BLURB => 	"This plugin checks the sensor value of a CISCO_SENSOR_MIB compliant device";
use constant LICENSE => "This nagios plugin is free software, and comes with ABSOLUTELY\n".
						"no WARRANTY. It may be used, redistributed and/or modified under\n".
						"the terms of the GNU General Public Licence\n".
						"(see http://www.fsf.org/licensing/licenses/gpl.txt).\n";
use constant EXAMPLE => "\n\n".
						"Example:\n".
						"\n".
						"check_cisco_sensor -H 192.168.0.43\n".
						"\n".
						"Test Mode that checks the compatibility of the plugin on a host with address 192.168.0.43\n".
						"using SNMP protocol version 1 and 'public' as community\n".
						"Plugin returns OK if it is a CISCO_SENSOR_MIB compliant device and can recover sensors data. Also, a list of all sensors\n".
						"with id, status, value, description, type, scale and precision is returned. If it's not compatible it returns UNKNOWN\n".
						"\n".
						"check_cisco_sensor -H 192.168.0.43 -e 234 -l \"Air in temperature\" -w 60 -c 75".
						"\n".
						"It checks the sensor value on a CISCO_SENSOR_MIB compliant device with ip address 192.168.0.43.\n" .
						"The plugin returns CRITICAL if the value of the sensor with id 234 is equal or greater than 60, \n".
						"WARNING if the value is equal or greater than 75 and OK in any other case. For output and perfdata\n".
						"purposes ,the label name of the sensor\n is 'Air in temperature', in case of not to define it, the plugin\n".
						"would try to recover the description associated to the -e id in the ENTITY_MIB mib.\n".
						"\n".
						"Ranges in warning and critical thresolds are defined as [@]start:end\n".
						"Notes:\n".
						"\n".
						"1. start <= end\n".
						"2. start and ':' is not required if start=0\n".
						"3. if range is of format 'start:' and end is not specified, assume end is infinity\n".
						"4. to specify negative infinity, use '~'\n".
						"5. alert is raised if metric is outside start and end range (inclusive of endpoints)\n".
						"6. if range starts with '\@', then alert if inside this range (inclusive of endpoints)\n".
						"\n".
						"Example ranges:\n".
						"\n".
						"\n".
						"10 \t\t\t Generate alert if x < 0 or > 10, (outside the range of {0 .. 10}) \n".
						"10: \t\t\t Generate alert if x < 10, (outside {10 .. 8}) \n".
						"~:10 \t\t\t Generate alert if x > 10, (outside the range of {-8 .. 10}) \n".
						"10:20 \t\t\t Generate alert if x < 10 or > 20, (outside the range of {10 .. 20}) \n".
						"\@10:20 \t\t\t Generate alert if x = 10 and = 20, (inside the range of {10 .. 20}) \n".
						"\n".
						"Note: Symbol '~' in bash is equivalent to the global variable  \$HOME. Make sure to escape\n".
						"this symbol with '\\' when type it in the command line. \n";
								
# VARIABLE DEFINITION

my $Nagios;
my $Error;
my $PluginMode;
my $PluginReturnValue, my $PluginOutput="";


# MAIN FUNCTION

# Get command line arguments
$Nagios = &CreateNagiosManager(USAGE, VERSION, BLURB, LICENSE, NAME, EXAMPLE);
eval {$Nagios->getopts};

if (!$@) {
	# Command line parsed
	if (&CheckArguments($Nagios, $Error, $PluginMode)) {
		# Argument checking passed

		if ($PluginMode == MODE_TEST) {
			$PluginReturnValue = &TestHost($Nagios, $PluginOutput);
			$PluginOutput = "TEST MODE\n\n" . $PluginOutput;
		}
		else {
			$PluginReturnValue = &PerformCheck($Nagios, $PluginOutput)
		}
		
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
	$Nagios->add_arg(spec => 'snmpver|E=s',
				help => 'SNMP protocol version (default: 2)',
				default => '2',
				required => 0);				
	# Add argument port
	$Nagios->add_arg(spec => 'port|P=i',
				help => 'SNMP agent port (default: 161)',
				default => 161,
				required => 0);
	
	# Add argument id
	$Nagios->add_arg(spec => 'label|l=s',
				help => "Sensor label name",
				required => 0);
	
	# Add argument id
	$Nagios->add_arg(spec => 'id|e=i',
				help => "Sensor id",
				required => 0);
	# Add argument warning
	$Nagios->add_arg(spec => 'warning|w=s',
				help => "Warning value threshold",
				required => 0);
	# Add argument critical
	$Nagios->add_arg(spec => 'critical|c=s',
				help => "Critical value threshold",
				required => 0);				
	
	# Return value
	return $Nagios;
}


# Checks argument values and sets some default values
# Input: Nagios Plugin object
# Output: Error description string
# Return value: True if arguments ok, false if not

sub CheckArguments() {
	my $Nagios = $_[0];

	if ( $Nagios->opts->port <= 0 ) {
		$_[1] = "Invalid SNMP agent port: must be greater than zero";
		return 0;
	}
	
	if ( (!defined $Nagios->opts->id) && (!defined $Nagios->opts->warning) && (!defined $Nagios->opts->critical) ) {
		$_[2] = MODE_TEST;
		return 1;
	}
	elsif ( (defined $Nagios->opts->warning) && (defined $Nagios->opts->critical) ){	
		#Check Warning Thresold
		if ( $Nagios->opts->warning !~ /^(@?(\d+|(\d+|~):(\d*)))?$/ ) {
			$_[1] = "Invalid warning value";
			return 0;
		}
		#Check Critical Thresold
		if ( $Nagios->opts->critical !~ /^(@?(\d+|(\d+|~):(\d*)))?$/ ) {
			$_[1] = "Invalid critical value";
			return 0;
		}
		$_[2] = MODE_CHECK;
	}
	else {
		$_[1] = "Invalid arguments.It must be defined critical and warning argument for check mode or neither of both for test mode.";
		return 0;
	}
	return 1;
}


# Checks if host supports sensors data of CISCO_SENSOR_MIB.
# If OK, it returns info about sensors 
# Input: Nagios Plugin object
# Output: Test output string
# Return value: OK if test passed, UNKNOWN if not.

sub TestHost(){
	my $SNMPError;
	my $SNMPSession;
	my $Output;
	my $PluginReturnValue = UNKNOWN;
	
	my $entSensorStatus = OID_ENTSENSORVALUEENTRY . '.5';
	my $entSensorType = OID_ENTSENSORVALUEENTRY . '.1';
	my $entSensorValue = OID_ENTSENSORVALUEENTRY . '.4';
	my $entSensorPrecision = OID_ENTSENSORVALUEENTRY . '.3';
	my $entSensorScale = OID_ENTSENSORVALUEENTRY . '.2';
	
	($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $Nagios->opts->hostname, 
													-community => $Nagios->opts->community, 
													-version => $Nagios->opts->snmpver, 
													-port => $Nagios->opts->port, 
													-timeout => $Nagios->opts->timeout);
	
	if (defined($SNMPSession)) {
		my $RequestResultIndex = $SNMPSession->get_entries(-columns => [$entSensorPrecision]);
		my $RequestResult = $SNMPSession->get_entries(-columns => [OID_ENTSENSORVALUEENTRY]);
		my $RequestResultDesc = $SNMPSession->get_entries(-columns => [OID_ENTPHYSICALDESC]);
		
		if ( defined($RequestResultIndex) && defined($RequestResult) && defined($RequestResultDesc) ) {
			my $id;
			my $Oid;
			my $status;
			my $value;
			my $type;
			my $precision;
			my $scale;
			my $desc="";
			$Output = "CISCO SENSORS DATA\n";
			foreach  $Oid (keys %{$RequestResultIndex}) {
				$id = (split(/\./, $Oid))[-1];
				if (defined $RequestResultDesc->{OID_ENTPHYSICALDESC.".$id"}) {
					 #Only recover id�s with description associated
					$desc = $RequestResultDesc->{OID_ENTPHYSICALDESC.".$id"};
					$status = SENSOR_STATUS->[$RequestResult->{$entSensorStatus.".$id"}];
					$value = $RequestResult->{$entSensorValue.".$id"};
					$type = SENSOR_TYPES->[$RequestResult->{$entSensorType.".$id"}];
					$precision = $RequestResult->{$Oid};
					$scale = SENSOR_SCALES->[$RequestResult->{$entSensorScale.".$id"}];						
					
					$Output. = "Sensor id: $id\t"  .
								"Description: $desc\t" .
								"Type: $type \t" .
								"Status: $status\t" .
								"Value: $value\t" .
								"Scale: $scale\t" .
								"Precision: $precision\n";
				}
			}
			$PluginReturnValue = OK;
		}
		$SNMPSession->close();
	}
	
	$_[1] = $Output;
	return $PluginReturnValue;
}


# Performs whole check: 
# Input: Nagios Plugin object
# Output: Plugin output string
# Return value: Plugin return value

sub PerformCheck() {
 	my $entSensorStatus = OID_ENTSENSORVALUEENTRY . '.5';
	my $entSensorType = OID_ENTSENSORVALUEENTRY . '.1';
	my $entSensorValue = OID_ENTSENSORVALUEENTRY . '.4';
	my $entSensorPrecision = OID_ENTSENSORVALUEENTRY . '.3';
	my $entSensorScale = OID_ENTSENSORVALUEENTRY . '.2';
	
	my $SNMPSession;
 	my $SNMPError;
	my $i;
	my $j;

 	my $CriticalOutput="";
	my $WarningOutput="";

 	my $PluginOutput;
 	my $PluginReturnValue = UNKNOWN;
	
	my $RequestResult ;
	
	my $SensorStatusId;
	my $SensorLabelname;
	my $SensorType;
	my $SensorRealValue;
	my $SensorNormalizedValue;
	my $SensorScale;
	my $SensorPrecision;
	my $Scale;
	my @SensorErrorMessages;
	my @SensorTypeAbbreviation;
	my @SensorScaleAbbreviation;
	
	# Start new SNMP session
 	($SNMPSession, $SNMPError) = Net::SNMP->session(-hostname => $Nagios->opts->hostname, 
 	                                                -community => $Nagios->opts->community, 
 	                                                -version => $Nagios->opts->snmpver, 
 	                                                -port => $Nagios->opts->port
 	                                                -timeout => $Nagios->opts->timeout););
	
	if ( !defined($SNMPSession) ) {
		$PluginOutput = "Error '$SNMPError' starting session";
	}
 	else {
		my $SensorId = $Nagios->opts->id;
		
		# Get sensor data
		$RequestResult = $SNMPSession->get_request(-varbindlist => [ "$entSensorStatus.$SensorId",
																	 "$entSensorValue.$SensorId",
																	 "$entSensorType.$SensorId",
																	 "$entSensorPrecision.$SensorId",
																	 "$entSensorScale.$SensorId",
																	 OID_ENTPHYSICALDESC . ".$SensorId" ]);
		$SNMPSession->close();
		
		# Checks if sensor status is ok
		if ( defined($RequestResult) ) {
			if ( $SensorStatusId =~ /^\d+$/ ) {
				if ( $SensorStatusId == SENSOR_STATUS_OK ) {
					# Sensor status is OK: It can be checked
					# Set sensor label
					if ( defined($Nagios->opts->label) ){
						$SensorLabelname = $Nagios->opts->label;	
					}
					else {
						$RequestResult = $SNMPSession->get_request(-varbindlist => [ OID_ENTPHYSICALDESC . ".$SensorId" ]);
						if (!defined($RequestResult)) {	
							$SNMPSession->close();
							$_[1] = "Error recovering sensor name with id $SensorId";
							return UNKNOWN;
						}
						$SensorLabelname=$$RequestResult{OID_ENTPHYSICALDESC.".$SensorId"};
						
						if ($SensorLabelname =~ m/noSuch/){
							$SNMPSession->close();
							$_[1] = "No Such Instance ($SensorId) currently exists at this OID";
							return UNKNOWN;
						}
					}					
					
		if (!defined($RequestResult)) {	
			$SNMPSession->close();
			$_[1] = "Not exists sensor with id =$SensorId";
			return UNKNOWN;
		}
		$SensorStatusId=$$RequestResult{$entSensorStatus.".$SensorId"};
		
		if ($SensorStatusId !~ /^\d+$/){
			$SNMPSession->close();
			$_[1] = "No Such Instance ($SensorId) currently exists at this OID";
			return UNKNOWN;
		}
		
		if ($SensorStatusId ne 1) {
			$SNMPSession->close();
			$_[1] = "Sensor with id $SensorId is not ok. It is $SensorErrorMessages[$SensorStatusId]";
			return UNKNOWN;				
		}
		else {
			# Set sensor label
			if (defined($Nagios->opts->label)){
				$SensorLabelname=$Nagios->opts->label;	
			}
			else{
				$RequestResult=$SNMPSession->get_request(-varbindlist => [ OID_ENTPHYSICALDESC.".$SensorId"]);
				if (!defined($RequestResult)) {	
					$SNMPSession->close();
					$_[1] = "Error recovering sensor name with id $SensorId";
					return UNKNOWN;
				}
				$SensorLabelname=$$RequestResult{OID_ENTPHYSICALDESC.".$SensorId"};
				
				if ($SensorLabelname =~ m/noSuch/){
					$SNMPSession->close();
					$_[1] = "No Such Instance ($SensorId) currently exists at this OID";
					return UNKNOWN;
				}
			}
			
			#Recovers  sensor value, type, precision and scale value
			$RequestResult=$SNMPSession->get_request(-varbindlist => [ $entSensorValue.".$SensorId"]);
			if ((!defined($RequestResult) )|| ($$RequestResult{$entSensorValue.".$SensorId"} =~ m/noSuch/)){
				$SNMPSession->close();
				$_[1] = "Error recovering sensor value with id $SensorId";
				return UNKNOWN;
			}
			$SensorRealValue = $$RequestResult{$entSensorValue.".$SensorId"};
			
			#type
			$RequestResult=$SNMPSession->get_request(-varbindlist => [ $entSensorType.".$SensorId"]);
			if ((!defined($RequestResult) )|| ($$RequestResult{$entSensorType.".$SensorId"} =~ m/noSuch/)){
				$SNMPSession->close();
				$_[1] = "Error recovering sensor data type with id $SensorId";
				return UNKNOWN;
			}
			$SensorType= $$RequestResult{$entSensorType.".$SensorId"};
			
			#precision
			$RequestResult=$SNMPSession->get_request(-varbindlist => [ $entSensorPrecision.".$SensorId"]);
			if ((!defined($RequestResult) )|| ($$RequestResult{$entSensorPrecision.".$SensorId"} =~ m/noSuch/)){
				$SNMPSession->close();
				$_[1] = "Error recovering sensor precision with id $SensorId";
				return UNKNOWN;
			}
			$SensorPrecision= $$RequestResult{$entSensorPrecision.".$SensorId"};
			
			#scale
			$RequestResult=$SNMPSession->get_request(-varbindlist => [ $entSensorScale.".$SensorId"]);
			if ((!defined($RequestResult) )|| ($$RequestResult{$entSensorScale.".$SensorId"} =~ m/noSuch/)){
				$SNMPSession->close();
				$_[1] = "Error recovering sensor scale with id $SensorId";
				return UNKNOWN;
			}
			$SensorScale= $$RequestResult{$entSensorScale.".$SensorId"};
			
			#Plugin Status and Plugin Output 
			$PluginReturnValue = $Nagios->check_threshold(check => $SensorRealValue, warning => $Nagios->opts->warning, critical => $Nagios->opts->critical);
			if ($PluginReturnValue ne OK){
				my $thresold;
				if ($PluginReturnValue eq CRITICAL){
					$thresold=$Nagios->opts->critical;
				}
				else{
					if ($PluginReturnValue eq WARNING){
						$thresold=$Nagios->opts->warning;
					}
				}
				my $message="";
				my $doubledot = $thresold =~ tr/://; 
				my $minMessage="";
				my $maxMessage="";
				my $valueMessage="";
				$valueMessage .= "$SensorRealValue".(($SensorScale eq 9) ? "" : "$SensorScaleAbbreviation[$SensorScale]");
				$valueMessage .= "$SensorTypeAbbreviation[$SensorType]";
				
				if ((substr $thresold, 0, 1) eq "\@"){
					my @limits = split(/:/, (substr $thresold, 1, length($thresold)) );

					if (!$doubledot){  							
						$minMessage=" >=0 or <= $limits[0]";
					}
					else{
						if ($limits[0] ne "~"){
							$minMessage=" <$limits[0]";
						}
						if(defined($limits[1])){
							$maxMessage=" >$limits[1]";
						}
					}
					if(length($minMessage) and length($maxMessage)){
						$message =  "Sensor \"$SensorLabelname\"  = $valueMessage (valid range is ";
						$message .= $minMessage." or".$maxMessage."). ";
					}
					else{
						$message =  "Sensor \"$SensorLabelname\"  = $valueMessage (valid range is $minMessage$maxMessage). ";
					}	    
				}
				else{
					my @limits = split(/:/, $thresold);							   
					if (!$doubledot){  							
						$minMessage=" >=0 and <= $limits[0]";
					}
					else{
						if ($limits[0] ne "~"){
							$minMessage=" >=$limits[0]";
						}
						if(defined($limits[1])){
							$maxMessage=" <=$limits[1]";
						}
					}
					if(length($minMessage) and length($maxMessage)){
						$message =  "Sensor \"$SensorLabelname\"  = $valueMessage (valid range is ";
						$message .=  $minMessage." and".$maxMessage."). ";
					}
					else{
						$message = "Sensor \"$SensorLabelname\"  = $valueMessage (valid range is $minMessage$maxMessage). "; 
					}
    						     
				}				
				$PluginOutput = $message;
			}				
		}
		
		
		#Perfdata and ok output
		if ($SensorScale == 15){
			$Scale = 10**15;
		}
		else{
			if ($SensorScale == 14){
				$Scale = 10**18;
			}
			else{
				$Scale = 10**(($SensorScale-9)*3);
			}
		}
		$SensorNormalizedValue=$SensorRealValue*$Scale/10**$SensorPrecision;
		if ($PluginReturnValue eq OK){
			$PluginOutput = "Sensor \"$SensorLabelname\" value ($SensorNormalizedValue"."$SensorTypeAbbreviation[$SensorType]) is in range. ";
		}
		
		my $perfdata = "'$SensorLabelname'=$SensorNormalizedValue"."$SensorTypeAbbreviation[$SensorType];;;;";
		$PluginOutput .= "| $perfdata";

		# Close SNMP session
		$SNMPSession->close();
	}
	
 	#Return result
 	$_[1] = $PluginOutput;
 	return $PluginReturnValue;
 }
