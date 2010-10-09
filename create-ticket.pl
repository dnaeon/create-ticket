#!/usr/bin/perl -w

##########################################################################
# Filename      : create-ticket.pl                                       #
# Version       : 0.03                                                   #
# Description   : Logs a ticket in JIRA. The script is intended to be    #
#		  executed by Nagios each time a critical or warning	 #
#	 	  alerts are noticed.					 #
# Functions     : The following functions are defined in the file:       #
#                 CreateTicketInJira () - logs a ticket in JIRA          #
##########################################################################

use strict;
use XMLRPC::Lite;

# description for the keys from Nagios
my @keydesc = ( 'Notification Type',
		'Hostname',
		'Host Alias / Address',
		'Date / Time',
		'Output',
		'Service / Host State',
		'Service Description'
	      );

# stores the information sent by Nagios
my %NagiosData;

# fetch the ticket data from stdin
# the fields in the ticket data should be separated by a tab char
while (<STDIN>) {
  my @ticket_data = split('\t', $_);
	
  # temp vars
  my ($value, $i) = 0;

  # fill in the data in the %NagiosData hash
  foreach $value (@ticket_data) {
    $NagiosData{$keydesc[$i++]} = $value;
  }

  # log the ticket
  CreateTicketInJira (%NagiosData);
}

# CreateTicketInJira () - logs a ticket in JIRA
# this function uses XMLRPC to create a ticket in JIRA
sub CreateTicketInJira {  
  my %NagiosData = @_;

  # create the description of the ticket
  my $ticket_description;
  foreach (keys %NagiosData) {
    $ticket_description .= "$_: $NagiosData{$_}\n";
  }

  $ticket_description .= "\nClick on the following link for more information about the issue in Nagios:\n";
  $ticket_description .= 'http://nagios-host.org/nagios/cgi-bin/extinfo.cgi';

  (my $srv_link = $NagiosData{'Service Description'}) =~ s/ /+/g if exists $NagiosData{'Service Description'};
  $ticket_description .= (exists $NagiosData{'Service Description'}
		      ?  "?type=2&host=$NagiosData{'Hostname'}&service=$srv_link"
		      :  "?host=$NagiosData{'Hostname'}");

  # execute the XMLRPC call - the ticket will be logged by the "Jira Issue Reporter" user
  my $jira = XMLRPC::Lite->proxy ('http://jira-instance.org:8080/jira/rpc/xmlrpc');
  my $auth = $jira->call ("jira1.login", "user", "pass")->result ();
  my $call = $jira->call ("jira1.createIssue", $auth, {
    'project'               => 'CALL',
    'type'                  => 10,
    'reporter'              => 'user',
    'summary'               => (defined($NagiosData{'Service Description'}) ? "$NagiosData{'Service Description'} on $NagiosData{'Hostname'} - $NagiosData{'Service / Host State'} alert"  : "Host $NagiosData{'Hostname'} is $NagiosData{'Service / Host State'}"),
    'description'           => $ticket_description, 
    'customFieldValues'     => [
      {
        # Urgency
        'customfieldId'      => 'customfield_10031',
        'values'             => [SOAP::Data->type (string => 'Medium')]
      },
      {
        # Business impact
        'customfieldId'      => 'customfield_10022',
        'values'             => [SOAP::Data->type (string => 'Medium')]
      },
      {
        # Location
        'customfieldId'      => 'customfield_10081',
        'values'             => [$NagiosData{'Hostname'}]
      }
    ]
  });

  # Auto acknowledge of the problem
  my $nagios_extcmd = "/var/run/nagios/nagios.cmd";
  my $date=`/bin/date +%s`;
  chomp ($date);

  my $msg = defined($NagiosData{'Service Description'}) 
	  ? "[$date] ACKNOWLEDGE_SVC_PROBLEM;$NagiosData{'Hostname'};$NagiosData{'Service Description'};0;1" 
	  : "[$date] ACKNOWLEDGE_HOST_PROBLEM;$NagiosData{'Hostname'};0;1";

  open(FILE, ">> $nagios_extcmd") || die ("Cannot open file $nagios_extcmd: $!");
  print FILE "$msg";
  close (FILE);

  # die if there's an error
  die $call->faultstring if $call->fault;

  $jira->call ("jira1.logout", $auth);
}

