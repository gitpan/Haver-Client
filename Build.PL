#!/usr/bin/perl
use Module::Build;
my $build = Module::Build->new(
	module_name        => 'Haver::Client',
	dist_name          => 'haver-client',
	dist_version_from  => 'lib/Haver/Client.pm',
	dist_author        => 'Bryan Donlan <bdonlan@bd-home-comp.no-ip.org>',
	license => 'gpl',
	requires => {
		'perl'           => '5.8.0',
		Haver            => 0.06,
		'Digest::SHA1'   => 2.01,
		'Data::Dumper'   => 2.121,

	},
	create_makefile_pl => 'passthrough',
	script_files => [ glob ('bin/*.pl') ],
);

$build->create_build_script;
