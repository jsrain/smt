#!/usr/bin/env perl
use strict;
use warnings;
use IPC::Open3;
use SMTConstants;
use SMTUtils;

sub jobhandler
{
  my %retval;
  my ($jobtype, $jobid, $args) =  @_;

  SMTUtils::logger ("jobhandler for softwarepush called", $jobid);
  SMTUtils::logger ("softwarepush runs jobid \"$jobid\"", $jobid);


  # check whether this handler can handle requested jobtype
  SMTUtils::error ("wrong job handler: \"softwarepush\" cannot handle \"$jobtype\"", $jobid) if ( $jobtype ne "softwarepush" );


  # collect and verify arguments
  my $force;
  my $agreelicenses;
  my $packages;


  $force   = $args->[0]->{force}->[0]			if ( defined ( $args->[0]->{force}->[0] ) );
  error( "argument missing: force", $jobid )		if ( ! defined( $force ) );
  error( "argument invalid: force", $jobid )		if ( ! ( $force eq "true" || $force eq "false" ) );

  $agreelicenses = $args->[0]->{agreelicenses}->[0]	if ( defined ( $args->[0]->{agreelicenses}->[0] ) );
  error( "argument missing: agreelicenses", $jobid )	if ( ! defined( $agreelicenses ) );
  error( "argument invalid: agreelicenses", $jobid )	if ( ! ( $agreelicenses eq "true" || $agreelicenses eq "false" ) );


  $packages   = $args->[0]->{packages}->[0]->{package}	if ( defined ( $args->[0]->{packages}->[0]->{package}  ) );
  error( "argument missing: packages", $jobid ) 	if ( ! defined( $packages   ));
  error( "argument invalid: packages", $jobid )  	if ( ! isa($packages, 'ARRAY' ) );


  #==  run zypper ==

  my $command = "/usr/bin/zypper";
  my @cmdArgs;
  push (@cmdArgs, "--no-cd");					# ignore CD/DVD repositories
  push (@cmdArgs, "-x");					# xml output
  push (@cmdArgs, "--non-interactive");				# doesn't ask user
  push (@cmdArgs, "in");					# install
  push (@cmdArgs, "-l") if ( $agreelicenses eq "true" );	# agree licenses
  push (@cmdArgs, "-f") if ( $force eq "true" );		# reinstall

  foreach my $pack (@$packages)                                                             
  {                                                                                         
    push (@cmdArgs, $pack);
  }    

  (my $retval, my $stdout, my $stderr) = SMTUtils::executeCommand ( $command, undef, @cmdArgs );

  return (
    stdout => defined ( $stdout )? $stdout : "",
    stderr => defined ( $stderr )? $stderr : "",
    returnvalue => $retval,
    success => ($retval == 0 ) ? "true" : "false",
    message => ($retval == 0 ) ? "softwarepush successfully finished" : "softwarepush failed"
  );

}

SMTUtils::logger ("successfully loaded handler for jobtype \"softwarepush\"");

return 1;

