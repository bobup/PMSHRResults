#!/usr/bin/perl -w

# HRResults.pl - Manage Human Readable Open Water Results
# Beginning in 2024 part of the processing of OW points was the creation of "human readable" 
# results suitable for posting on the pacific masters Open+Water+Event+Results page. 
# This removed the burden 
# that we once placed on the hosts of producing TWO kinds of results for us. Now, they just 
# give us the OW points results and we do the rest. (Added benefits: Corrections to the OW points
# results automatically translated to corrections to the human readable results (in the past
# this rarely happened, thus the human readable results rarely matched the points); we controlled
# the look of the pages and can make them all look the same.)
# This program will update the PRODUCTION database so that the human readable results produced by
# the OW Points code are
# pointed to by our web site's Open+Water+Event+Results page.
# The steps performed by this program:
#	1)	Get a list of all human readable results that we've already generated and pushed to production
#		for the year we care about ($owYear - set below.) That list is logged.
#	2)	Confirm that all hr result files that we SHOULD HAVE generated are in the above list. If not that's
#		weird and we'll report it.
#	3)	For each hr file that we've generated and pushed to the OW Points HR page we need to make sure that
#		it is linked to by the PMS Open+Water+Event+Results web page.  If it's not then we make that happen.
#
# Note; we only install the Age Group HR results since each of those has a link to the Overall HR results for 
#	the same event.
#
# Copyright (c) 2024 Bob Upshaw.  This software is covered under the Open Source MIT License 

####################
# PERL modules and initialization to help compiling
####################
use File::Basename;
use POSIX qw(strftime);
use Cwd 'abs_path';
my $appProgName;	# name of the program we're running
my $appDirName;     # directory containing the application we're running
my $appRootDir;		# directory containing the appDirName directory
my $sourceData;		# full path of directory containing the "source data" which we process to create the generated files
my $dateTimeFormat;
my $currentDateTime;	# the date/time we start this application
my $yearFormat;
my ($dateFormat, $currentDate);		# just the year-mm-dd
my $owYear;			# the OW year we're going to process
# $yearBeingProcessed is important:  it is the DEFAULT $owYear.
#	It's the year this app is running. It is computed below.
my $yearBeingProcessed;
# The program we're running is (by default) in a directory parallel to the directory that will contain
# the generated logs, but this can be changed by specifying a value for the GeneratedFiles in the arguments
# passed to this program. 
my $generatedFiles;

BEGIN {
	# get the date/time we're starting:
	$dateTimeFormat = '%a %b %d %Y %Z %I:%M:%S %p';
	$currentDateTime = strftime $dateTimeFormat, localtime();
	$dateFormat = '%Y-%m-%d';		# year-mm-dd
	$currentDate = strftime $dateFormat, localtime();
	$yearFormat = '%Y';
	$yearBeingProcessed = strftime $yearFormat, localtime();	# the year we're doing the processing
	$owYear = $yearBeingProcessed;		# default (the year we're processing is the same as the year we're doing the processing)
	
	# Get the name of the program we're running:
	$appProgName = basename( $0 );
	die( "Can't determine the name of the program being run - did you use/require 'File::Basename' and its prerequisites?")
		if( (!defined $appProgName) || ($appProgName eq "") );
	

	# The directory containing this program is called the "appDirName".
	# The appDirName is important because it's what we use to find everything else we need.  In particular, we
	# need to find and process the 'properties.txt' file (also contained in the appDirName), and from that
	# file we determine various operating parameters, which can override defaults set below, and also
	# set required values that are NOT set below.
	#
	
	$appDirName = dirname( $0 );     # directory containing the application we're running, e.g.
										# e.g. /Users/bobup/Development/PacificMasters/PMSHRResults/Code/
										# or ./Code/
	die( "${appProgName}:: Can't determine our running directory - did you use 'File::Basename' and its prerequisites?")
		if( (!defined $appDirName) || ($appDirName eq "") );
	# convert our application directory into a full path:
	$appDirName = abs_path( $appDirName );		# now we're sure it begins with a '/'

	# The 'appRootDir' is the parent directory of the appDirName:
	$appRootDir = dirname($appDirName);		# e.g. /Users/bobup/Development/PacificMasters/PMSOWPoints/
	die( "${appProgName}:: The parent directory of '$appDirName' is not a directory! (A permission problem?)" )
		if( !-d $appRootDir );
	
	# DEFAULT:  Generated files based on passed 'appRootDir':
	$generatedFiles = "$appRootDir/GeneratedFiles";	# directory location where we'll put all files we generate 

	# initialize our source data directory name:
	$sourceData = "$appRootDir/SourceData";	
}


####################
# Usage string
####################

my $UsageString = <<bup
Usage:  
	$appProgName [year]
	[-dDebugValue]
	[-tPROPERTYFILE]
	[-sSOURCEDATADIR]
	[-gGENERATEDFILESDIR]
	[-h]
where all arguments are optional:
	year
		where year is the year to process
	-dDebugValue - a value 0 or greater.  The larger the value, the more debug stuff printed to the log
	-tPROPERTYFILE - the FULL PATH NAME of the property.txt file.  The default is appDirName/properties.txt, where
		'appDirName' is the directory holding this script, and
		'properties.txt' is the name of the properties files for this script.
	-sSOURCEDATADIR is the full path name of the SourceData directory
	-gGENERATEDFILES is the full path name of the GeneratedFiles directory
	-h - display help text then quit

Handle human readable OW results that are produced by the OW points program but still need to
be linked to by the Open+Water+Event+Results page on our web site.
bup
;

####################
# pragmas
####################
use DBI;
use strict;
use sigtrap;
use warnings;


####################
# included modules
####################

use lib "$appDirName/../../PMSPerlModules";
require PMS_MySqlSupport;
require PMSLogging;
use Data::Dumper;
require PMSStruct;
require PMSMacros;
require PMSConstants;

####################
# hard-coded program options.  Change them if you want the program to behave differently
####################
							


####################
# internal subroutines
####################
sub GetOWCalendar( $$$ );

####################
# global flags and variables
####################

PMSStruct::GetMacrosRef()->{"currentDateTime"} = $currentDateTime;
PMSStruct::GetMacrosRef()->{"currentDate"} = $currentDate;

# define the generation date, which we rarely have a reason to change from "now", but this and the
# currentDate can be overridden in the property file below:
PMSStruct::GetMacrosRef()->{"generateDate"} = PMSStruct::GetMacrosRef()->{"currentDateTime"};

# the $groupDoingTheProcessing is the orginazation whose results are being processed.
# Set the default here:
my $groupDoingTheProcessing = "PacMasters"; 

# more defaults...
# We also use the AppDirName in the properties file (it can't change)
PMSStruct::GetMacrosRef()->{"AppDirName"} = $appDirName;	# directory containing the application we're running
# location of property file for this program:
my $propertiesDir = $appDirName;	# Directory holding the properties.txt file.
my $propertiesFileName = "properties.txt";



# location of property file for the OWPoints program for the year we're processing:
my $owPropertiesDir = $appDirName . "/../../PMSOWPoints/SourceData/";
my $owPropertiesSimpleName = "$owYear-properties.txt";

############################################################################################################
# get to work - initialize the program
############################################################################################################
# get the arguments:
my $arg;
my $numErrors = 0;
my $helpRequested = 0;
while( defined( $arg = shift ) ) {
	my $flag = $arg;
	my $value = PMSUtil::trim($arg);
	if( $value =~ m/^-/ ) {
		# we have a flag in the form '-x...'
		$flag =~ s/(-.).*$/$1/;
		$value =~ s/^-.//;
		if( $flag !~ m/^-.$/ ) {
			print "${appProgName}:: FATAL ERROR:  Invalid flag: '$arg'\n";
			$numErrors++;
		}
		SWITCH: {
	        if( $flag =~ m/^-d$/ ) {$PMSConstants::debug=$value; last SWITCH; }
	        if( $flag =~ m/^-t$/ ) {
	        	$value = $arg;			# maintain the case of chars
				$value =~ s/^-.//;		# get rid of flag ('-t')
				$propertiesDir = dirname($value);
				$propertiesFileName = basename($value);
				last SWITCH;
	        }
	        if( $flag =~ m/^-s$/ ) {
	        	$value = $arg;			# maintain the case of chars
				$value =~ s/^-.//;		# get rid of flag ('-s')
				$sourceData = $value;
				last SWITCH;
	        }
	        if( $flag =~ m/^-g$/ ) {
	        	$value = $arg;			# maintain the case of chars
				$value =~ s/^-.//;		# get rid of flag ('-g')
				$generatedFiles = $value;
				last SWITCH;
	        }
			if( $flag =~ m/^-h$/ ) {
				print $UsageString;
				$helpRequested = 1;
				last SWITCH; 
			}
			print "${appProgName}:: FATAL ERROR:  Invalid flag: '$arg'\n";
			$numErrors++;
		}
	} else {
		# we don't have a flag - must be the year to process
		if( $value ne "" ) {
			$value =~ m/^(\d\d\d\d)$/;
			my $year = $1;
			if( !defined $year ) {
				$owYear = $year;
			}
			if( 
				($owYear < 2008) ||
				($owYear > $yearBeingProcessed)
				) {
				print "${appProgName}:: FATAL ERROR:  Invalid value for the year to process ($owYear)\n";
				$numErrors++;
			}
		}
	}
} # end of while - done getting command line args


if( $helpRequested ) {
	exit(1);       # non-zero because we didn't do anything useful!
}
# if we got any errors we're going to give up:
if( $numErrors > 0 ) {
	print "${appProgName}:: ABORT!:  $numErrors errors found - giving up!\n";
	exit;
}

# make sure our directory name ends with a '/':
if( $generatedFiles !~ m,/$, ) {
	$generatedFiles .= "/";
}
# Store the GeneratedFiles directory as a macro:
PMSStruct::GetMacrosRef()->{"GeneratedFiles"} = $generatedFiles;

# initialize our logging
my $simpleLogFileName = "HRResultsLog.txt";				# file name of the log file
my $generatedLogFileName = $generatedFiles . $simpleLogFileName;		# full path name of the log file we'll generate
# open the log file so we can log errors and debugging info:
if( my $tmp = PMSLogging::InitLogging( $generatedLogFileName )) { die $tmp; }

PMSLogging::PrintLog( "", "", "$appProgName started on $currentDateTime...", 1 );
PMSLogging::PrintLog( "", "", "  ...with the app root of '$appRootDir'...", 1 );
PMSLogging::PrintLog( "", "", "  ...and reading properties from '$propertiesDir/$propertiesFileName'", 1 );

# keep the value of $sourceData as a macro for convenience, and also because we use it in the properties.txt file
# (We might also change it in the properties file)
PMSStruct::GetMacrosRef()->{"SourceData"} = $sourceData;
PMSStruct::GetMacrosRef()->{"YearBeingProcessed"} = $yearBeingProcessed;
PMSStruct::GetMacrosRef()->{"owYear"} = $owYear;


# Read the properties.txt file for this program and set the necessary properties by setting name/values in 
# the %macros hash which is accessed by the reference returned by PMSStruct::GetMacrosRef().  For example,
# if the macro "numSwimsToConsider" is set in the properties file, then it's value is retrieved by 
#	my $numSwimsWeWillConsider = PMSStruct::GetMacrosRef()->{"numSwimsToConsider"};
# after the following call to GetProperties();
# Note that the full path name of the properties file is set above, either to its default value when
# $propertiesDir and $propertiesFileName are initialized above, or to a non-default value by an
# argument to this script.
PMSMacros::GetProperties( $propertiesDir, $propertiesFileName, $yearBeingProcessed );
# just in case the SourceData changed get the new value:
$sourceData = PMSStruct::GetMacrosRef()->{"SourceData"};

PMSLogging::PrintLog( "", "", "  ...and the SourceData directory of '$sourceData'...", 1 );

# initialize our DB access
PMS_MySqlSupport::SetSqlParameters( 'default',
	PMSStruct::GetMacrosRef()->{"dbHost"},
	PMSStruct::GetMacrosRef()->{"dbName"},
	PMSStruct::GetMacrosRef()->{"dbUser"},
	PMSStruct::GetMacrosRef()->{"dbPass"} );

# some initial values could have changed in the above property file, so we're going to
# re-initialize those values:
$owYear = PMSStruct::GetMacrosRef()->{"owYear"};

		
# at this point we INSIST that $yearBeingProcessed is a reasonable year:
if( ($yearBeingProcessed !~ m/^\d\d\d\d$/) ||
	( ($yearBeingProcessed < 2008) || ($yearBeingProcessed > 2030) ) ) {
	die( "${appProgName}::  The year being processed ('$yearBeingProcessed') is invalid - ABORT!");
}
PMSLogging::PrintLog( "", "", "  ...theYearBeingProcessed set to: '$yearBeingProcessed'", 1 );


# Get the list of PRODUCTION human readable files (linked to by OW points)
# - /usr/home/pacmasters/public_html/pacificmasters.org/sites/default/files/comp/points/OWPoints
#		The above path is the directory holding the current year's OW points pages and spreadsheets.
# -	/usr/home/pacmasters/public_html/pacificmasters.org/sites/default/files/comp/points/OWPoints/hrResults/2024
#		The above path is the directory holding the 2024 human readable results generated while computing OW points
#		for 2024.
# -	https://data.pacificmasters.org/points/OWPoints/hrResults/
#		The above path is the URL to the directory holding the subdirectories containing the human readable results
#		for all years for which they were generated while computing OW points.  (2024 and beyond...)
# - https://data.pacificmasters.org/points/OWPoints/hrResults/2024/Lake_Berryessa_1_Mile-cat1-AG.html
#		The above path is the URL to a specific human readable generated in 2024 while generating OW points.
# The $hrDirPath is the full path name to the directory holding the HR result files we've generated 
# and pushed to PRODUCTION:
my $hrDirPath = "/usr/home/pacmasters/public_html/pacificmasters.org/sites/default/files/comp/points/OWPoints/hrResults/$owYear";
# The $hrDirURL is the URL to the directory holding the HR result files we've generated 
# and pushed to PRODUCTION:
my $hrDirURL = "https://data.pacificmasters.org/points/OWPoints/hrResults/$owYear/";
# (1): The @files array will hold the names of all HR files for the $owYear that exist on the PRODUCTION machine.
my @files = ();
@files = qx{ ssh pacmasters\@pacmasters.pairserver.com "( ls $hrDirPath )" };
PMSLogging::PrintLog( "", "", "Here are the hr files for $owYear so far:\n @files", 0 );


# get the calendar properties for the ow season we're processing:
GetOWCalendar( $owPropertiesDir, $owPropertiesSimpleName, $owYear );

# At this point we have a hash that looks like this:
#	%calendar{n-detail} - where "n" is a unique number representing an OW race, and "detail" is
#		one of the following:
#		FileName - the partial path to the result that we process for this event
#		CAT - the suit category of this event
#		Date - the date that this event is swum
#		Distance - the distance of this event, in miles
#		EventName - the name of this event (e.g. "Lake Berryessa 1 Mile")
#		UniqueID - the unique id of this event to distinguish it from all other events 
#			tracked by our OW points system.
#		Keywords - a list of keywords to help us confirm that a file name matches the event.
#		Link - a URL pointed to a description of this OW event.
#	In addition, there are details that may be generated by OW Points for an event and
#		stored in this hash:
#		HRLink - a link to the human readable results generated while processing points.
#	In addition, the following hash entries exist for each event:
#		%calendar{n} = FileName
#		%calendar{FileName} = n
#	where 'n' is the race number.

# compute the full (simple) name of each HR file:
my $calendarRef = PMSMacros::GetCalendarRef();
foreach my $key (keys %{$calendarRef}) {
	if( $key =~ m/^\d+$/ ) {
		# we've got a calendar entry of the form $calendar{n} = filename
		my $fileName = $calendarRef->{$key};
		# if there are no results for this event yet then we have not yet generated any HR results, 
		# so in that case skip this event:
		next if( $fileName eq "NO RESULTS");
		
		my $cat = $calendarRef->{"$key-CAT"};
		my $eventName = $calendarRef->{"$key-EventName"};
		$eventName =~ s/\s/_/g;		# replace spaces with underscore in file names
		# (2) see if these hr result files exist:
		my $type = "AG";			# we only install the Age Group HR results - those link to overall results
		my $simpleFileName = "$eventName-cat$cat-$type.html";
		if( grep( /^$simpleFileName$/, @files ) ) {
			# yes - this HR result file has been generated
			PMSLogging::PrintLog( "", "", "The HR file name '$simpleFileName' exists in the OW Points HR directory.", 0 );
			# (3) in this case we're going to make sure it's part of the PMS web site Open+Water+Event+Results page 
			InstallHRResultIfNecessary( $simpleFileName, $calendarRef, $key, $hrDirURL, $owYear );
		} else {
			PMSLogging::DumpError( "", "", "The HR file name '$simpleFileName' DOES NOT EXIST in the OW Points HR directory.", 1 );
		}
	} # end of if( $key =~ digits only...
}

PMSLogging::PrintLog( "", "", "$appProgName Done.", 1 );

exit;

##############################################################################################################################
################################### Support Routines #########################################################################
##############################################################################################################################

#			InstallHRResultIfNecessary( $simpleFileName, $calendarRef, $key, $hrDirURL, $owYear );
# InstallHRResultIfNecessary - we confirmed that we have a human readable result file - does it need to
#	be installed on the PMS Open+Water+Event+Results web page?
#
# PASSED:
#	$simpleFileName - the file name of the file holding the HR result (located in the OW Points tree) on PRODUCTION.
#	$calendarRef - a reference to the calendar describing all OW events for the year being processed.  See the OW Points
#		properties and documentation, the PMSMacros.pm module, and also GetOWCalendar() below.
#	$key - the key designating a specific calendar entry defining the event for which the HR results describe.
#	$hrDirURL - the URL of the HR results described by the passed calendar entry and the passed $simpleFileName.
#	$owYear - the year we're processing.
#
# RETURNED:
#	n/a
#
# NOTES:
#	If the passed HR results don't need to be pushed to the PMS site then this routine has no effect. Otherwise,
#	the appropriate PRODUCTION database is updated with the specifics so that the Open+Water+Event+Results page
#	will be updated with a link to the passed HR results.
#
sub InstallHRResultIfNecessary( $$$$$ ) {
	my ($simpleFileName, $calendarRef, $key, $hrDirURL, $owYear) = @_;
	my $keyword = $calendarRef->{"$key-Keywords"};
	my $distance = $calendarRef->{"$key-Distance"};
	my $eventDate = $calendarRef->{"$key-Date"};
	my $category = $calendarRef->{"$key-CAT"};
	my $fullURL = "$hrDirURL$simpleFileName";		# this is the existing HR results file on PRODUCTION
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $resultHash;
	my $simpleFileNameNoExtension = $simpleFileName;
	$simpleFileNameNoExtension =~ s/\.html$//;
	# set the following $fileName to either $simpleFileName or $simpleFileNameNoExtension, depending on
	# strict you want to be. 
	my $fileName = $simpleFileNameNoExtension;

	# is this HR result file installed in our results_ow production database?
	my $query1 = "SELECT * FROM `results_ow` WHERE `results_file` LIKE '%$fileName%' " .
		"AND event_date LIKE '%$owYear-%'";
	my( $sth, $rv ) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query1 );
	my $count = 0;
	while( defined( $resultHash = $sth->fetchrow_hashref ) ) {
		my $eventId = $resultHash->{"event_id"};
		my $resultsFile = $resultHash->{"results_file"};
		$count++;		
	}
	if( $count == 1 ) {
		PMSLogging::PrintLog( "", "", "Found ONE instance of '$fileName' installed - NO INSTALLATION NECESSARY.", 0 );
	} elsif( $count > 1 ) {
		PMSLogging::DumpError( "", "", "Found $count instances of '$fileName' installed - TAKE A LOOK AT THIS!!", 1 );
	} else {
		PMSLogging::PrintLog( "", "", "Found ZERO instance of '$fileName' installed - INSTALLATION UNDERWAY...", 1 );
		# figure out what event_id to use when installing this HR result;
		my $query2 = "SELECT * FROM `event_titles` WHERE event_type='o' " .
  			"AND obsolete = 0 AND event_title like '%$keyword%'";
		my( $sth2, $rv2 ) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query2 );
		$count = 0;
		my $eventId;
		while( defined( $resultHash = $sth2->fetchrow_hashref ) ) {
			$eventId = $resultHash->{"event_id"};
			$count++;		
		}
		if( $count == 0 ) {
			PMSLogging::DumpError( "", "", "Didn't find any event_titles with the title like '$keyword' - INSTALLATION FAILED!!", 1 );
		} elsif( $count > 1 ) {
			PMSLogging::DumpError( "", "", "Too many event_titles like '$keyword' - INSTALLATION FAILED!!", 1 );
		} else {
			my $hrDistance = DistanceForHumans( $distance );
			#print "Found eventId = $eventId\n";
			# In order to install our HR results all we need to do is update the results_ow table with a
			# row representing the HR result:
			my $query3 = "INSERT INTO results_ow " .
				"(event_id, event_date, category, distance, results_type, results_file, remote) " .
				" VALUES " .
				"($eventId, '$eventDate', 'Cat $category', '$hrDistance', 'Age Group+Overall', '$fullURL', 1)";
			#print "Install HR results: `$query3`\n";
			my( $sth3, $rv3 ) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query3 );
		}
	}
} # end of InstallHRResultIfNecessary()


#			my $hrDistance = DistanceForHumans( $distance );
# DistanceForHumans - convert the passed $distance (in miles) to something a human would rather see.
#
# PASSED:
#	$distance - a number (integer or float) representing the distance of a race.  E.g. 2 or 3.107.  This
#		distance is in miles.
#
# RETURNED:
#	The same distance but more descriptive, possibly in units different than miles.  For example, if $distance
#	is '2' then "2 miles" is returned. If '6.214' is passed, then "10km" is returned.
#
sub DistanceForHumans( $ ) {
	my $distance = $_[0];
	my $result = -1;
	
	# is the passed distance an integer?  If so assume it's miles and set appropriately:
	if( int( $distance ) == $distance ) {
		# an integral number of miles:
		if( $distance == 1 ) {
			$result = "$distance Mile";
		} else {
			$result = "$distance Miles";
		}
	} else {
		# assume this distance is kilometers (a real hack) or one of a small set of non-integral miles.
		# There is only a small number of distances
		# we will see. If this distance isn't one we recognize we'll leave it as a float in Miles.)
		if( $distance == 3.107 ) {
			$result = "5km";
		} elsif( $distance == 6.214 ) {
			$result = "10km";
		} elsif( $distance == .932 ) {
			$result = "1.5km";
		} elsif( $distance == 1.553 ) {
			$result = "2.5km";
		} elsif( $distance == 2.7 ) {
			$result = "2.7 Miles";
		} elsif( $distance == .746 ) {
			$result = "1.2km";
		} elsif( $distance == .5 ) {
			$result = "1/2 Mile";
		} else {
			# worse case...
			$result = "$distance Miles";
		}
	}
	return $result;
} # end of DistanceForHumans()


# GetOWCalendar( $propertiesDir, $propertiesFileName, $owYear );
# GetOWCalendar - parse the passed OW property file for the passed year and store the calendar table internally.
#
# PASSED:
#	$propertiesDir - the directory (relative to this application) containing the properties for the OW Points application.
#		It is this property file that contains a description of every OW event for a specific year.
#	$simplePropFileName - the name of the OW Points property file.
#	$yearBeingProcessed - the year we're processing.
#
# RETURNED:
#	n/a
#
# NOTES:
#	The side-effect of this routine is to construct the 'calendar' hash used by this application. This is how
#	we know the OW events we have processed for points, thus the OW events for which we should have (or eventually
#	will have) HR results.
#
# 	see PMSMacros.pm for a definition of the 'calendar' hash.
#
sub GetOWCalendar( $$$ ) {
	my ($propertiesDir, $simplePropFileName, $yearBeingProcessed) = @_;
	my $propFileFD;
	my $propFileName = $propertiesDir . "/" . $simplePropFileName;
	my $lineNum = 0;
	my $processingCalendar = 0;		# set to 1 when processing a ">calendar....>endcalendar" block
	my $processingSkip = 0;			# set to 1 when processing a ">skip...>endskip" block
	open( $propFileFD, "< $propFileName" ) || die( "Can't open $propFileName: $!" );
	while( my $line = <$propFileFD> ) {
		my $value = "";
		$lineNum++;
		chomp( $line );
		$line =~ s/\s*#.*$//;		# remove optional spaces followed by comment
		$line =~ s/^\s+|\s+$//g;			# remove leading and trailing space

		# if we're processing a >skip block then all we want to find is an >endskip ignoring
		# everything else.
		if( $processingSkip ) {
			if( $line =~ m/^>endskip$/ ) {
				$processingSkip = 0;
			}
			next;
		}

		# handle a continuation line
		while( $line =~ m/\\$/ ) {
			$line =~ s/\s*\\$//;		# remove (optional) whitespace followed by continuation char
			# special case:  if the entire line is a single word add a space so we find the 'name', e.g. the lines
			# look like this:
			#    name \
			#		value...
			if( ! ($line =~ m/\s/) ) {
				$line .= " ";
			}
			my $nextLine;
			last if( ! ($nextLine = <$propFileFD>) );		# get the next line
			$lineNum++;
			chomp( $nextLine );
			$nextLine =~ s/\s*#.*$//;		# remove optional spaces followed by comment
			$nextLine =~ s/^\s+|\s+$//g;			# remove leading and trailing space
			$line .= $nextLine;
		}

		next if( $line eq "" );		# if we now have an empty line then get next line
		my $macroName = $line;
		$macroName =~ s/\s.*$//;	# remove all chars from first space char until eol
		if( ($macroName =~ m/^>/) || $processingCalendar ) {
			# found a non macro definition (synonym, etc of the form ">....")
			$macroName = lc( $macroName );
			if( $macroName eq ">skip" ) {
				$processingSkip = 1;
				next;
			} elsif( $macroName eq ">calendar" ) {
				$processingCalendar = 1;
				next;
			} elsif( $macroName eq ">endcalendar" ) {
				$processingCalendar = 0;
				next;
			} elsif( $processingCalendar ) {
				PMSMacros::ProcessCalendarPropertyLine($line, $yearBeingProcessed);
				next;
			} elsif( $macroName eq ">endoffile" ) {
				last;
			}
		}
		# if we got here we found a line to ignore...
	} # end of while( my $line = <$propFileFD....

} # end of GetOWCalendar()

# end of OWChallenge.pl
