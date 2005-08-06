#!/usr/bin/perl
use Module::Build;
my $build = Module::Build->new(
	module_name        => 'Haver::Client',
	dist_version_from  => 'lib/Haver/Client.pm',
	dist_author        => [
		'Dylan Hardison <dylan@haverdev.org>',
		'Bryan Donlan <bdonlan@haverdev.org>',
	],
	license => 'gpl',
	requires => {
		'perl'           => '5.8.0',
		'Haver::Core'    => 0.08,
		'Digest::SHA1'   => 2.01,
		'Data::Dumper'   => 2.121,
	},
	create_makefile_pl => 'passthrough',
	script_files => [ glob ('bin/*.pl') ],
	# XXX: This is a hack, feel free to remove it...
	($ENV{USER} eq 'dylan') ? (sign => 1) : (),
);

$build->create_build_script;
