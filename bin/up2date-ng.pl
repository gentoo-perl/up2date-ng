#!/usr/bin/perl

# -----------------------------------------------------------------------------
#
# up2date-ng
#
# date        : 2007-10-19
# author      : Christian Hartmann <ian@gentoo.org>
# contributors: Michael Cummings <mcummings@gentoo.org>
#               Yuval Yaari <yuval@gentoo.org>
#               Daniel Westermann-Clark <daniel@acceleration.net>
# version     : 0.24
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
use PortageXS;
Getopt::Long::Configure("bundling");

# - init vars & contants >
my $VERSION			= '0.24';
my $pxs				= PortageXS->new();
my $portdir			= $pxs->getPortdir();
my @scan_portage_categories	= ();
my $up2date_config_dir		= './';
my $category_list_file		= $up2date_config_dir.'up2date_category.list';
my $package_mask_file		= $up2date_config_dir.'up2date_package.mask';
my $package_altname_file	= $up2date_config_dir.'up2date_package.altname';
my @timeData			= localtime(time);
my %modules			= ();
my @tmp_availableVersions	= ();
my @packages2update		= ();
my @tmp_v			= ();
my %pmask			= ();
my %paltname			= ();
my @need_packagealtname		= ();
my $cat_pkg			= '';
my $cpan_searchstring		= '';
my $html_packagelist_table	= '';
my $mail_packagelist_table	= '';
my $p_modulename		= '';
my $xml_packagelist_table	= '';
my $bumplist_packagelist	= '';
my $DEBUG			= 0;
my $generate_all		= 0;
my $generate_bumplist		= 0;
my $generate_html		= 0;
my $generate_mail		= 0;
my $generate_packagelist	= 0;
my $generate_xml		= 0;
my $force_cpan_reload		= 0;
my $hasVirtual			= 0;
my $numberPackagesTotal		= 0;
my $tmp;
my $mod;

# - get options >
printHeader();
GetOptions(
	'debug'			=> \$DEBUG,
	'force-cpan-reload'	=> \$force_cpan_reload,
	'generate-all'		=> \$generate_all,
	'generate-bumplist'	=> \$generate_bumplist,
	'generate-html'		=> \$generate_html,
	'generate-mail'		=> \$generate_mail,
	'generate-packagelist'	=> \$generate_packagelist,
	'generate-xml'		=> \$generate_xml,
	'help|h'		=> sub { exit(printUsage()); },
	'portdir=s'		=> \$portdir,
	) or exit(printUsage());

if ($generate_all) {
	$generate_xml=1;
	$generate_mail=1;
	$generate_html=1;
	$generate_packagelist=1;
	$generate_bumplist=1;
}

# - Print settings and do some basic checks >
if (-d $portdir) {
	$pxs->print_ok("PORTDIR: ".$portdir."\n");
}
else {
	$pxs->print_err("PORTDIR not set or incorrect!\n\n");
	exit(0);
}
$pxs->print_ok("checking for dirs..\n");
foreach my $this_category (@scan_portage_categories) {
	print "   ".$portdir."/".$this_category;
	if (-d $portdir."/".$this_category) {
		print ".. ok\n";
	}
	else {
		print ".. directory does not exist - aborting!\n\n";
		exit(0);
	}
}

# - Parse up2date_package.mask >
if (-f $package_mask_file) {
	$pxs->print_ok('parsing '.$package_mask_file."\n");
	
	$pmask{'all'} = $pxs->getFileContents($package_mask_file);
	
	foreach my $line (split(/\n/,$pmask{'all'})) {
		$line=~s/^[ |\t]+//;	# leading whitespaces and tabs
		$line=~s/[ |\t]+$//;	# trailing whitespaces and tabs
		$line=~s/#(.*)//g;	# remove comments
		
		if ($line ne '') {
			if (substr($line,0,2) eq '>=') {
				# - block package versions greater/equal then given version (e.g. >=dev-perl/Video-Info-0.999) >
				$tmp=substr($line,2,length($line)-2);
				$tmp=~s/([a-zA-Z\-]+)\/([a-zA-Z\-]+)-([0-9a-zA-Z\._\-]+)/$1\/$2/;
				$pmask{'package'}{$tmp}{'version'}=$3;
				$pmask{'package'}{$tmp}{'operator'}='>=';
			}
			elsif (substr($line,0,1) eq '>') {
				# - block package versions greater then given version (e.g. >dev-perl/Video-Info-0.993) >
				$tmp=substr($line,1,length($line)-1);
				$tmp=~s/([a-zA-Z\-]+)\/([a-zA-Z\-]+)-([0-9a-zA-Z\._\-]+)/$1\/$2/;
				$pmask{'package'}{$tmp}{'version'}=$3;
				$pmask{'package'}{$tmp}{'operator'}='>';
			}
			elsif (substr($line,0,1) eq '=') {
				# - block one package version (e.g. =dev-perl/Video-Info-0.999) >
				$tmp=substr($line,1,length($line)-1);
				$tmp=~s/([a-zA-Z\-]+)\/([a-zA-Z\-]+)-([0-9a-zA-Z\._\-]+)/$1\/$2/;
				$pmask{'package'}{$tmp}{'version'}=$3;
				$pmask{'package'}{$tmp}{'operator'}='=';
			}
			else {
				# - block whole package (e.g. dev-perl/Video-Info) >
				$tmp=$line;
				$pmask{'package'}{$tmp}{'operator'}='*';
				$pmask{'package'}{$tmp}{'version'}=0;
			}
			
			if ($DEBUG) {
				print "package: ".$tmp."\n";
				print "pmask{'package'}{'".$tmp."'}{'version'} : ".$pmask{'package'}{$tmp}{'version'}."\n";
				print "pmask{'package'}{'".$tmp."'}{'operator'}: ".$pmask{'package'}{$tmp}{'operator'}."\n";
				print "\n";
			}
		}
	}
}
else {
	$pxs->print_info("No package.mask file available - Skipping\n");
}

# - Parse up2date_package.mask >
if (-f $package_altname_file) {
	$pxs->print_ok('parsing '.$package_altname_file."\n");
	
	$paltname{'all'} = $pxs->getFileContents($package_altname_file);
	
	foreach my $line (split(/\n/,$paltname{'all'})) {
		$line=~s/^[ |\t]+//;	# leading whitespaces and tabs
		$line=~s/[ |\t]+$//;	# trailing whitespaces and tabs
		$line=~s/#(.*)//g;	# remove comments
		
		if ($line ne '' && $line ne ' ') {
			$line=~s/[ |\t]+/ /; # remove multiple whitespaces and tabs
			my @tmp=split(/ /,$line);
			
			# - set $paltname{'portage'}{<portage-packagename>} = <cpan-packagename> (in lowercase) >
			$paltname{'portage'}{lc($tmp[0])}=lc($tmp[1]);

			if ($DEBUG) { print $tmp[0]." ".$paltname{'portage'}{lc($tmp[0])}."\n"; }
		}
	}
}
else {
	$pxs->print_info("No up2date_package.altname file available - Skipping\n");
}

# - Get categorys to check >
@scan_portage_categories=$pxs->getPortageXScategorylist('perl');

# - get package/version info from portage and cpan >
print "\n";
$pxs->print_ok("getting infos from CPAN\n");
getCPANPackages($force_cpan_reload);
print "\n";
$pxs->print_ok("getting package information from portage-tree\n");
print "\n";
getPerlPackages();

# - get some work done >
$pxs->print_ok("Available updates:\n");
foreach my $p_original_modulename (sort keys %{$modules{'portage_lc'}}) {
	if ($DEBUG) { print $p_original_modulename."\n"; }
	$p_modulename=$p_original_modulename;
	
	if (! $modules{'cpan_lc'}{$p_modulename}) {
		# - Could not find a matching package name - probably not a CPAN-module >
		if ($DEBUG) { print "- Could not find CPAN-Module ('".$p_modulename."') for package '".$p_original_modulename."'!\n"; }
		
		# - Look for an entry in up2date_package.altname for this package >
		if ($paltname{'portage'}{$p_original_modulename}) {
			# - found entry in up2date_package.altname >
			if ($paltname{'portage'}{$p_original_modulename} ne "-") {
				if ($DEBUG) { print "- Found entry for this package. Using '".$paltname{'portage'}{$p_original_modulename}."' now.\n"; }
				
				$p_modulename=$paltname{'portage'}{$p_original_modulename};
				
				if (! defined $modules{'cpan_lc'}{$p_modulename}) {
					# - entry in up2date_package.altname does not match >
					if ($DEBUG) { print "- Could not find CPAN-Module for given entry ('".$paltname{'portage'}{$p_original_modulename}."')! Please correct! Skipping..\n"; }
					push(@need_packagealtname,$modules{'portage'}{$p_original_modulename}{'name'});
					next;
				}
			}
			else {
				# - Package has been marked as "non-CPAN-module" >
				if ($DEBUG) { print "- Package '".$p_modulename."' has been marked as non-CPAN-module. Skipping.\n"; }
				next;
			}
		}
		else {
			# - no entry in up2date_package.altname found for $p_modulename >
			if ($DEBUG) { print "- No entry in up2date_package.altname found for package '".$p_modulename."'!\n"; }
			push(@need_packagealtname,$modules{'portage'}{$p_original_modulename}{'name'});
			next;
		}
	}
	
	# - Package found >
	
	# - Convert portage version >
	@tmp_v=split(/\./,$modules{'portage_lc'}{$p_original_modulename});
	$modules{'portage_lc_original-portage-version'}{$p_original_modulename}=$modules{'portage_lc'}{$p_original_modulename};
	if ($#tmp_v > 1) {
		if ($DEBUG) { print " converting version -> ".$modules{'portage_lc'}{$p_original_modulename}; }
		$modules{'portage_lc'}{$p_original_modulename}=$tmp_v[0].".";
		for (1..$#tmp_v) { $modules{'portage_lc'}{$p_original_modulename}.= $tmp_v[$_]; }
		if ($DEBUG) { print " -> ".$modules{'portage_lc'}{$p_original_modulename}."\n"; }
	}
	
	# - Portage package matches CPAN package >
	if ($modules{'cpan_lc'}{$p_modulename} > $modules{'portage_lc'}{$p_original_modulename}) {
		# - package needs some lovin - check if package/version has been masked >
		$cat_pkg = $modules{'portage'}{$p_original_modulename}{'category'}."/".$modules{'portage'}{$p_original_modulename}{'name'};
		
		if (defined $pmask{'package'}{$cat_pkg}{'operator'}) {
			# - package is masked >
			if ($pmask{'package'}{$tmp}{'operator'} eq "*") {
				# - all versions of this package have been masked - skip >
				if ($DEBUG) { print "All versions of this package have been masked - skip\n"; }
				next;
			}
			elsif ($pmask{'package'}{$tmp}{'operator'} eq ">=") {
				# - all versions greater/equal than {'version'} have been masked >
				if ($modules{'cpan_lc'}{$p_modulename} >= $pmask{'package'}{$tmp}{'version'}) {
					# - cpan version has been masked - skip >
					if ($DEBUG) { print "cpan version has been masked - skip\n"; }
					next;
				}
			}
			elsif ($pmask{'package'}{$tmp}{'operator'} eq ">") {
				# - all versions greater than {'version'} have been masked >
				if ($modules{'cpan_lc'}{$p_modulename} > $pmask{'package'}{$tmp}{'version'}) {
					# - cpan version has been masked - skip >
					if ($DEBUG) { print "cpan version has been masked - skip\n"; }
					next;
				}
			}
			elsif ($pmask{'package'}{$tmp}{'operator'} eq "=") {
				# - this version has been masked >
				if ($modules{'cpan_lc'}{$p_modulename} == $pmask{'package'}{$tmp}{'version'}) {
					# - cpan version has been masked - skip >
					if ($DEBUG) { print "cpan version has been masked - skip\n"; }
					next;
				}
			}
		}
		
		# - print update msg >
		print '   '.$modules{'portage'}{$p_original_modulename}{'category'}."/".$modules{'portage'}{$p_original_modulename}{'name'}." needs updating. Ebuild: ".$modules{'portage_lc'}{$p_original_modulename}."; CPAN: ".$modules{'cpan_lc'}{$p_modulename}."\n";
		
		# - store packagename - it needs to be updated >
		push(@packages2update,$modules{'portage'}{$p_original_modulename}{'category'}."/".$modules{'portage'}{$p_original_modulename}{'name'});
		
		# - check for virtuals >
		if (-d $portdir.'/virtual/perl-'.$modules{'portage'}{$p_original_modulename}{'name'}) {
			$hasVirtual=1;
		}
		else {
			$hasVirtual=0;
		}
		
		# - generate searchstring for search.cpan.org >
		$cpan_searchstring=$p_original_modulename;
		$cpan_searchstring=~s/-/::/g;
		
		if ($generate_xml) {
			$xml_packagelist_table .= "  <tr>\n";
			if ($hasVirtual) {
				$xml_packagelist_table .= "    <ti><uri link=\"http://search.cpan.org/search?query=".$cpan_searchstring."&amp;mode=all\">".$modules{'portage'}{$p_original_modulename}{'name'}."</uri> (virtual/perl-".$modules{'portage'}{$p_original_modulename}{'name'}.")</ti>\n";
			}
			else {
				$xml_packagelist_table .= "    <ti><uri link=\"http://search.cpan.org/search?query=".$cpan_searchstring."&amp;mode=all\">".$modules{'portage'}{$p_original_modulename}{'name'}."</uri></ti>\n";
			}
			$xml_packagelist_table .= "    <ti align=\"right\">".$modules{'portage_lc'}{$p_original_modulename}."</ti>\n";
			$xml_packagelist_table .= "    <ti align=\"right\">".$modules{'cpan_lc'}{$p_modulename}."</ti>\n";
			$xml_packagelist_table .= "  </tr>\n";
		}
		
		if ($generate_mail) {
			$mail_packagelist_table .= "  ".$modules{'portage'}{$p_original_modulename}{'name'};
			if ($hasVirtual) { $mail_packagelist_table.=" *"; }
			for(0..(35-($hasVirtual*2)-length($modules{'portage_lc'}{$p_original_modulename})-length($p_original_modulename))) {
				$mail_packagelist_table .= " ";
			}
			$mail_packagelist_table .= " ".$modules{'portage_lc'}{$p_original_modulename};
			for(0..(20-length($modules{'cpan_lc'}{$p_modulename}))) {
				$mail_packagelist_table .= " ";
			}
			$mail_packagelist_table .= " ".$modules{'cpan_lc'}{$p_modulename};
			$mail_packagelist_table .= "\n";
		}

		if ($generate_html) {
			$html_packagelist_table .= "\t\t\t<tr>\n";
			if ($hasVirtual) {
				$html_packagelist_table .= "\t\t\t\t<td><a href=\"http://search.cpan.org/search?query=".$cpan_searchstring."&amp;mode=all\">".$modules{'portage'}{$p_original_modulename}{'name'}."</a> (virtual/perl-".$modules{'portage'}{$p_original_modulename}{'name'}.")</td>\n";
			}
			else {
				$html_packagelist_table .= "\t\t\t\t<td><a href=\"http://search.cpan.org/search?query=".$cpan_searchstring."&amp;mode=all\">".$modules{'portage'}{$p_original_modulename}{'name'}."</a></td>\n";
			}
			$html_packagelist_table .= "\t\t\t\t<td align=\"right\">".$modules{'portage_lc'}{$p_original_modulename}."</td>\n";
			$html_packagelist_table .= "\t\t\t\t<td align=\"right\">".$modules{'cpan_lc'}{$p_modulename}."</td>\n";
			$html_packagelist_table .= "\t\t\t</tr>\n";
		}
		
		if ($generate_bumplist) {
			$bumplist_packagelist .= $modules{'portage'}{$p_original_modulename}{'category'}.'/'.$modules{'portage'}{$p_original_modulename}{'name'}.' ';
			if ($hasVirtual) {
				$bumplist_packagelist .= '1 ';
			}
			else {
				$bumplist_packagelist .= '0 ';
			}
			$bumplist_packagelist .= $modules{'portage_lc_original-portage-version'}{$p_original_modulename}.' ';
			$bumplist_packagelist .= $modules{'cpan_lc'}{$p_modulename}."\n";
		}
	}
	else {
		if ($DEBUG) { print $p_original_modulename." is uptodate\n"; }
	}
}

$numberPackagesTotal=(keys %{$modules{'portage_lc'}});
print "\n";
$pxs->print_ok("total packages suspected as outdated: ".($#packages2update+1)." of ".$numberPackagesTotal."\n");
print "\n";

# - Generate xml >
if ($generate_xml) {
	$pxs->print_ok("called with --generate-xml\n");
	my $xml = $pxs->getFileContents("template_outdated-cpan-packages.xml");
	my $dateXML = sprintf("%u-%02u-%02u",int($timeData[5]+1900),($timeData[4]+1),$timeData[3]);
	my $numberOutdated = ($#packages2update+1);
	chomp($xml_packagelist_table);
	$xml =~ s/<TMPL_PACKAGELIST_TABLE>/$xml_packagelist_table/;
	$xml =~ s/<TMPL_VAR_DATE>/$dateXML/g;
	$xml =~ s/<TMPL_NUMBER_OUTDATED>/$numberOutdated/;
	$xml =~ s/<TMPL_VAR_UP2DATE-NG-VERSION>/$VERSION/;
	$xml =~ s/<TMPL_NUMBER_PACKAGES_TOTAL>/$numberPackagesTotal/;
	
	$pxs->print_ok("creating outdated-cpan-packages.xml\n");
	open(FH,">outdated-cpan-packages.xml") || die ("Cannot open/write to file outdated-cpan-packages.xml");
	print FH $xml;
	close(FH);
	$pxs->print_ok("done!\n\n");
}

# - Generate mail >
if ($generate_mail) {
	$pxs->print_ok("called with --generate-mail\n");
	my $mail = $pxs->getFileContents("template_outdated-cpan-packages.mail");
	$mail_packagelist_table .= "\nTotal packages suspected as outdated: ".($#packages2update+1)." of ".$numberPackagesTotal."\n";
	$mail =~ s/<TMPL_PACKAGELIST_TABLE>/$mail_packagelist_table/;
	$mail =~ s/<TMPL_VAR_UP2DATE-NG-VERSION>/$VERSION/;
	
	$pxs->print_ok("creating outdated-cpan-packages.mail\n");
	open(FH,">outdated-cpan-packages.mail") || die ("Cannot open/write to file outdated-cpan-packages.mail");
	print FH $mail;
	close(FH);
	$pxs->print_ok("done!\n\n");
}

# - Generate html >
if ($generate_html) {
	$pxs->print_ok("called with --generate-html\n");
	my $html = $pxs->getFileContents("template_outdated-cpan-packages.html");
	my $dateHTML = sprintf("%u-%02u-%02u",int($timeData[5]+1900),($timeData[4]+1),$timeData[3]);
	my $numberOutdated = ($#packages2update+1);
	chomp($html_packagelist_table);
	$html =~ s/<TMPL_PACKAGELIST_TABLE>/$html_packagelist_table/;
	$html =~ s/<TMPL_VAR_DATE>/$dateHTML/g;
	$html =~ s/<TMPL_NUMBER_OUTDATED>/$numberOutdated/;
	$html =~ s/<TMPL_VAR_UP2DATE-NG-VERSION>/$VERSION/;
	$html =~ s/<TMPL_NUMBER_PACKAGES_TOTAL>/$numberPackagesTotal/;

	$pxs->print_ok("creating outdated-cpan-packages.html\n");
	open(FH,">outdated-cpan-packages.html") || die ("Cannot open/write to file outdated-cpan-packages.html");
	print FH $html;
	close(FH);
	$pxs->print_ok("done!\n\n");
}

# - Generate bumplist >
if ($generate_bumplist) {
	$pxs->print_ok("called with --generate-bumplist\n");
	$pxs->print_ok("creating outdated-cpan-packages.bumplist\n");
	open(FH,">outdated-cpan-packages.bumplist") || die ("Cannot open/write to file outdated-cpan-packages.bumplist");
	print FH $bumplist_packagelist;
	close(FH);
	$pxs->print_ok("done!\n\n");
}

# - Generate packagelist >
if ($generate_packagelist) {
	$pxs->print_ok("called with --generate-packagelist\n");
	$pxs->print_ok("creating outdated-cpan-packages.packagelist\n");
	open(FH,">outdated-cpan-packages.packagelist") || die ("Cannot open/write to file outdated-cpan-packages.packagelist");
	foreach (@packages2update) {
		print FH $_."\n";
	}
	close(FH);
	$pxs->print_ok("done!\n\n");
}

# - Any packages not found? Do we need additional entries in up2date_package.altname? >
if ($#need_packagealtname >= 0) {
	$pxs->print_info("".($#need_packagealtname+1)." packages were found where a up2date_package.altname entry is missing or wrong:\n");
	foreach (@need_packagealtname) {
		print "   - ".$_."\n";
	}
	print "   Please add entries for these packages to the up2date_package.altname file.\n";
}

print "\n";
exit(0);

# -----------------------------------------------------------------------------
# subs >
# -----------------------------------------------------------------------------

sub getPerlPackages {
	my %excludeDirs			= ("." => 1, ".." => 1, "metadata" => 1, "licenses" => 1, "eclass" => 1, "distfiles" => 1, "virtual" => 1, "profiles" => 1);
	my @matches			= ();
	my $dhp;
	my $tc;
	my $tp;
	
	foreach $tc (@scan_portage_categories) {
		next if (!-d $portdir.'/'.$tc);
		$dhp = new DirHandle($portdir.'/'.$tc);
		while (defined($tp = $dhp->read)) {
			# - not excluded and $_ is a dir?
			if (! $excludeDirs{$tp} && -d $portdir.'/'.$tc.'/'.$tp) {
				@tmp_availableVersions=();
				my @tmp_availableEbuilds = $pxs->getAvailableEbuilds($tc.'/'.$tp,$portdir);
				foreach (@tmp_availableEbuilds) {
					push(@tmp_availableVersions,$pxs->getEbuildVersion($_));
				}
				
				# - get highest version >
				if ($#tmp_availableVersions>-1) {
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

sub getCPANPackages {
	my $force_cpan_reload	= shift;
	my $cpan_pn		= "";
	my @tmp_v		= ();
	
	if ($force_cpan_reload) {
		# - User forced reload of the CPAN index >
		CPAN::Index->force_reload();
	}
	
	for $mod (CPAN::Shell->expand("Module","/./")) {
		if (defined $mod->cpan_version) {
			# - Fetch CPAN-filename and cut out the filename of the tarball.
			#   We are not using $mod->id here because doing so would end up
			#   missing a lot of our ebuilds/packages >
			$cpan_pn = $mod->cpan_file;
			$cpan_pn =~ s|.*/||;
			
			if ($mod->cpan_version eq "undef" && ($cpan_pn=~m/ / || $cpan_pn eq "" || ! $cpan_pn )) {
				# - invalid line - skip that one >
				next;
			}
			
			# - Right now both are "MODULE-FOO-VERSION-EXT" >
			my $cpan_version = $cpan_pn;
			
			# - Drop "-VERSION-EXT" from cpan_pn >
			$cpan_pn =~ s/(?:-?)?(?:v?[\d\.]+[a-z]?)?\.(?:tar|tgz|zip|bz2|gz|tar\.gz)?$//;
			
			if ( length(lc($cpan_version)) >= length(lc($cpan_pn)) ) {
				# - Drop "MODULE-FOO-" from version >
				if (length(lc($cpan_version)) == length(lc($cpan_pn))) {
					$cpan_version=0;
				}
				else {
					$cpan_version = substr($cpan_version,length(lc($cpan_pn))+1,length(lc($cpan_version))-length(lc($cpan_pn))-1);
				}
				if (defined $cpan_version) {
					$cpan_version =~ s/\.(?:tar|tgz|zip|bz2|gz|tar\.gz)?$//;
					
					# - Remove any leading/trailing stuff (like "v" in "v5.2.0") we don't want >
					$cpan_version=~s/^[a-zA-Z]+//;
					$cpan_version=~s/[a-zA-Z]+$//;
					
					# - Convert CPAN version >
					@tmp_v=split(/\./,$cpan_version);
					if ($#tmp_v > 1) {
						if ($DEBUG) { print " converting version -> ".$cpan_version; }
						$cpan_version=$tmp_v[0].".";
						for (1..$#tmp_v) { $cpan_version.= $tmp_v[$_]; }
						if ($DEBUG) { print " -> ".$cpan_version."\n"; }
					}
					
					if ($cpan_version eq "") { $cpan_version=0; }
					
					# - Don't replace versions from CPAN if they're older than the one we've got >
					if (! exists($modules{'cpan'}{$cpan_pn}) || $modules{'cpan'}{$cpan_pn} < $cpan_version) {
						$modules{'cpan'}{$cpan_pn} = $cpan_version;
						$modules{'cpan_lc'}{lc($cpan_pn)} = $cpan_version;
					}
				}
			}
		}
	}
	return 0;
}

sub printHeader {
	print "\n".color("green bold")." up2date-ng".color("reset")." version ".$VERSION." - brought to you by the Gentoo perl-herd-maintainer ;-)\n";
	print "                           Distributed under the terms of the GPL-2\n\n";
}

sub printUsage {
	print "  --generate-xml         : generate GuideXML file with table of outdated packages\n";
	print "                           (using template_outdated-cpan-packages.xml)\n";
	print "  --generate-mail        : generate an mail body\n";
	print "                           (using template_outdated-cpan-packages.mail)\n";
	print "  --generate-html        : generate html file with table of outdated packages\n";
	print "                           (using template_outdated-cpan-packages.html)\n";
	print "  --generate-packagelist : generate list of outdated packages\n";
	print "  --generate-bumplist    : generate list of outdated packages for bumping\n";
	print "  --generate-all         : enables generation on xml, mail, html and packagelist\n";
	print "  --force-cpan-reload    : forces reload of the CPAN indexes\n";
	print "  --portdir              : use given PORTDIR instead of the one defined in make.conf\n";
	print "  --debug                : show debug information\n";
	print "  -h, --help             : show this help\n";
	print "\n";
	
	return 0;
}

# - Here comes the POD >

=head1 NAME

up2date-ng - Compare module versions (ebuild vs CPAN)

=head1 VERSION

This document refers to version 0.24 of up2date-ng

=head1 SYNOPSIS

up2date-ng [option]...

=head1 DESCRIPTION

up2date-ng is a tool that compares the versions of perl packages in portage
with the version of the packages on CPAN. up2date-ng is developed and used
by the Gentoo perl-herd maintainers to keep track of which cpan related
ebuilds could be versionbumped.

=head1 ARGUMENTS

  --generate-xml           generate GuideXML file with table of outdated packages
                           (using template_outdated-cpan-packages.xml)

  --generate-mail          generate an mail body
                           (using template_outdated-cpan-packages.mail)

  --generate-html          generate html file with table of outdated packages
                           (using template_outdated-cpan-packages.html)

  --generate-packagelist   generate list of outdated packages

  --generate-bumplist      generate list of outdated packages for bumping

  --generate-all           enables generation on xml, mail, html and packagelist

  --force-cpan-reload      forces reload of the CPAN indexes

  --portdir                use given PORTDIR instead of the one defined in make.conf

  --debug                  show debug information

  -h, --help               show options and versionnumber

=head1 AUTHOR

Christian Hartmann <ian@gentoo.org>

=head1 CONTRIBUTORS

Many thanks go out to all the people listed below:

Michael Cummings <mcummings@gentoo.org>
Yuval Yaari <yuval@gentoo.org>
Daniel Westermann-Clark <daniel@acceleration.net>

=head1 TODO

Put your stuff here and poke me.

=head1 REPORTING BUGS

Please report bugs via http://bugs.gentoo.org/ or https://bugs.gentoo.org/

=head1 LICENSE

up2date-ng - Compare module versions (ebuild vs CPAN)
Copyright (C) 2007  Christian Hartmann

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
