#!/usr/bin/perl

# -----------------------------------------------------------------------------
#
# up2date-ng.pl
#
# date        : 2006-04-20
# author      : Christian Hartmann <ian@gentoo.org>
# version     : 0.1
# license     : GPL-2
# description : Scripts that compares the versions of perl packages in portage
#               with the version of the packages on CPAN
#
# header      : $Header: $
#
# -----------------------------------------------------------------------------
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# -----------------------------------------------------------------------------

# - modules >
use warnings;
use strict;
use DirHandle;
use CPAN;
use Term::ANSIColor;
use Getopt::Long;
Getopt::Long::Configure("bundling");

# - init vars & contants >
my $VERSION			= "0.1";
my $portdir			= getParamFromFile(getFileContents("/etc/make.conf"),"PORTDIR","lastseen") || "/usr/portage";
my @scan_portage_categories	= qw(dev-perl perl-core);
my @timeData			= localtime(time);
my %modules			= ();
my @tmp_availableVersions	= ();
my @packages2update		= ();
my @tmp_v			= ();
my $p_modulename		= "";
my $xml_packagelist_table	= "";
my $mail_packagelist_table	= "";
my $DEBUG			= 0;
my $generate_xml		= 0;
my $generate_mail		= 0;
my $with_qa			= 0;
my $verbose			= 0;
my $gotPackage			= 0;
my $mod;

# - init colors >
my $yellow	= color("yellow bold");
my $green	= color("bold green");
my $white	= color("bold white");
my $cyan	= color("bold cyan");
my $reset	= color("reset");

# - get options >
printHeader();
GetOptions(
	'generate-xml'	=> \$generate_xml,
	'generate-mail'	=> \$generate_mail,
	'with-qa'	=> \$with_qa,
	'debug'		=> \$DEBUG,
	'verbose|v'	=> \$verbose,
	'help|h'	=> sub { printUsage(); }
	) || printUsage();

if ($generate_xml+$generate_mail+$with_qa+$DEBUG+$verbose == 0) { printUsage(); }

# - get package/version info from portage and cpan >
print "\n";
print $green." *".$reset." getting infos from CPAN\n";
getCPANPackages();
print "\n";
print $green." *".$reset." getting package information from portage-tree\n";
getPerlPackages();

# - get some work done >
foreach my $p_original_modulename (sort keys %{$modules{'portage'}})
{
	if ($DEBUG) { print $p_original_modulename."\n"; }
	$p_modulename=$p_original_modulename;
	$p_modulename=~s/-/::/g;
		
	$gotPackage=0;
	if (! defined $modules{'cpan'}{$p_modulename})
	{
		# - Could not find a matching package name - try something different (lowercase) >
		if (defined $modules{'cpan_lc'}{lc($p_modulename)}{'cpan'})
		{
			# - We could find a matching package after getting rid of case-sensitivity >
			if ($with_qa) { print $yellow." *".$reset." [QA-Notice] Package '".$p_original_modulename."' should be renamed to match case: ".$modules{'cpan_lc'}{lc($p_modulename)}{'cpan'}."\n"; }
			$modules{'cpan'}{$modules{'cpan_lc'}{lc($p_modulename)}{'cpan'}}=$modules{'cpan_lc'}{lc($p_modulename)}{'version'};
			$p_modulename=$modules{'cpan_lc'}{lc($p_modulename)}{'cpan'};
			$gotPackage=1;
		}
		else
		{
			if ($DEBUG) { print "ERROR: Could not find CPAN-Module ('".$p_modulename."') for package '".$p_original_modulename."'!\n"; }
		}
	}
	else
	{
		# - Package found without doing any nasty tricks >
		$gotPackage=1;
	}
	
	if ($gotPackage)
	{
		# - Convert portage version >
		@tmp_v=split(/\./,$modules{'portage'}{$p_original_modulename});
		if ($#tmp_v > 1)
		{
			if ($DEBUG) { print " converting version -> ".$modules{'portage'}{$p_original_modulename}; }
			$modules{'portage'}{$p_original_modulename}=$tmp_v[0].".";
			for (1..$#tmp_v) { $modules{'portage'}{$p_original_modulename}.= $tmp_v[$_]; }
			if ($DEBUG) { print " -> ".$modules{'portage'}{$p_original_modulename}."\n"; }
		}
		
		# - Convert CPAN version >
		@tmp_v=split(/\./,$modules{'cpan'}{$p_modulename});
		if ($#tmp_v > 1)
		{
			if ($DEBUG) { print " converting version -> ".$modules{'cpan'}{$p_modulename}; }
			$modules{'cpan'}{$p_modulename}=$tmp_v[0].".";
			for (1..$#tmp_v) { $modules{'cpan'}{$p_modulename}.= $tmp_v[$_]; }
			if ($DEBUG) { print " -> ".$modules{'cpan'}{$p_modulename}."\n"; }
		}
		
		# - Portage package matches CPAN package >
		if ($modules{'cpan'}{$p_modulename} > $modules{'portage'}{$p_original_modulename})
		{
			# - package needs some lovin >
			if ($verbose) { print $p_original_modulename." needs updating. Ebuild: ".$modules{'portage'}{$p_original_modulename}."; CPAN: ".$modules{'cpan'}{$p_modulename}."\n"; }
			
			# - store packagename - it needs to be updated >
			push(@packages2update,$p_original_modulename);
			
			if ($generate_xml)
			{
				$xml_packagelist_table .= "  <tr>\n";
				$xml_packagelist_table .= "    <ti>".$p_original_modulename."</ti>\n";
				$xml_packagelist_table .= "    <ti>".$modules{'portage'}{$p_original_modulename}."</ti>\n";
				$xml_packagelist_table .= "    <ti>".$modules{'cpan'}{$p_modulename}."</ti>\n";
				$xml_packagelist_table .= "  </tr>\n";
			}
			
			if ($generate_mail)
			{
				$mail_packagelist_table .= "  ".$p_original_modulename;
				for(0..(35-length($modules{'portage'}{$p_original_modulename})-length($p_original_modulename)))
				{
					$mail_packagelist_table .= " ";
				}
				$mail_packagelist_table .= " ".$modules{'portage'}{$p_original_modulename};
				for(0..(20-length($modules{'cpan'}{$p_modulename})))
				{
					$mail_packagelist_table .= " ";
				}
				$mail_packagelist_table .= " ".$modules{'cpan'}{$p_modulename};
				$mail_packagelist_table .= "\n";
			}
		}
		else
		{
			if ($DEBUG) { print $p_original_modulename.".. ok\n"; }
		}
	}
}

print "\n";
print $green." *".$reset." total packages suspected as outdated: ".($#packages2update+1)."\n";
print "\n";

# - Generate xml >
if ($generate_xml)
{
	print $green." *".$reset." called with --generate-xml\n";
	my $xml = getFileContents("template_outdated-cpan-packages.xml");
	my $dateXML = int($timeData[5]+1900)."-".$timeData[4]."-".$timeData[3];
	chomp($xml_packagelist_table);
	$xml =~ s/<TMPL_PACKAGELIST_TABLE>/$xml_packagelist_table/;
	$xml =~ s/<TMPL_VAR_DATE>/$dateXML/g;
	
	print $green." *".$reset." creating outdated-cpan-packages.xml\n";
	open(FH,">outdated-cpan-packages.xml") || die ("Cannot open/write to file outdated-cpan-packages.xml");
	print FH $xml;
	close(FH);
	print $green." *".$reset." done!\n";
}

# - Generate mail >
if ($generate_mail)
{
	print $green." *".$reset." called with --generate-mail\n";
	my $mail = getFileContents("template_outdated-cpan-packages.mail");
	$mail_packagelist_table .= "\nTotal packages suspected as outdated: ".($#packages2update+1)."\n";
	$mail =~ s/<TMPL_PACKAGELIST_TABLE>/$mail_packagelist_table/;
	
	print $green." *".$reset." creating outdated-cpan-packages.mail\n";
	open(FH,">outdated-cpan-packages.mail") || die ("Cannot open/write to file outdated-cpan-packages.mail");
	print FH $mail;
	close(FH);
	print $green." *".$reset." done!\n";
}


print "\n";
exit(0);

# -----------------------------------------------------------------------------
# subs >
# -----------------------------------------------------------------------------

sub getPerlPackages
{
	my %excludeDirs			= ("." => 1, ".." => 1, "metadata" => 1, "licenses" => 1, "eclass" => 1, "distfiles" => 1, "virtual" => 1, "profiles" => 1);
	my @matches			= ();
	my $dhp;
	my $tc;
	my $tp;

	foreach $tc (@scan_portage_categories)
	{
		$dhp = new DirHandle($portdir."/".$tc);
		while (defined($tp = $dhp->read))
		{
			# - not excluded and $_ is a dir?
			if (! $excludeDirs{$tp} && -d $portdir."/".$tc."/".$tp)
			{
				@tmp_availableVersions=();
				my @tmp_availableEbuilds = getAvailableEbuilds($portdir,$tc."/".$tp);
				foreach (@tmp_availableEbuilds)
				{
					push(@tmp_availableVersions,getEbuildVersionSpecial($_));
				}
				
				# - get highest version >
				$modules{'portage'}{$tp}=(sort(@tmp_availableVersions))[$#tmp_availableVersions];
			}
		}
		undef $dhp;
	}
}

# Description:
# Returns the value of $param. Expects filecontents in $file.
# $valueOfKey = getParamFromFile($filecontents,$key);
# e.g.
# $valueOfKey = getParamFromFile(getFileContents("/path/to.ebuild","IUSE","firstseen");
sub getParamFromFile
{
	my $file  = shift;
	my $param = shift;
	my $mode  = shift; # ("firstseen","lastseen") - default is "lastseen"
	my $c     = 0;
	my $d     = 0;
	my @lines = ();
	my @aTmp  = (); # temp (a)rray
	my $sTmp  = ""; # temp (s)calar
	my $text  = ""; # complete text/file after being cleaned up and striped
	my $value = ""; # value of $param
	my $this  = "";
	
	# - 1. split file in lines >
	@lines = split(/\n/,$file);

	# - 2 & 3 >
	for($c=0;$c<=$#lines;$c++)
	{
		# - 2. remove leading and trailing whitespaces and tabs from every line >
		$lines[$c]=~s/^[ |\t]+//;  # leading whitespaces and tabs
		$lines[$c]=~s/[ |\t]+$//;  # trailing whitespaces and tabs
		
		# - 3. remove comments >
		$lines[$c]=~s/#(.*)//g;
		
		if ($lines[$c]=~/^$param="(.*)"/)
		{
			# single-line with quotationmarks >
			$value=$1;
		
			if ($mode eq "firstseen")
			{
				# - 6. clean up value >
				$value=~s/^[ |\t]+//; # remove leading whitespaces and tabs
				$value=~s/[ |\t]+$//; # remove trailing whitespaces and tabs
				$value=~s/\t/ /g;     # replace tabs with whitespaces
				$value=~s/ {2,}/ /g;  # replace 1+ whitespaces with 1 whitespace
				return $value;
			}
		}
		elsif ($lines[$c]=~/^$param="(.*)/)
		{
			# multi-line with quotationmarks >
			$value=$1." ";
			for($d=$c+1;$d<=$#lines;$d++)
			{
				# - look for quotationmark >
				if ($lines[$d]=~/(.*)"/)
				{
					# - found quotationmark; append contents and leave loop >
					$value.=$1;
					last;
				}
				else
				{
					# - no quotationmark found; append line contents to $value >
					$value.=$lines[$d]." ";
				}
			}
		
			if ($mode eq "firstseen")
			{
				# - 6. clean up value >
				$value=~s/^[ |\t]+//; # remove leading whitespaces and tabs
				$value=~s/[ |\t]+$//; # remove trailing whitespaces and tabs
				$value=~s/\t/ /g;     # replace tabs with whitespaces
				$value=~s/ {2,}/ /g;  # replace 1+ whitespaces with 1 whitespace
				return $value;
			}
		}
		elsif ($lines[$c]=~/^$param=(.*)/)
		{
			# - single-line without quotationmarks >
			$value=$1;
			
			if ($mode eq "firstseen")
			{
				# - 6. clean up value >
				$value=~s/^[ |\t]+//; # remove leading whitespaces and tabs
				$value=~s/[ |\t]+$//; # remove trailing whitespaces and tabs
				$value=~s/\t/ /g;     # replace tabs with whitespaces
				$value=~s/ {2,}/ /g;  # replace 1+ whitespaces with 1 whitespace
				return $value;
			}
		}
	}
	
	# - 6. clean up value >
	$value=~s/^[ |\t]+//; # remove leading whitespaces and tabs
	$value=~s/[ |\t]+$//; # remove trailing whitespaces and tabs
	$value=~s/\t/ /g;     # replace tabs with whitespaces
	$value=~s/ {2,}/ /g;  # replace 1+ whitespaces with 1 whitespace
	
	return $value;
}

# Description:
# Returnvalue is the content of the given file.
# $filecontent = getFileContents($file);
sub getFileContents
{
	my $content	= "";
	
	open(FH,"<".$_[0]) || die("Cannot open file ".$_[0]);
	while(<FH>) { $content.=$_; }
	close(FH);
	return $content;
}

# Description:
# @listOfEbuilds = getAvailableEbuilds($PORTDIR, category/packagename);
sub getAvailableEbuilds
{
	my $PORTDIR	= shift;
	my $catPackage	= shift;
	my @ebuildList	= ();
	
	if (-e $PORTDIR."/".$catPackage)
	{
		# - get list of ebuilds >
		my $dh = new DirHandle($PORTDIR."/".$catPackage);
		while (defined($_ = $dh->read))
		{
			if ($_ =~ m/(.+)\.ebuild$/)
			{
				push(@ebuildList,$_);
			}
		}
	}
	
	return @ebuildList;
}


# Description:
# Returns version of an ebuild. (Without -rX string etc.)
# $version = getEbuildVersionSpecial("/path/to/ebuild");
sub getEbuildVersionSpecial
{
	my $ebuildVersion = shift;
	$ebuildVersion =~ s/([a-zA-Z0-9\-_\/]+)-([0-9a-zA-Z\._\-]+)\.ebuild/$2/;
	
	# - get rid of -rX >
	$ebuildVersion=~s/([a-zA-Z0-9\-_\/]+)-r[0-9+]/$1/;
	$ebuildVersion=~s/([a-zA-Z0-9\-_\/]+)-rc[0-9+]/$1/;
	$ebuildVersion=~s/([a-zA-Z0-9\-_\/]+)_p[0-9+]/$1/;
	
	# - get rid of oter stuff we don't want >
	$ebuildVersion=~s/([a-zA-Z0-9\-_\/]+)_alpha/$1/;
	$ebuildVersion=~s/([a-zA-Z0-9\-_\/]+)_beta/$1/;
	$ebuildVersion=~s/[a-zA-Z]+$//;
	
	return $ebuildVersion;
}

sub getCPANPackages
{
	for $mod (CPAN::Shell->expand("Module","/./"))
	{
		if ( (defined $mod->cpan_version) && ($mod->cpan_version ne "undef") )
		{
			$modules{'cpan'}{$mod->id}=$mod->cpan_version;
			$modules{'cpan_lc'}{lc($mod->id)}{'version'}=$mod->cpan_version;
			$modules{'cpan_lc'}{lc($mod->id)}{'cpan'}=$mod->id;
			
			# - Remove any leading/trailing stuff (like "v" in "v5.2.0") we don't want >
			$modules{'cpan'}{$mod->id}=~s/^[a-zA-Z]+//;
			$modules{'cpan'}{$mod->id}=~s/[a-zA-Z]+$//;
		}
	}
	
	return 0;
}

sub printHeader
{
	print "\n";
	print $green." up2date-ng.pl".$reset." version ".$VERSION." - brought to you by the Gentoo perl-herd-maintainer ;-)\n";
	print "                             Distributed under the terms of the GPL-2\n";
	print "\n";
}

sub printUsage
{
	print "  --generate-xml  : generate GuideXML file with table of outdated packages\n";
	print "                    (using template_outdated-cpan-packages.xml)\n";
	print "  --generate-mail : generate an mail body\n";
	print "                    (using template_outdated-cpan-packages.mail)\n";
	print "  -v, --verbose   : be a bit more verbose\n";
	print "  --with-qa       : show qa-notices\n";
	print "  --debug         : show debug information\n";
	print "  -h, --help      : show this help\n";
	print "\n";
	
	exit(0);
}
