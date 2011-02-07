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
use version 0.77;
use DirHandle;
use CPAN;
use Term::ANSIColor;
use Getopt::Long;
use PortageXS v0.2.11;
use CPAN::DistnameInfo;

#use Data::Dumper;

Getopt::Long::Configure("bundling");

# - init vars & contants >
my $VERSION                 = '0.24';
my $pxs                     = PortageXS->new();
my $portdir                 = $pxs->getPortdir();
my $reponame                = '';
my @scan_portage_categories = ();
my $up2date_config_dir      = './';
my $category_list_file      = $up2date_config_dir . 'up2date_category.list';
my $package_mask_file       = $up2date_config_dir . 'up2date_package.mask';
my $package_altname_file    = $up2date_config_dir . 'up2date_package.altname';
my @timeData                = localtime(time);
my %modules                 = ();
my @packages2update         = ();
my %pmask                   = ();
my %paltname                = ();
my @need_packagealtname     = ();
my $html_packagelist_table  = '';
my $mail_packagelist_table  = '';
my $xml_packagelist_table   = '';
my $bumplist_packagelist    = '';
my $DEBUG                   = 0;
my $generate_all            = 0;
my $generate_bumplist       = 0;
my $generate_html           = 0;
my $generate_mail           = 0;
my $generate_packagelist    = 0;
my $generate_xml            = 0;
my $force_cpan_reload       = 0;
my $hasVirtual              = 0;
my $numberPackagesTotal     = 0;

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
	$reponame = $pxs->getReponame($portdir) || "no-reponame" ;
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
		$line=~s/^[ \t]+//;	# leading whitespaces and tabs
		$line=~s/[ \t]+$//;	# trailing whitespaces and tabs
		$line=~s/#.*//;	# remove comments
		my $tmp;
		if ($line ne '') {
			if (substr($line,0,2) eq '>=') {
				# - block package versions greater/equal then given version (e.g. >=dev-perl/Video-Info-0.999) >
				$tmp=substr($line,2);
				$tmp=~s|([a-zA-Z+_.-]+)/([a-zA-Z0-9+_-]+)-([0-9]+(\.[0-9]+)*[a-z]?[0-9a-zA-Z_-]*)|$1/$2|;
				$pmask{'package'}{$tmp}{'version'}=$3;
				$pmask{'package'}{$tmp}{'operator'}='>=';
			}
			elsif (substr($line,0,1) eq '>') {
				# - block package versions greater then given version (e.g. >dev-perl/Video-Info-0.993) >
				$tmp=substr($line,1);
				$tmp=~s|([a-zA-Z+_.-]+)/([a-zA-Z0-9+_-]+)-([0-9]+(\.[0-9]+)*[a-z]?[0-9a-zA-Z_-]*)|$1/$2|;
				$pmask{'package'}{$tmp}{'version'}=$3;
				$pmask{'package'}{$tmp}{'operator'}='>';
			}
			elsif (substr($line,0,1) eq '=') {
				# - block one package version (e.g. =dev-perl/Video-Info-0.999) >
				$tmp=substr($line,1);
				$tmp=~s|([a-zA-Z+_.-]+)/([a-zA-Z0-9+_-]+)-([0-9]+(\.[0-9]+)*[a-z]?[0-9a-zA-Z_-]*)|$1/$2|;
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

# - Parse up2date_package.altname >
if (-f $package_altname_file) {
	$pxs->print_ok('parsing '.$package_altname_file."\n");

	foreach my $line (split(/\n/,$pxs->getFileContents($package_altname_file))) {
		$line=~s/^[ \t]+//;	# leading whitespaces and tabs
		$line=~s/[ \t]+$//;	# trailing whitespaces and tabs
		$line=~s/#.*//;	# remove comments
		
		if ($line ne '' && $line ne ' ') {
			$line=~s/[ \t]+/ /; # remove multiple whitespaces and tabs
			my @tmp=split(/ /,$line);
			
			# - set $paltname{'portage'}{<portage-packagename>} = <cpan-packagename> (in lowercase) >
			$paltname{$tmp[0]}=$tmp[1];

			if ($DEBUG) { print "'$tmp[0]' => '$paltname{$tmp[0]}'\n"; }
		}
	}
}
else {
	$pxs->print_info("No up2date_package.altname file available - Skipping\n");
}

# - Get categories to check >
@scan_portage_categories=$pxs->getPortageXScategorylist('perl');

# - get package/version info from portage and cpan >
print "\n";
$pxs->print_ok("getting package information from portage-tree\n");
print "\n";
getPerlPackages();
$pxs->print_ok("getting infos from CPAN\n");
getCPANPackages($force_cpan_reload);
print "\n";

# - get some work done >
$pxs->print_ok("Available updates:\n");
foreach my $distname (sort keys %modules) {
	if ($DEBUG) { print $distname."\n"; }
	
	if (! $modules{$distname}{'CPAN_V'}) {
		# - Could not find a matching package name - probably not a CPAN-module >
		if ($DEBUG) { print "- Could not find CPAN-Module ('".$distname."') for package '".$modules{$distname}{'PN'}."'!\n"; }
		push(@need_packagealtname,$distname) unless $paltname{$distname} eq '-';
		next;
	}
	if ($modules{$distname}{'CPAN_V'} > $modules{$distname}{'EBUILD_V'} ) {
		# - package needs some lovin - check if package/version has been masked >
		my $cat_pkg = $modules{$distname}{'CATEGORY'}."/".$modules{$distname}{'PN'};
		
		if (defined $pmask{'package'}{$cat_pkg}{'operator'}) {
			# - package is masked >
			if ($pmask{'package'}{$cat_pkg}{'operator'} eq "*") {
				# - all versions of this package have been masked - skip >
				if ($DEBUG) { print "All versions of this package have been masked - skip\n"; }
				next;
			}
			elsif ($pmask{'package'}{$cat_pkg}{'operator'} eq ">=") {
				# - all versions greater/equal than {'version'} have been masked >
				if ($modules{$distname}{'CPAN_V'} >= version->parse($pmask{'package'}{$cat_pkg}{'version'}) ) {
					# - cpan version has been masked - skip >
					if ($DEBUG) { print "cpan version has been masked - skip\n"; }
					next;
				}
			}
			elsif ($pmask{'package'}{$cat_pkg}{'operator'} eq ">") {
				# - all versions greater than {'version'} have been masked >
				if ($modules{$distname}{'CPAN_V'} > version->parse($pmask{'package'}{$cat_pkg}{'version'}) ) {
					# - cpan version has been masked - skip >
					if ($DEBUG) { print "cpan version has been masked - skip\n"; }
					next;
				}
			}
			elsif ($pmask{'package'}{$cat_pkg}{'operator'} eq "=") {
				# - this version has been masked >
				if ($modules{$distname}{'CPAN_V'} == version->parse($pmask{'package'}{$cat_pkg}{'version'}) ) {
					# - cpan version has been masked - skip >
					if ($DEBUG) { print "cpan version has been masked - skip\n"; }
					next;
				}
			}
		}
		print '   '.$cat_pkg." needs updating. Ebuild: ".$modules{$distname}{'PV'}."; CPAN: ".$modules{$distname}{'CPAN_V'}."\n";
		
		# - store packagename - it needs to be updated >
		push(@packages2update,$cat_pkg);
		
		# - check for virtuals >
		if (-d $portdir.'/virtual/perl-'.$modules{$distname}{'PN'}) {
			$hasVirtual=1;
		}
		else {
			$hasVirtual=0;
		}
		
		if ($generate_xml) {
			$xml_packagelist_table .= "  <tr>\n";
			if ($hasVirtual) {
				$xml_packagelist_table .= "    <ti><uri link=\"http://search.cpan.org/dist/".$distname."\">".$modules{$distname}{'PN'}."</uri> (virtual/perl-".$modules{$distname}{'PN'}.")</ti>\n";
			}
			else {
				$xml_packagelist_table .= "    <ti><uri link=\"http://search.cpan.org/dist/".$distname."\">".$modules{$distname}{'PN'}."</uri></ti>\n";
			}
			$xml_packagelist_table .= "    <ti align=\"right\">".$modules{$distname}{'PV'}."</ti>\n";
			$xml_packagelist_table .= "    <ti align=\"right\"><uri link=\"http://search.cpan.org/dist/".$distname."-".$modules{$distname}{'CPAN_V'}."/\">".$modules{$distname}{'CPAN_V'}."</uri></ti>\n";
			$xml_packagelist_table .= "    <ti><uri link=\"http://search.cpan.org/diff?from=".$distname."-".$modules{$distname}{'EBUILD_V'}."&amp;to=".$distname."-".$modules{$distname}{'CPAN_V'}."&amp;w=1\">Diff</uri></ti>\n";
			$xml_packagelist_table .= "  </tr>\n";
		}
		
		if ($generate_mail) {
			$mail_packagelist_table .= "  ".$distname;
			if ($hasVirtual) { $mail_packagelist_table.=" *"; }
			for(0..(35-($hasVirtual*2)-length($distname)-length($modules{$distname}{'EBUILD_V'}))) {
				$mail_packagelist_table .= " ";
			}
			$mail_packagelist_table .= " ".$modules{$distname}{'EBUILD_V'};
			for(0..(20-length($modules{$distname}{'CPAN_V'}))) {
				$mail_packagelist_table .= " ";
			}
			$mail_packagelist_table .= " ".$modules{$distname}{'CPAN_V'};
			$mail_packagelist_table .= "\n";
		}
		
		if ($generate_html) {
			$html_packagelist_table .= "\t\t\t<tr>\n";
			if ($hasVirtual) {
				$html_packagelist_table .= "\t\t\t\t<td><a href=\"http://search.cpan.org/dist/".$distname."\">".$distname."</a> (virtual/perl-".$distname.")</td>\n";
			}
			else {
				$html_packagelist_table .= "\t\t\t\t<td><a href=\"http://search.cpan.org/dist/".$distname."\">".$distname."</a></td>\n";
			}
			$html_packagelist_table .= "\t\t\t\t<td align=\"right\">".$modules{$distname}{'EBUILD_V'}."</td>\n";
			$html_packagelist_table .= "\t\t\t\t<td align=\"right\">".$modules{$distname}{'CPAN_V'}."</td>\n";
			$html_packagelist_table .= "\t\t\t</tr>\n";
		}
		
		if ($generate_bumplist) {
			$bumplist_packagelist .= $cat_pkg .' ';
			if ($hasVirtual) {
				$bumplist_packagelist .= '1 ';
			}
			else {
				$bumplist_packagelist .= '0 ';
			}
			$bumplist_packagelist .= $modules{$distname}{'PV'}.' ';
			$bumplist_packagelist .= $modules{$distname}{'CPAN_V'}."\n";
		}
	}
	else {
		if ($DEBUG) { print $distname." is uptodate\n"; }
	}
}

$numberPackagesTotal=(keys %modules);
print "\n";
$pxs->print_ok("total packages suspected as outdated: ".($#packages2update+1)." of ".$numberPackagesTotal."\n");
print "\n";

# - Generate xml >
if ($generate_xml) {
	$pxs->print_ok("called with --generate-xml\n");
	my $xml = $pxs->getFileContents("template_outdated-cpan-packages.xml");
	my $dateXML = sprintf("%u-%02u-%02u",int($timeData[5]+1900),($timeData[4]+1),$timeData[3]);
	my $numberOutdated = ($#packages2update+1);
	my $guide_link = "/proj/en/perl/outdated-cpan-packages.xml";
	my $file_name = "outdated-cpan-packages.xml";
	if ($reponame eq 'gentoo') {
		$reponame = "portage";
	} else {
		$file_name  = "outdated-cpan-packages-$reponame.xml";
		$guide_link = "/proj/en/perl/outdated-cpan-packages-$reponame.xml";
	}
	chomp($xml_packagelist_table);
	$xml =~ s/<TMPL_PACKAGELIST_TABLE>/$xml_packagelist_table/;
	$xml =~ s/<TMPL_VAR_DATE>/$dateXML/g;
	$xml =~ s/<TMPL_NUMBER_OUTDATED>/$numberOutdated/;
	$xml =~ s/<TMPL_VAR_UP2DATE-NG-VERSION>/$VERSION/;
	$xml =~ s/<TMPL_NUMBER_PACKAGES_TOTAL>/$numberPackagesTotal/;
	$xml =~ s/<TMPL_REPO_NAME>/$reponame/g;
	$xml =~ s/<TMPL_GUIDE_LINK>/$guide_link/;
	
	$pxs->print_ok("creating $file_name\n");
	open my $fh,'>',"$file_name" or die ("Cannot open/write to file $file_name");
	print $fh $xml;
	close $fh;
	$pxs->print_ok("done!\n\n");
}

# - Generate mail >
if ($generate_mail) {
	$pxs->print_ok("called with --generate-mail\n");
	my $mail = $pxs->getFileContents("template_outdated-cpan-packages.mail");
	my $numberOutdated = ($#packages2update+1);
	$mail =~ s/<TMPL_PACKAGELIST_TABLE>/$mail_packagelist_table/;
	$mail =~ s/<TMPL_NUMBER_OUTDATED>/$numberOutdated/;
	$mail =~ s/<TMPL_NUMBER_PACKAGES_TOTAL>/$numberPackagesTotal/;
	$mail =~ s/<TMPL_VAR_UP2DATE-NG-VERSION>/$VERSION/;
	
	$pxs->print_ok("creating outdated-cpan-packages.mail\n");
	open my $fh, '>','outdated-cpan-packages.mail' or die ("Cannot open/write to file outdated-cpan-packages.mail");
	print $fh $mail;
	close $fh;
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
	open my $fh, '>', 'outdated-cpan-packages.html' or die ("Cannot open/write to file outdated-cpan-packages.html");
	print $fh $html;
	close $fh;
	$pxs->print_ok("done!\n\n");
}

# - Generate bumplist >
if ($generate_bumplist) {
	$pxs->print_ok("called with --generate-bumplist\n");
	$pxs->print_ok("creating outdated-cpan-packages.bumplist\n");
	open my $fh, '>', 'outdated-cpan-packages.bumplist' or die ("Cannot open/write to file outdated-cpan-packages.bumplist");
	print $fh $bumplist_packagelist;
	close $fh;
	$pxs->print_ok("done!\n\n");
}

# - Generate packagelist >
if ($generate_packagelist) {
	$pxs->print_ok("called with --generate-packagelist\n");
	$pxs->print_ok("creating outdated-cpan-packages.packagelist\n");
	open my $fh,'>','outdated-cpan-packages.packagelist' or die ("Cannot open/write to file outdated-cpan-packages.packagelist");
	foreach (@packages2update) {
		print $fh $_."\n";
	}
	close $fh;
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
	my %excludeDirs = (
		"." => 1,
		".." => 1,
		"metadata" => 1,
		"licenses" => 1,
		"eclass" => 1,
		"distfiles" => 1,
		"virtual" => 1,
		"profiles" => 1,
		"CVS" => 1,
	);

	foreach my $tc (@scan_portage_categories) {
		next if (!-d $portdir.'/'.$tc);
		my $dhp = new DirHandle($portdir.'/'.$tc);
		while (defined( my $tp = $dhp->read)) {
			# - not excluded and $_ is a dir?
			if (! $excludeDirs{$tp} && -d "$portdir/$tc/$tp") {
				my $package = $tp;
				if ( exists $paltname{$tp} and $paltname{$tp} ne '-' ) {
					$package = $paltname{$tp};
				}
				$modules{$package}{'PN'}=$tp;
				$modules{$package}{'CATEGORY'}=$tc;
				$modules{$package}{'PV'}=$pxs->getBestEbuildVersion($tc.'/'.$tp,$portdir);
				$modules{$package}{'CPAN_VERSION'}=
					getCPANVERSION($portdir.'/'.$tc.'/'.$tp.'/'.$tp.'-'.$modules{$package}{'PV'}.'.ebuild');
				if ($modules{$package}{'CPAN_VERSION'} ) {
					$modules{$package}{'EBUILD_V'} = version->parse($modules{$package}{'CPAN_VERSION'});
				} else {
					my $version = "".$modules{$package}{'PV'};
					$version =~ s/_.*//;
					$version =~ s/-.*//;
					$version =~ s/[a-zA-z]*$//;
					my @tmp_v = split /\./, $version;
					$version = shift(@tmp_v) .".";
					$version .= shift @tmp_v while @tmp_v;
					$modules{$package}{'EBUILD_V'} = version->parse($version);
				}
			}
		}
		undef $dhp;
	}
}

sub getCPANVERSION {
    my ($file) = @_;
    my $cpan_re = qr{^MODULE_VERSION=(['"]?)([\d.]+)\1$};
    open my ($fh), '<', $file or die "Cannot open $file: $!";
    while (<$fh>) {
        next unless $_ =~ m{$cpan_re};
        return $2;
    }
    close $fh;
    return 0;
}

sub getCPANPackages {
	my $force_cpan_reload	= shift;

	if ($force_cpan_reload) {
		# - User forced reload of the CPAN index >
		CPAN::Index->force_reload();
	}

	for my $mod (CPAN::Shell->expand("Module","/./"),) {
		if (defined $mod->cpan_version) {
			# - Fetch CPAN-filename and cut out the filename of the tarball.
			#   We are not using $mod->id here because doing so would end up
			#   missing a lot of our ebuilds/packages >
			my $d = CPAN::DistnameInfo->new($mod->cpan_file);
			my $cpan_pn = $d->dist();
			next unless $cpan_pn;
			next unless exists $modules{$cpan_pn};
			my $version = $d->version;
			$version =~ s/[a-z]+$//;
			$version =~ s/\.[a-zA-Z][a-zA-Z0-9]*$//; # Crazy PIP stuff
			my $cpan_version = eval { version->parse($version) } ||
				do {
					#if ($DEBUG) { print "$cpan_pn",Dumper $d,"\n"};
					version->parse('0')
				};
			if (! exists( $modules{$cpan_pn}{'CPAN_V'}) || $modules{$cpan_pn}{'CPAN_V'} < $cpan_version) {
				$modules{$cpan_pn}{'CPAN_V'} = $cpan_version;
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
	print << "EOD" ;
  --generate-xml         : generate GuideXML file with table of outdated packages
                           (using template_outdated-cpan-packages.xml)
  --generate-mail        : generate an mail body
                           (using template_outdated-cpan-packages.mail)
  --generate-html        : generate html file with table of outdated packages
                           (using template_outdated-cpan-packages.html)
  --generate-packagelist : generate list of outdated packages
  --generate-bumplist    : generate list of outdated packages for bumping
  --generate-all         : enables generation on xml, mail, html and packagelist
  --force-cpan-reload    : forces reload of the CPAN indexes
  --portdir              : use given PORTDIR instead of the one defined in make.conf
  --debug                : show debug information
  -h, --help             : show this help

EOD

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
