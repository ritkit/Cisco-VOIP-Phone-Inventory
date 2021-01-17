#!/usr/bin/perl

##Name: Phone Inventory Scrapper
##Purpose: Take a list of IPs and scrape the following information
##Hostname
##Phone Directory Number
##Model Number
##MAC Address
##Serial Number
##
##Output: A CSV with the collected information above and the originally supplies hostname/IP

## Coded by: Christian Rahl
## Last Update: 26th Aug, 2020

use strict;
use warnings;
use Text::CSV_XS qw( csv );
use Getopt::Long qw(GetOptions);
Getopt::Long::Configure qw(gnu_getopt);
use WWW::Mechanize;
use WWW::Mechanize::Plugin::FollowMetaRedirect;
use Web::Scraper;
use Encode;

# Array to store each phones information, add the CSV column labels
my $phoneInventory; 
@$phoneInventory = (["Provided HN", "Provided IP", "Provided Model", "Hostname", "Directory Number", "Model", "MAC", "Serial"]);

## GetOptions and their values
## -f Collect a file name for input <Input CSV>
## -h Collect the Hostname <hostname> IP is required also if used
## -i Collect an IP for input <IP>
## -o Output to a file <Filename>
## -s Output to standard input
## -t Timeout to wait for web page to load, defaul 5 seconds
## -d Debug mode
my $phoneName;
my $phoneIP;
my $phoneFile;
my $inventoryFile;
my $stdout;
my $debug=0;
my $timeout=5;

GetOptions(
	'file|f=s' => \$phoneFile,
	'hostname|h=s' => \$phoneName,
	'ip|i=s' => \$phoneIP,
	'output|o=s' => \$inventoryFile,
	'stdout|s' => \$stdout,
	'timeout|t=i' => \$timeout,
	'debug|d' => sub{$debug=1}
) or die "Usage: $0 <--file|-f Filename> <--hostname -h Phone Name && --ip|-i Phone IP> <--output|-o filename> <--stdout|-s> <--timeout|-t Seconds> <--debug\-d>\n";

## Create the Method to download the HTML file and follow redirects
## Autocheck disabled so that I can continue through the other phones
## Quiet mode again, do not warn me, will skip the phone if 
my $browser = WWW::Mechanize->new(
	agent => 'SouthPole-PerlUA/1.0',
	#Turns on autocheck if debug is set
	autocheck => $debug,
	#Turns off quiet mode if debug is set
	quiet => $debug^1,
	timeout => $timeout
);

## Build a search for the table for each of the phone info
## This is to help handle the information being in seperate locations
my $phonescraper = scraper { 
	## Search for the hostname
	process '//tr/td[preceding-sibling::td//b/text()[contains(translate(.,\'ABCDEFGHIJKLMNOPQRSTUVWXYZ\',\'abcdefghijklmnopqrstuvwxyz\'),"host name")]]//b', Hostname => 'TEXT';
	
	## Search for the primary directory number
	process '//tr/td[preceding-sibling::td//b/text()[contains(translate(.,\'ABCDEFGHIJKLMNOPQRSTUVWXYZ\',\'abcdefghijklmnopqrstuvwxyz\'),"phone dn")]]//b', DN => 'TEXT';
	
	## Search for the Model Number
	process '//tr/td[preceding-sibling::td//b/text()[contains(translate(.,\'ABCDEFGHIJKLMNOPQRSTUVWXYZ\',\'abcdefghijklmnopqrstuvwxyz\'),"model number")]]//b', Model => 'TEXT';
	
	## Search for the MAC Address
	process '//tr/td[preceding-sibling::td//b/text()[contains(translate(.,\'ABCDEFGHIJKLMNOPQRSTUVWXYZ\',\'abcdefghijklmnopqrstuvwxyz\'),"mac address")]]//b', MAC => 'TEXT';
	
	## Search for the serial number
	process '//tr/td[preceding-sibling::td//b/text()[contains(translate(.,\'ABCDEFGHIJKLMNOPQRSTUVWXYZ\',\'abcdefghijklmnopqrstuvwxyz\'),"serial number")]]//b', Serial => 'TEXT';
};

## Take in phone information 1 of 2 ways
## First way is via a CSV file that contains Hostname(SEP....), and IP
## Second is via flags including Hostname and IP
my $phoneList;
if ($phoneFile) {
	$phoneList = csv (in => $phoneFile) or die "Unable to parse CSV file at '$phoneFile' [$!]\n";
}
elsif ($phoneName && $phoneIP) {
	@$phoneList = ( ["$phoneName","$phoneIP"] );
}
else {
	die "Usage: $0 <--file|-f Filename> <--hostname -h Phone Name && --ip|-i Phone IP> <--output|-o filename> <--stdout|-s> <--debug\-d>\n";
}

my $phonelistlength = scalar @$phoneList;
my $i = 1;

## Loop through each phone connecting and collecting the information above
foreach my $phone (@$phoneList){

	## Display how many phones that need to be collected and what are left
	print "Collecting phone $i of $phonelistlength.\n";
	
	#Collect the phone IP to check on and add HTTP:// to the front
	$browser->get('http://'.@$phone[1]);
	
	if( $browser->success() ){
		#Some of the phones use the <Meta> tag in HTML to redirect instead of 302.
		#This next line tells mech to follow that meta redirect
		$browser->follow_meta_redirect( ignore_wait => 1 ); 
		
		#Check to make sure the phone was reachable
		if($browser->response()->is_success){
			#Grab the HTML
			my $phoneHTML = $browser->response()->decoded_content(charset => 'utf-8');
			
			#Print HTML for troubleshooting
			if ($debug){
				print "$phoneHTML \n";
			}
			
			## Read in phone info from the website, and pass it to the scraper
			## Outputs a scraper object with the PhoneInfo
			my $phoneInfo = $phonescraper->scrape($phoneHTML) or die "Unable to read from phone\n";
			
			## Take the phone info and append it onto the CSV Inventory Array
			## The first 2 items are added for confirmation that the correct info was collected
			push (@$phoneInventory, ["@$phone[0]","@$phone[1]","@$phone[2]","$phoneInfo->{Hostname}", 
				"$phoneInfo->{DN}", "$phoneInfo->{Model}", "$phoneInfo->{MAC}", "$phoneInfo->{Serial}"]);
		}	
	}
	#If the phone was not reachable indicate in the file
	else{
		push (@$phoneInventory, ["@$phone[0]","@$phone[1]","@$phone[2]","Unable to reach phone", "", "", "", ""]);
	}
	
	$i++;
}

## Take the compiled inventory list
## and create a CSV if an output file is created
if ($inventoryFile){
	csv (in => $phoneInventory, out => "$inventoryFile", sep_char => ",");
}

## Or output to StdOut if indicated
elsif ($stdout){
	foreach my $item (@$phoneInventory){
		foreach my $print (@$item){
			print $print,"\t";
		}
		print "\n";
	}
}