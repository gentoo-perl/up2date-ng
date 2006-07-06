#!/usr/bin/perl

# -----------------------------------------------------------------------------
#
# up2date-ng.pl
#
# date        : 2006-07-06
# author      : Christian Hartmann <ian@gentoo.org>
# version     : 0.19
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
my $VERSION			= "0.19";
my $portdir			= getPortdir();
my @scan_portage_categories	= ();
my $package_mask_file		= "up2date_package.mask";
my $package_altname_file	= "up2date_package.altname";
my $category_list_file		= "up2date_category.list";
my @timeData			= localtime(time);
my %modules			= ();
my @tmp_availableVersions	= ();
my @packages2update		= ();
my @tmp_v			= ();
my %pmask			= ();
my %paltname			= ();
my @need_packagealtname		= ();
my $p_modulename		= "";
my $xml_packagelist_table	= "";
my $mail_packagelist_table	= "";
my $html_packagelist_table	= "";
my $cat_pkg			= "";
my $cpan_searchstring		= "";
my $DEBUG			= 0;
my $generate_xml		= 0;
my $generate_mail		= 0;
my $generate_html		= 0;
my $generate_packagelist	= 0;
my $generate_all		= 0;
my $force_cpan_reload		= 0;
my $verbose			= 0;
my $tmp;
my $mod;

# - init colors >
my $yellow	= color("yellow bold");
my $green	= color("bold green");
my $white	= color("bold white");
my $cyan	= color("bold cyan");
my $red		= color("bold red");
my $reset	= color("reset");

# - get options >
printHeader();
GetOptions(
	'debug'			=> \$DEBUG,
	'force-cpan-reload'	=> \$force_cpan_reload,
	'generate-all'		=> \$generate_all,
	'generate-html'		=> \$generate_html,
	'generate-mail'		=> \$generate_mail,
	'generate-packagelist'	=> \$generate_packagelist,
	'generate-xml'		=> \$generate_xml,
	'help|h'		=> sub { printUsage(); },
	'portdir=s'		=> \$portdir,
	'verbose|v'		=> \$verbose
	) || printUsage();

if ($generate_all)
{
	$generate_xml=1;
	$generate_mail=1;
	$generate_html=1;
	$generate_packagelist=1;
}
if ($generate_xml+$generate_mail+$generate_html+$generate_packagelist+$DEBUG+$verbose == 0) { printUsage(); }

# - Print settings and do some basic checks >
if (-d $portdir)
{
	print $green." *".$reset." PORTDIR: ".$portdir."\n";
}
else
{
	print $red." *".$reset." PORTDIR not set or incorrect!\n";
	exit(0);
}
print $green." *".$reset." checking for dirs..\n";
foreach my $this_category (@scan_portage_categories)
{
	print "   ".$portdir."/".$this_category;
	if (-d $portdir."/".$this_category)
	{
		print ".. ok\n";
	}
	else
	{
		print ".. directory does not exist - aborting!\n";
		exit(0);
	}
}

# - Parse up2date_package.mask >
if (-f $package_mask_file)
{
	print $green." *".$reset." parsing ".$package_mask_file."\n";
	
	$pmask{'all'} = getFileContents($package_mask_file);
	
	foreach my $line (split(/\n/,$pmask{'all'}))
	{
		$line=~s/^[ |\t]+//;	# leading whitespaces and tabs
		$line=~s/[ |\t]+$//;	# trailing whitespaces and tabs
		$line=~s/#(.*)//g;	# remove comments
		
		if ($line ne "")
		{
			if (substr($line,0,2) eq ">=")
			{
				# - block package versions greater/equal then given version (e.g. >=dev-perl/Video-Info-0.999) >
				$tmp=substr($line,2,length($line)-2);
				$tmp=~s/([a-zA-Z\-]+)\/([a-zA-Z\-]+)-([0-9a-zA-Z\._\-]+)/$1\/$2/;
				$pmask{'package'}{$tmp}{'version'}=$3;
				$pmask{'package'}{$tmp}{'operator'}=">=";
			}
			elsif (substr($line,0,1) eq ">")
			{
				# - block package versions greater then given version (e.g. >dev-perl/Video-Info-0.993) >
				$tmp=substr($line,1,length($line)-1);
				$tmp=~s/([a-zA-Z\-]+)\/([a-zA-Z\-]+)-([0-9a-zA-Z\._\-]+)/$1\/$2/;
				$pmask{'package'}{$tmp}{'version'}=$3;
				$pmask{'package'}{$tmp}{'operator'}=">";
			}
			elsif (substr($line,0,1) eq "=")
			{
				# - block one package version (e.g. =dev-perl/Video-Info-0.999) >
				$tmp=substr($line,1,length($line)-1);
				$tmp=~s/([a-zA-Z\-]+)\/([a-zA-Z\-]+)-([0-9a-zA-Z\._\-]+)/$1\/$2/;
				$pmask{'package'}{$tmp}{'version'}=$3;
				$pmask{'package'}{$tmp}{'operator'}="=";
			}
			else
			{
				# - block whole package (e.g. dev-perl/Video-Info) >
				$tmp=$line;
				$pmask{'package'}{$tmp}{'operator'}="*";
				$pmask{'package'}{$tmp}{'version'}=0;
			}
			
			if ($DEBUG)
			{
				print "package: ".$tmp."\n";
				print "pmask{'package'}{'".$tmp."'}{'version'} : ".$pmask{'package'}{$tmp}{'version'}."\n";
				print "pmask{'package'}{'".$tmp."'}{'operator'}: ".$pmask{'package'}{$tmp}{'operator'}."\n";
				print "\n";
			}
		}
	}
}
else
{
	print $yellow." *".$reset." No package.mask file available - Skipping\n";
}

# - Parse up2date_package.mask >
if (-f $package_altname_file)
{
	print $green." *".$reset." parsing ".$package_altname_file."\n";
	
	$paltname{'all'} = getFileContents($package_altname_file);
	
	foreach my $line (split(/\n/,$paltname{'all'}))
	{
		$line=~s/^[ |\t]+//;	# leading whitespaces and tabs
		$line=~s/[ |\t]+$//;	# trailing whitespaces and tabs
		$line=~s/#(.*)//g;	# remove comments
		
		if ($line ne "" && $line ne " ")
		{
			$line=~s/[ |\t]+/ /; # remove multiple whitespaces and tabs
			my @tmp=split(/ /,$line);
			
			# - set $paltname{'portage'}{<portage-packagename>} = <cpan-packagename> (in lowercase) >
			$paltname{'portage'}{lc($tmp[0])}=lc($tmp[1]);

			if ($DEBUG) { print $tmp[0]." ".$paltname{'portage'}{lc($tmp[0])}."\n"; }
		}
	}
}
else
{
	print $yellow." *".$reset." No package.altname file available - Skipping\n";
}

# - Parse up2date_category.list >
if (-f $category_list_file)
{
	print $green." *".$reset." parsing ".$category_list_file."\n";
	
	foreach my $line (split(/\n/,getFileContents($category_list_file)))
	{
		$line=~s/^[ |\t]+//;	# leading whitespaces and tabs
		$line=~s/[ |\t]+$//;	# trailing whitespaces and tabs
		$line=~s/#(.*)//g;	# remove comments
		
		if ($line ne "" && $line ne " ")
		{
			push (@scan_portage_categories,$line);
			if ($DEBUG) { print "adding '".$line."' to categories-searchlist\n"; }
		}
	}
}
else
{
	print $red." *".$reset." No category.list file available - Aborting\n";
	exit(0);
}

# - get package/version info from portage and cpan >
print "\n";
print $green." *".$reset." getting infos from CPAN\n";
getCPANPackages($force_cpan_reload);
print "\n";
print $green." *".$reset." getting package information from portage-tree\n";
getPerlPackages();

# - get some work done >
foreach my $p_original_modulename (sort keys %{$modules{'portage_lc'}})
{
	if ($DEBUG) { print $p_original_modulename."\n"; }
	$p_modulename=$p_original_modulename;
	
	if (! $modules{'cpan_lc'}{$p_modulename}) 
	{
		# - Could not find a matching package name - probably not a CPAN-module >
		if ($DEBUG) { print "- Could not find CPAN-Module ('".$p_modulename."') for package '".$p_original_modulename."'!\n"; }
		
		# - Look for an entry in up2date_package.altname for this package >
		if ($paltname{'portage'}{$p_original_modulename})
		{
			# - found entry in package.altname >
			if ($paltname{'portage'}{$p_original_modulename} ne "-")
			{
				if ($DEBUG) { print "- Found entry for this package. Using '".$paltname{'portage'}{$p_original_modulename}."' now.\n"; }
				
				$p_modulename=$paltname{'portage'}{$p_original_modulename};
				
				if (! defined $modules{'cpan_lc'}{$p_modulename})
				{
					# - entry in package.altname does not match >
					if ($DEBUG) { print "- Could not find CPAN-Module for given entry ('".$paltname{'portage'}{$p_original_modulename}."')! Please correct! Skipping..\n"; }
					push(@need_packagealtname,$modules{'portage'}{$p_original_modulename}{'name'});
					next;
				}
			}
			else
			{
				# - Package has been marked as "non-CPAN-module" >
				if ($DEBUG) { print "- Package '".$p_modulename."' has been marked as non-CPAN-module. Skipping.\n"; }
				next;
			}
		}
		else
		{
			# - no entry in package.altname found for $p_modulename >
			if ($DEBUG) { print "- No entry in package.altname found for package '".$p_modulename."'!\n"; }
			push(@need_packagealtname,$modules{'portage'}{$p_original_modulename}{'name'});
			next;
		}
	}
	
	# - Package found >
	
	# - Convert portage version >
	@tmp_v=split(/\./,$modules{'portage_lc'}{$p_original_modulename});
	if ($#tmp_v > 1)
	{
		if ($DEBUG) { print " converting version -> ".$modules{'portage_lc'}{$p_original_modulename}; }
		$modules{'portage_lc'}{$p_original_modulename}=$tmp_v[0].".";
		for (1..$#tmp_v) { $modules{'portage_lc'}{$p_original_modulename}.= $tmp_v[$_]; }
		if ($DEBUG) { print " -> ".$modules{'portage_lc'}{$p_original_modulename}."\n"; }
	}
	
	# - Portage package matches CPAN package >
	if ($modules{'cpan_lc'}{$p_modulename} > $modules{'portage_lc'}{$p_original_modulename})
	{
		# - package needs some lovin - check if package/version has been masked >
		$cat_pkg = $modules{'portage'}{$p_original_modulename}{'category'}."/".$modules{'portage'}{$p_original_modulename}{'name'};
		
		if (defined $pmask{'package'}{$cat_pkg}{'operator'})
		{
			# - package is masked >
			if ($pmask{'package'}{$tmp}{'operator'} eq "*")
			{
				# - all versions of this package have been masked - skip >
				if ($DEBUG) { print "All versions of this package have been masked - skip\n"; }
				next;
			}
			elsif ($pmask{'package'}{$tmp}{'operator'} eq ">=")
			{
				# - all versions greater/equal than {'version'} have been masked >
				if ($modules{'cpan_lc'}{$p_modulename} >= $pmask{'package'}{$tmp}{'version'})
				{
					# - cpan version has been masked - skip >
					if ($DEBUG) { print "cpan version has been masked - skip\n"; }
					next;
				}
			}
			elsif ($pmask{'package'}{$tmp}{'operator'} eq ">")
			{
				# - all versions greater than {'version'} have been masked >
				if ($modules{'cpan_lc'}{$p_modulename} > $pmask{'package'}{$tmp}{'version'})
				{
					# - cpan version has been masked - skip >
					if ($DEBUG) { print "cpan version has been masked - skip\n"; }
					next;
				}
			}
			elsif ($pmask{'package'}{$tmp}{'operator'} eq "=")
			{
				# - this version has been masked >
				if ($modules{'cpan_lc'}{$p_modulename} == $pmask{'package'}{$tmp}{'version'})
				{
					# - cpan version has been masked - skip >
					if ($DEBUG) { print "cpan version has been masked - skip\n"; }
					next;
				}
			}
		}
		
		if ($verbose) { print $modules{'portage'}{$p_original_modulename}{'category'}."/".$modules{'portage'}{$p_original_modulename}{'name'}." needs updating. Ebuild: ".$modules{'portage_lc'}{$p_original_modulename}."; CPAN: ".$modules{'cpan_lc'}{$p_modulename}."\n"; }
		
		# - store packagename - it needs to be updated >
		push(@packages2update,$modules{'portage'}{$p_original_modulename}{'category'}."/".$modules{'portage'}{$p_original_modulename}{'name'});
		
		# - generate searchstring for search.cpan.org >
		$cpan_searchstring=$p_original_modulename;
		$cpan_searchstring=~s/-/::/g;
			
		if ($generate_xml)
		{
			$xml_packagelist_table .= "  <tr>\n";
			$xml_packagelist_table .= "    <ti><uri link=\"http://search.cpan.org/search?query=".$cpan_searchstring."&amp;mode=all\">".$modules{'portage'}{$p_original_modulename}{'name'}."</uri></ti>\n";
			$xml_packagelist_table .= "    <ti align=\"right\">".$modules{'portage_lc'}{$p_original_modulename}."</ti>\n";
			$xml_packagelist_table .= "    <ti align=\"right\">".$modules{'cpan_lc'}{$p_modulename}."</ti>\n";
			$xml_packagelist_table .= "  </tr>\n";
		}
		
		if ($generate_mail)
		{
			$mail_packagelist_table .= "  ".$modules{'portage'}{$p_original_modulename}{'name'};
			for(0..(35-length($modules{'portage_lc'}{$p_original_modulename})-length($p_original_modulename)))
			{
				$mail_packagelist_table .= " ";
			}
			$mail_packagelist_table .= " ".$modules{'portage_lc'}{$p_original_modulename};
			for(0..(20-length($modules{'cpan_lc'}{$p_modulename})))
			{
				$mail_packagelist_table .= " ";
			}
			$mail_packagelist_table .= " ".$modules{'cpan_lc'}{$p_modulename};
			$mail_packagelist_table .= "\n";
		}

		if ($generate_html)
		{
			$html_packagelist_table .= "\t\t\t<tr>\n";
			$html_packagelist_table .= "\t\t\t\t<td><a href=\"http://search.cpan.org/search?query=".$cpan_searchstring."&amp;mode=all\">".$modules{'portage'}{$p_original_modulename}{'name'}."</td>\n";
			$html_packagelist_table .= "\t\t\t\t<td align=\"right\">".$modules{'portage_lc'}{$p_original_modulename}."</td>\n";
			$html_packagelist_table .= "\t\t\t\t<td align=\"right\">".$modules{'cpan_lc'}{$p_modulename}."</td>\n";
			$html_packagelist_table .= "\t\t\t</tr>\n";
		}
	}
	else
	{
		if ($DEBUG) { print $p_original_modulename." is uptodate\n"; }
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
	my $dateXML = sprintf("%u-%02u-%02u",int($timeData[5]+1900),($timeData[4]+1),$timeData[3]);
	my $numberOutdated = ($#packages2update+1);
	chomp($xml_packagelist_table);
	$xml =~ s/<TMPL_PACKAGELIST_TABLE>/$xml_packagelist_table/;
	$xml =~ s/<TMPL_VAR_DATE>/$dateXML/g;
	$xml =~ s/<TMPL_NUMBER_OUTDATED>/$numberOutdated/;
	$xml =~ s/<TMPL_VAR_UP2DATE-NG-VERSION>/$VERSION/;
	
	print $green." *".$reset." creating outdated-cpan-packages.xml\n";
	open(FH,">outdated-cpan-packages.xml") || die ("Cannot open/write to file outdated-cpan-packages.xml");
	print FH $xml;
	close(FH);
	print $green." *".$reset." done!\n\n";
}

# - Generate mail >
if ($generate_mail)
{
	print $green." *".$reset." called with --generate-mail\n";
	my $mail = getFileContents("template_outdated-cpan-packages.mail");
	$mail_packagelist_table .= "\nTotal packages suspected as outdated: ".($#packages2update+1)."\n";
	$mail =~ s/<TMPL_PACKAGELIST_TABLE>/$mail_packagelist_table/;
	$mail =~ s/<TMPL_VAR_UP2DATE-NG-VERSION>/$VERSION/;
	
	print $green." *".$reset." creating outdated-cpan-packages.mail\n";
	open(FH,">outdated-cpan-packages.mail") || die ("Cannot open/write to file outdated-cpan-packages.mail");
	print FH $mail;
	close(FH);
	print $green." *".$reset." done!\n\n";
}

# - Generate html >
if ($generate_html)
{
	print $green." *".$reset." called with --generate-html\n";
	my $html = getFileContents("template_outdated-cpan-packages.html");
	my $dateHTML = sprintf("%u-%02u-%02u",int($timeData[5]+1900),($timeData[4]+1),$timeData[3]);
	my $numberOutdated = ($#packages2update+1);
	chomp($html_packagelist_table);
	$html =~ s/<TMPL_PACKAGELIST_TABLE>/$html_packagelist_table/;
	$html =~ s/<TMPL_VAR_DATE>/$dateHTML/g;
	$html =~ s/<TMPL_NUMBER_OUTDATED>/$numberOutdated/;
	$html =~ s/<TMPL_VAR_UP2DATE-NG-VERSION>/$VERSION/;
	
	print $green." *".$reset." creating outdated-cpan-packages.html\n";
	open(FH,">outdated-cpan-packages.html") || die ("Cannot open/write to file outdated-cpan-packages.html");
	print FH $html;
	close(FH);
	print $green." *".$reset." done!\n\n";
}

# - Generate packagelist >
if ($generate_packagelist)
{
	print $green." *".$reset." called with --generate-packagelist\n";
	print $green." *".$reset." creating outdated-cpan-packages.packagelist\n";
	open(FH,">outdated-cpan-packages.packagelist") || die ("Cannot open/write to file outdated-cpan-packages.packagelist");
	foreach (@packages2update)
	{
		print FH $_."\n";
	}
	close(FH);
	print $green." *".$reset." done!\n\n";
}

# - Any packages not found? Do we need additional entries in package.altname? >
if ($#need_packagealtname >= 0)
{
	print $yellow." *".$reset." ".($#need_packagealtname+1)." packages were found where a package.altname entry is missing or wrong:\n";
	foreach (@need_packagealtname)
	{
		print "   - ".$_."\n";
	}
	print "   Please add entries for these packages to the package.altname file.\n";
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
				if ($#tmp_availableVersions>-1)
				{
					$modules{'portage_lc_realversion'}{lc($tp)}=(sort(@tmp_availableVersions))[$#tmp_availableVersions];
					$modules{'portage_lc'}{lc($tp)}=$modules{'portage_lc_realversion'}{lc($tp)};
					
					# - get rid of -rX >
					$modules{'portage_lc'}{lc($tp)}=~s/([a-zA-Z0-9\-_\/]+)-r[0-9+]/$1/;
					$modules{'portage_lc'}{lc($tp)}=~s/([a-zA-Z0-9\-_\/]+)-rc[0-9+]/$1/;
					$modules{'portage_lc'}{lc($tp)}=~s/([a-zA-Z0-9\-_\/]+)_p[0-9+]/$1/;
					$modules{'portage_lc'}{lc($tp)}=~s/([a-zA-Z0-9\-_\/]+)_pre[0-9+]/$1/;
					
					# - get rid of other stuff we don't want >
					$modules{'portage_lc'}{lc($tp)}=~s/([a-zA-Z0-9\-_\/]+)_alpha[0-9+]?/$1/;
					$modules{'portage_lc'}{lc($tp)}=~s/([a-zA-Z0-9\-_\/]+)_beta[0-9+]?/$1/;
					$modules{'portage_lc'}{lc($tp)}=~s/[a-zA-Z]+$//;

					$modules{'portage'}{lc($tp)}{'name'}=$tp;
					$modules{'portage'}{lc($tp)}{'category'}=$tc;
				}
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
	my @packagelist	= ();
	
	if (-e $PORTDIR."/".$catPackage)
	{
		# - get list of ebuilds >
		my $dh = new DirHandle($PORTDIR."/".$catPackage);
		while (defined($_ = $dh->read))
		{
			if ($_ =~ m/(.+)\.ebuild$/)
			{
				push(@packagelist,$_);
			}
		}
	}
	
	return @packagelist;
}


# Description:
# Returns version of an ebuild. (Without -rX string etc.)
# $version = getEbuildVersionSpecial("foo-1.23-r1.ebuild");
sub getEbuildVersionSpecial
{
	my $ebuildVersion = shift;
	$ebuildVersion=substr($ebuildVersion,0,length($ebuildVersion)-7);
	$ebuildVersion =~ s/^([a-zA-Z0-9\-_\/\+]*)-([0-9\.]+[a-zA-Z]?)([\-r|\-rc|_alpha|_beta|_pre|_p]?)/$2$3/;
		
	return $ebuildVersion;
}

sub getCPANPackages
{
	my $force_cpan_reload	= shift;
	my $cpan_pn		= "";
	my @tmp_v		= ();
	
	if ($force_cpan_reload)
	{
		# - User forced reload of the CPAN index >
		CPAN::Index->force_reload();
	}
	
	for $mod (CPAN::Shell->expand("Module","/./"))
	{
		if (defined $mod->cpan_version)
		{
			# - Fetch CPAN-filename and cut out the filename of the tarball.
			#   We are not using $mod->id here because doing so would end up
			#   missing a lot of our ebuilds/packages >
			$cpan_pn = $mod->cpan_file;
			$cpan_pn =~ s|.*/||;
			
			if ($mod->cpan_version eq "undef" && ($cpan_pn=~m/ / || $cpan_pn eq "" || ! $cpan_pn ))
			{
				# - invalid line - skip that one >
				next;
			}
			
			# - Right now both are "MODULE-FOO-VERSION-EXT" >
			my $cpan_version = $cpan_pn;
			
			# - Drop "-VERSION-EXT" from cpan_pn >
			$cpan_pn =~ s/(?:-?)?(?:v?[\d\.]+[a-z]?)?\.(?:tar|tgz|zip|bz2|gz|tar\.gz)?$//;
			
			if ( length(lc($cpan_version)) >= length(lc($cpan_pn)) )
			{
				# - Drop "MODULE-FOO-" from version >
				if (length(lc($cpan_version)) == length(lc($cpan_pn)))
				{
					$cpan_version=0;
				}
				else
				{
					$cpan_version = substr($cpan_version,length(lc($cpan_pn))+1,length(lc($cpan_version))-length(lc($cpan_pn))-1);
				}
				if (defined $cpan_version)
				{
					$cpan_version =~ s/\.(?:tar|tgz|zip|bz2|gz|tar\.gz)?$//;
					
					# - Remove any leading/trailing stuff (like "v" in "v5.2.0") we don't want >
					$cpan_version=~s/^[a-zA-Z]+//;
					$cpan_version=~s/[a-zA-Z]+$//;
					
					# - Convert CPAN version >
					@tmp_v=split(/\./,$cpan_version);
					if ($#tmp_v > 1)
					{
						if ($DEBUG) { print " converting version -> ".$cpan_version; }
						$cpan_version=$tmp_v[0].".";
						for (1..$#tmp_v) { $cpan_version.= $tmp_v[$_]; }
						if ($DEBUG) { print " -> ".$cpan_version."\n"; }
					}
					
					if ($cpan_version eq "") { $cpan_version=0; }
					
					$modules{'cpan'}{$cpan_pn} = $cpan_version;
					$modules{'cpan_lc'}{lc($cpan_pn)} = $cpan_version;
				}
			}
		}
	}
	return 0;
}

sub getPortdir
{
	my $portdir	= getParamFromFile(getFileContents("/etc/make.conf"),"PORTDIR","lastseen");
	
	if (! $portdir)
	{
		$portdir = getParamFromFile(getFileContents("/etc/make.globals"),"PORTDIR","lastseen");
	}
	
	return $portdir;
}

sub printHeader
{
	print "\n";
	print $green." up2date-ng.pl".$reset." version ".$VERSION." - brought to you by the Gentoo perl-herd-maintainer ;-)\n";
	print "                              Distributed under the terms of the GPL-2\n";
	print "\n";
}

sub printUsage
{
	print "  --generate-xml         : generate GuideXML file with table of outdated packages\n";
	print "                           (using template_outdated-cpan-packages.xml)\n";
	print "  --generate-mail        : generate an mail body\n";
	print "                           (using template_outdated-cpan-packages.mail)\n";
	print "  --generate-html        : generate html file with table of outdated packages\n";
	print "                           (using template_outdated-cpan-packages.html)\n";
	print "  --generate-packagelist : generate list of outdated packages\n";
	print "  --generate-all         : enables generation on xml, mail, html and packagelist\n";
	print "  --force-cpan-reload    : forces reload of the CPAN indexes\n";
	print "  --portdir              : use given PORTDIR instead of the one defined in make.conf\n";
	print "  -v, --verbose          : be a bit more verbose\n";
	print "  --debug                : show debug information\n";
	print "  -h, --help             : show this help\n";
	print "\n";
	
	exit(0);
}

# - Here comes the POD >

=head1 NAME

up2date-ng - Compare module versions (ebuild vs CPAN)

=head1 VERSION

This document refers to version 0.19 of up2date-ng

=head1 SYNOPSIS

up2date-ng [option]...

=head1 DESCRIPTION

up2date-ng is a tool that compares the versions of perl packages in portage
with the version of the packages on CPAN. up2date-ng is developed and used
by the Gentoo perl-herd maintainers to keep track of which cpan related
ebuilds could be versionbumped.

=head1 AGRUMENTS

  --generate-xml           generate GuideXML file with table of outdated packages
                           (using template_outdated-cpan-packages.xml)

  --generate-mail          generate an mail body
                           (using template_outdated-cpan-packages.mail)

  --generate-html          generate html file with table of outdated packages
                           (using template_outdated-cpan-packages.html)

  --generate-packagelist   generate list of outdated packages

  --generate-all           enables generation on xml, mail, html and packagelist

  --force-cpan-reload      forces reload of the CPAN indexes

  --portdir                use given PORTDIR instead of the one defined in make.conf

  -v, --verbose            be a bit more verbose

  --debug                  show debug information

  -h, --help               show options and versionnumber

=head1 AUTHOR

Christian Hartmann <ian@gentoo.org>

=head1 TODO

Put your stuff here and poke me.

=head1 REPORTING BUGS

Please report bugs via http://bugs.gentoo.org/ or https://bugs.gentoo.org/

=head1 LICENSE

up2date-ng - Compare module versions (ebuild vs CPAN)
Copyright (C) 2006  Christian Hartmann

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

=cut
