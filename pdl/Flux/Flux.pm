use Flux::Core;
use Flux::World;
use Flux::Fluxon;
use Flux::Vertex;
use Flux::Concentration;

package Flux;
use PDL 2.007_13; #2.007 required for PDL_Indx type.
#_13 required for IND_FLAG printf conversion flag macro.

BEGIN {
    package Flux;
    require DynaLoader;
    @ISA = qw(DynaLoader);
    bootstrap Flux;
}

use strict;
use warnings;

=head1 NAME

Flux - the Field Line Universal relaXer (MHD without resistivity); v. 2.0

=head1 SYNOPSIS

  # (from within perl)
  use PDL;
  use Flux;
  $world = new Flux::World;
  <...>

=head1 DESCRIPTION

Flux is the name of the perl module that is used to interface to FLUX,
the Field Line Universal relaXer; it is a resistivity-free
magnetohydrodynamic simulator using the quasi-lagrangian fluxon
approach.  Fluxons are discretized magnetic field lines; they interact
at a distance via the magnetic curvature and pressure forces.

This is the man page for version 2.0 of Flux, released 31-Oct-2007.
At the moment, FLUX is "merely" a topology-conserving force-free field 
solver.  As development proceeds, MHS, QSMHD, and ultimately full MHD 
will be incorporated into the code.

The Flux module is a Perl interface to the underlying 'C' engine.  In 
addition to defining several utility methods used by the other Flux 
modules, it autoloads object definitions for the following object types
(each of which is an interface to the corresponding C structure in the 
C library).  Each object can be accessed as a tied hash, or via special
object methods defined in each module.

=over 3

=item Flux::World

An entire simulation arena.  Each Flux::World object contains "global"
variables specific to that simulation, and has access methods to 
get flux concentrations and fluxons in the simulation.

=item Flux::Concentration

A boundary condition anchor - each fluxon must begin and end at a flux
concentration.  Flux concentrations have locations, flux values, and 
types.  In practice flux concentrations from toy models typically have 
one fluxon apiece, though in empirically driven models they are anticipated
to require more.

=item Flux::Fluxon

A discretized field line, implemented (in C) as a linked list of vertices,
connected by piecewise-linear flux elements ("fluxels").  Each fluxon has a 
source and a sink flux concentration (Flux::Concentration), and is composed 
of a list of vertices (Flux::Vertex) that contain the actual spatial information.

=item Flux::Vertex

A single element of a fluxon.  A vertex contains location and connectivity information
to the next and previous vertices along the same fluxon.

=back

Each of those object types has its own perl module and its own man page (e.g. say
C<man Flux::World> to find out about what you can do with world objects).

VERSION

This is Flux version 2.0 - part of the FLUX 2.0 release.

=head1 GETTING STARTED

If you are reading this as a man page, you are most of the way there.
FLUX is a Perl module that relies on the Perl Data Language (PDL) to
work, as well as on the libflux.a library (written in C, in the "lib"
subdirectory of the FLUX distribution).  If you are not acquainted
with PDL you will want to make sure it is installed, by entering the
"pdl" command at your UNIX prompt (or if, God help you, you are trying
to do MHD simulations from within Microsoft Windows, you should stop
and install Ubuntu now).

The Flux modules themselves handle basic manipulation tasks; to run a
simulation, you will need some additional code that is included in the
"pdl/PDL" directory of the main source code distribution.  The ".pdl"
files in the PDL directory are intended to work with the PDL
autoloader.  Your PDLLIB environment variable, or the @PDLLIB global
list within pdl, determines where the autoloader searches (see
L<PDL::AutoLoader> for details).

In particular, Flux does NOT contain an outermost loop for conducting
relaxations. That is accomplished in perl space. The file
"pdl/PDL/simple_relaxer.pdl" defines a "simple_relaxer" routine that
suffices for many applications.  You can invoke it with
C<simple_relaxer($world, $int, $glob, $n, $opt)>, where C<$world> is a
Flux::World object, $int is an interactive flag (usually 0), $global
performs rigorous neighbor checking (at great expense in speed), and
$n is the desired step number.  The $opt parameter is an options hash;
consult the source code for details.

Here is a sequence of commands that should help you get your first
FLUX relaxation to work:

  use Flux;
  $fluxdir = "/usr/local/src/flux";       # or whatever directory you use
  push(@PDLLIB,"+$fluxdir/pdl/PDL");
  $a = read_world('/usr/local/src/flux/menagerie/potential.flux');
  $a->forces('f_pressure_equi2b','f_curvature','f_vertex4');
  $dt = 0.3;
  simple_relaxer($a,0,0,1000);

The "pdl/menagerie" directory contains several other sample world
description files that you can use to test your code.  See L<Flux::World> 
for details.

=head1 FILE FORMAT

Flux worlds are stored and transferred in an ASCII format that is
parsed and generated by the underlying "C" library.  Here is a
description of the file format.

Flux world files are keyword/value data sets in standard ASCII form.
Lines that are all whitespace or that begin with the '#' character are
comments and are ignored.

Each world description file begins with some global information
coupled with description of the contents of the world or with a
description of how the world or its boundary conditions are to change.
The file format is intended to be useful both to store single-frame
relaxation sets and also to store and transfer time-dependent
datasets.

Each line begins with a keyword followed by some parameters, separated
by whitespace.  Most of the characters of the keyword are ignored;
these are marked with square brackets, as are all other optional parts
of the line.  Quantities to be replaced with numbers or strings are
surrounded with angle-brackets.

All entities receive numeric labels that should be unique.  

For more information, examine the FLUX wiki at 
  https://github.com/d-lamb/fluxon-mhd/wiki/User_Manual

=head2 AUTHOR

Copyright 2004-2008 Craig DeForest.  You may distribute this file 
under the terms of the Gnu Public License (GPL), version  2. 
You should have received a copy of the GPL with this file.  If not,
you may retrieve it from "http://www.gnu.org".

=head2 VERSION

This file is part of the FLUX 2.2 release (22-Nov-2008)

=head1 METHODS

The Flux module itself is a shell that contains no external methods at
all -- see the individual object modules for details on available
methods, or the FLUX wiki for tutorials, templates and sample control
files.

There are several low-level internal methods that are used for
accessing FLUX data structures; you do not want to use them unless you
Really Know What You're Doing.

=cut

##############################
# Global structure-definition variables:
#  $typecodes - converts between object mnemonic name and a type code
#  $methods   - converts between field mnemonic name and access method
#  $codes     - converts between object type, field name, and an access 
#                 code and data type.  The keys associated with each object
#                 mnemnonic name become the keys in the tied hash of each
#                 major Flux object type.
{
    our $typecodes = {
	links =>    1,
	vertex =>   2,
	fluxon =>   3,
        world  =>   4,
	concentration=>5
	};
    
    our $methods = {
	num    =>        [\&_rnum,  \&_wnum  ],
	long   =>        [\&_rlong, \&_wlong ],
	vlab   =>        [\&_rlong, \&_wvlab ],
	flab   =>        [\&_rlong, \&_wflab ],
	fclab   =>        [\&_rlong, \&_wfclab ],
	vector =>        [\&_rvec,  \&_wvec  ],
	vec    =>        [\&_rvec,  \&_wvec  ],
	Vertex =>        [\&_rvertex, undef  ],
	Fluxon =>        [\&_rfluxon, undef  ],
	FluxonList =>    [\&_rfluxonlist, undef],
	Concentration => [ \&_rconcentration, undef ],
	fluxon_conc   => [ \&_rconcentration, \&_wconc_line ],
	World  =>        [ \&_rworld, undef ],
        Neighbors =>     [ sub{ _rdumblist( $typecodes->{vertex}, @_) }, 
			   sub {_wdumblist( $typecodes->{vertex}, @_) }   ],
        Nearby =>        [ sub{ _rdumblist( $typecodes->{vertex}, @_) }, 
			   sub {_wdumblist( $typecodes->{vertex}, @_) }   ],
        Coeffs =>        [ \&_rcoeffs, \&_wcoeffs ], 
        Forces =>        [ \&_rforces, \&_wforces ],
	Bound  =>        [ \&_rbound, \&_wbound ],
        Photosphere =>   [ \&_rphot,  \&_wphot ],
	RCFuncs =>       [ \&_rrecon, \&_wrecon ]
    };

    our $codes = { 
	vertex => {
	    line=>        [1, 'Fluxon'],
	    prev=>        [2, 'Vertex'],
	    next=>        [3, 'Vertex'],
	    x=>           [4, 'vector'],
	    neighbors=>   [5, 'Neighbors'],
	    nearby=>      [6, 'Nearby'],
	    scr=>         [7, 'vector'],
	    r=>           [8, 'num'],
	    a=>           [9, 'num'],
	    b_vec=>      [10, 'vec'],
	    b_mag=>      [11, 'num'],
	    f_v=>        [12, 'vec'],
	    f_s=>        [13, 'vec'],
	    f_t=>        [14, 'vec'],
	    f_s_tot=>    [15, 'num'],
	    f_v_tot=>    [16, 'num'],
	    r_v=>        [17, 'num'],
	    r_s=>        [18, 'num'],
	    r_cl=>       [19, 'num'],
	    label=>      [20, 'vlab'],
	    links_sum=>  [21, 'num'],
	    links_n=>    [22, 'long'],
	    links_up=>   [23, 'Vertex'],
	    links_left=> [24, 'Vertex'],
	    links_right=>[25, 'Vertex'],
	    energy=>     [26, 'num'],
	    plan_step=>  [27, 'vec'],
	    f_n_tot=>    [28, 'num'],
	    r_ncl=>      [29, 'num'],
	    neighbors_n=>   [30,'long'],
	    neighbors_size=>[31,'long'],
	    nearby_n=>      [32,'long'],
	    nearby_size=>   [33,'long'],
	    f_v_ps=>        [34,'vec'],
	    rho=>           [35,'num'],
	    T=>             [36,'num'],
	    A=>             [37,'num'],
	    p=>             [38,'vec']
	},
	fluxon => {
	    flux=>	          [1,'num'],
	    label=>               [2,'flab'],
	    start=>               [3,'Vertex'],
	    end=>                 [4,'Vertex'],
	    v_ct=>                [5,'long'],
	    all_links_sum=>       [7,'num'],
	    all_links_n=>         [8,'long'],
	    all_links_up=>        [9,'Fluxon'],
	    all_links_left=>      [10,'Fluxon'],
	    all_links_right=>     [11,'Fluxon'],
	    start_links_sum=>     [13,'num'],
	    start_links_n=>       [14,'long'],
	    start_links_up=>      [15,'Fluxon'],
	    start_links_left=>    [16,'Fluxon'],
	    start_links_right=>   [17,'Fluxon'],
	    end_links_sum=>       [19,'num'],
	    end_links_n=>         [20,'long'],
	    end_links_up=>        [21,'Fluxon'],
	    end_links_left=>      [22,'Fluxon'],
	    end_links_right=>     [23,'Fluxon'],
	    fc_start =>           [24,'fluxon_conc'],
	    fc_end =>             [25,'fluxon_conc'],
            plasmoid =>           [26,'long']
	    },
	world => {
	    frame_number=>       [1,'long'],
	    state =>             [2,'long'],
	    concentrations =>    [3,'Concentration'],
	    lines =>             [4,'Fluxon'],
	    vertices =>          [5,'Vertex'],
	    photosphere =>       [6,'Photosphere'],
	    image =>             [7,'Vertex'],
	    image2 =>            [8,'Vertex'],
	    locale_radius =>     [9,'num'],
	    fc_ob =>            [10,'Concentration'],
	    fc_oe =>            [11,'Concentration'],
	    fc_pb =>            [12,'Concentration'],
	    fc_pe =>            [13,'Concentration'],
	    verbosity =>        [14,'long'],
	    forces =>           [15,'Forces'],
	    scale_b_power=>     [16,'num'],
	    scale_d_power=>     [17,'num'],
	    scale_s_power=>     [18,'num'],
	    scale_ds_power=>    [19,'num'],
	    refct=>             [20,'long'],
	    rc_funcs=>          [21,'RCFuncs'],
	    max_angle=>         [22,'num'],
            mean_angle=>        [23,'num'],
            dtau=>              [24,'num'],
            rel_step=>          [25,'long'],
            coeffs=>            [26,'Coeffs'],
            n_coeffs=>          [27,'long'],
            maxn_coeffs=>       [28,'long'],
	    handle_skew=>       [29,'long'],
	    auto_open=>         [30,'long'],
            default_bound =>    [31,'Bound'],
	    photosphere2 =>     [32,'Photosphere'],
	    masslaw =>          [33,'Forces'],
	    concurrency=>       [34,'long'],
	    f_min=>             [35,'num'],
	    f_max=>             [36,'num'],
	    fr_min=>            [37,'num'],
	    fr_max=>            [38,'num'],
	    ca_min=>            [39,'num'],
	    ca_max=>            [40,'num'],
	    ca_acc=>            [41,'num'],
	    ca_ct=>             [42,'num'],
	    use_fluid=>         [43,'long'],
	    k_b =>              [44,'num'],
	    gravity_type =>     [45,'long'],
	    gravity_origin =>   [46,'vec'],
	    g =>                [47,'num']
	    
	},
	concentration => {
	    world=>		 [1,'World'],
	    flux=>               [2,'num'],
	    label=>              [3,'fclab'],
	    lines=>              [4,'Fluxon'],
	    links_sum=>          [6,'num'],
	    links_n=>            [7,'long'],
	    links_up=>           [8,'Concentration'],
	    links_left=>         [9,'Concentration'],
	    links_right=>        [10,'Concentration'],
	    x=>                  [11,'vector'],
	    locale_radius=>      [12,'num'],
            bound=>              [13,'Bound']
	}
    };



    ##############################
    # Assemble an ordering for next iteration through tied hashes -- sort the links
    # in each tied hash and generate a hash that links by name.
    # Kludgey but it works.

    our $ordering = {};

    foreach my $type(keys %$codes) {
	$ordering->{$type} = {};
	my $thash = $codes->{$type};

	my @order = (
		     sort
		        { $thash->{$a}->[0] <=> $thash->{$b}->[0] } 
		        keys %$thash
		     );

	for my $i(0..$#order) {
	    $ordering->{$type}->{$order[$i]} = $order[$i+1];
	}
    }

}    
	

=pod

=head2 r_val - read a value from a structure

=for usage

   FLUX::r_val( structcode, valcode, typestr );

=for ref

The structcode is the numeric code associated with the structure type; it should be one of the
values from the global hash ref $Flux::typecodes.  The valcode is a numeric type corresponding
to structure field, and typestr is the type string in the global $Flux::codes hash.  If it is a
string, it is used to look up the reader in the global $Flux::methods hash, or if it is an array
ref containing two code refs then they are executed directly.

=cut

sub r_val {
    my( $me, $struct, $field, $type ) = @_;
    my $reader;

    if(ref $type) {
	print "type is $type, ref type is ".(ref $type)."...\n";
	die "r_val: Can't handle ref types yet\n";
    } else {
	$reader = $Flux::methods->{$type}->[0];
    }

    unless( defined($reader)) {
	print "r_val: no read method for type $type ($struct,$field) - returning undef\n";
	return undef;
    }

    &{$reader}( $me, $struct, $field );
}

=pod

=head2 w_val - write a value to a structure

=for usage

    FLUX::w_val( $structcode, $valcode, $typestr, $value );

=for ref

The structcode is the numeric code associated with the structure type; is should be one of the
values from the global hash ref $Flux::typecodes.  The valcode is a numeric type corresponding
to the structure field, and typestr is the type string in the global $Flux::codes hash.  If it is a 
string, it is used to look up the reader in the global $Flux::methods hash, or if it is an array
ref containing two code refs then they are executed directly.  The value is the value to put in the 
structure field.

=cut

sub w_val {
    my( $me, $struct, $field, $type, $val ) = @_;
    my $writer;

    if(ref $type) {
	die "w_val: can't handle ref types yet\n";
    } else {
	$writer = $Flux::methods->{$type}->[1];
    }

    die "w_val: write method is undefined for type $type ...\n"
	unless defined($writer);

    &{$writer}( $me, $struct, $field, $val );
}

=pod

=head2 tree - traverse a tree structure and return all its leaves in a list ref

=for usage

    @list = FLUX::tree($root, $lname);

=for ref

    The lname is the prefix for the link fields in the structure (e.g. "all_links" for the fluxon
tree).  The routine could/should be subclassed as appropriate to pass in individual links fields.

=cut

sub tree {
    my $me = shift;
    my $lname = shift;
    my $whole_tree = shift;

    while($whole_tree && defined($me->{$lname."_up"})) {
	$me = $me->{$lname."_up"};
    }
    
    unless($me->{$lname."_n"}>1) {
	return $me;
    }

    my @out = ();
    my $l = $me->{$lname."_left"};
    my $r = $me->{$lname."_right"};
    
    push(@out, tree($l,$lname)) if(defined $l);
    push(@out, $me);
    push(@out, tree($r,$lname)) if(defined $r);
    @out;
}

##############################
# Read/write a photosphere using the World->photosphere method
sub _rphot {
    my $me = shift;
    my $type = shift;
    my $field = shift;


    barf("_rphot requires a Flux::World") if(ref $me ne 'Flux::World');
    my $p = [$me->photosphere(undef,undef,$field)];

    my $hash = {
	type=>$p->[6]
	};
    if($p->[6]) {
	$hash->{origin} = pdl($p->[0],$p->[1],$p->[2]);
	$hash->{normal} = pdl($p->[3],$p->[4],$p->[5]);
    }
    return $hash;
}
	
sub _wphot {
    my $me = shift;
    my $type = shift;
    my $field = shift;
    my $val = shift;

    barf("_wphot requires a Flux::World\n") 
	unless(ref $me eq 'Flux::World');


    barf("_wphot requires a hash ref with a type field\n")
	unless( ref $val eq 'HASH' and 
		exists $val->{type}
		);

    barf("_wphot: origin and normal fields must each be 3-PDLs\n")
	unless( !$val->{type} or (
				  ref $val->{origin} eq 'PDL' and 
				  ref $val->{normal} eq 'PDL' and
				  $val->{origin}->ndims == 1 and
				  $val->{origin}->dim(0) == 3 and
				  $val->{normal}->ndims == 1 and 
				  $val->{origin}->dim(0) == 3
				  )
		);
    if($val->{type}) {
	$me->photosphere([$val->{origin}->list, $val->{normal}->list],$val->{type},$field);
    } else {
	$me->photosphere([0,0,0,0,0,0],0,$field);
    }
}

sub binary_dump {
    my $world = shift;
    my $fname = shift;

    if($fname =~ m/\.gz$/) {
	my $tmpname = "/tmp/flux-tmp-$$.flx";
	binary_dump_int($world,$tmpname);
	`gzip < $tmpname > $fname`;
	unlink $tmpname;
    } else {
	binary_dump_int($world, $fname);
    }
}

sub binary_read_dumpfile {
    my $fname = shift;
    my $world;

    if($fname =~ m/\.gz$/) {
	my $tmpname = "/tmp/flux-tmp-$$.flx";
	`gunzip < $fname > $tmpname`;
	$world = binary_read_dumpfile_int($tmpname);
	unlink $tmpname;
    } else {
	$world = binary_read_dumpfile_int($fname);
    }
    return $world;
}
    

=pod

=head1 AUTHOR

FLUX is copyright (c) 2004-2007 by Craig DeForest. Development was funded
under grants from NASA's Living With a Star and Solar and Heliospheric Physics
programs, and internally by Southwest Research Institute. The code is
distributable under the terms of the Gnu Public License ("GPL"),
version 2.  You should have received a copy of the GPL with FLUX, in the
file named "COPYING".  

FLUX comes with NO WARRANTY of any kind.

Comments, questions, gripes, or kudos should be directed to
"deforest@boulder.swri.edu".

=cut

use Flux::World;
use Flux::Fluxon;
use Flux::Vertex;
use Flux::Concentration;

$Flux::file_versions = Flux::file_versions();

1;
