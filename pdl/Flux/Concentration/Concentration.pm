=head1 NAME

Flux::Concentration - Fluxon MHD boundary condition (line tying post)

=head1 SYNOPSIS

 use PDL;
 use Flux;
  
 $world = read_world($filename);
 $fc = $world->concentration(15);
 print %$fc;

=head1 DESCRIPTION

Flux::Concentration objects are hashes tied to the FLUX_CONCENTRATION structures in the
FLUX library.  They represent endpoints of line-tied field lines.  

There are several special flux concentations in every Flux::World -
the fc_ob, fc_oe, fc_pb, and fc_pe concentrations are image
concentrations that are used for open and plasmoid boundary
conditions.  They act like normal flux concentrations for
accounting-of-flux purposes, but the location data are invalid.

=head2 AUTHOR

Copyright 2004-2008 Craig DeForest.  You may distribute this file 
under the terms of the Gnu Public License (GPL), version  2. 
You should have received a copy of the GPL with this file.  If not,
you may retrieve it from "http://www.gnu.org".

=head2 VERSION

This file is part of the FLUX 2.2 release (22-Nov-2008)

=head1 FUNCTIONS

=cut


package Flux::Concentration;
use PDL;

require Exporter;
require DynaLoader;
our @ISA = qw(Exporter DynaLoader Flux);
our @EXPORT = ();
bootstrap Flux::Concentration;  

use overload '""' => \&_stringify;

sub _stringify {
    my $me = shift;
    my $st;
    my $lct;

    if($me->{lines}) {
	if($me->{lines}->{fc_start}->{label} == $me->{label}) {
	    $st = "exiting ";
	    $lct = $me->{lines}->{start_links_n};
	} elsif($me->{lines}->{fc_end}->{label} == $me->{label}) {
	    $st = "entering";
	    $lct = $me->{lines}->{end_links_n};
	}
    } else {
	$lct = 0;
	$st = "NONE";
    }

    my $ess = ($lct==1 || $lct==-1) ? "" : "s";

    my $s = sprintf("Flux concentration %d: flux=%5g in %d (%s) line%s; location %s\n",
		    $me->{label},
		    $me->{flux},
		    $lct, $st, $ess,
		    $me->{x}
		    );
    return $s;
}

=pod

=head2 fluxon_ids

=for usage

  @list = $fc->fluxon_ids;
  $fluxon_count = $fc->fluxon_ids;

=for ref

Return a list of all fluxon labels associated with the flux concentration.

=cut

sub fluxon_ids {
  my $ref = _fluxon_ids(@_); # Call _fluxons in Concentration.xs
  @$ref;
}

=pod

=head2 fluxons

=for usage

    @fluxons = $fc->fluxons(@ids); ## some of 'em
    @fluxons = $fc->fluxons();     ## all of 'em

=for ref

Return the fluxon(s) associated with this flux concentration, or some of 'em, as a list of Flux::Fluxon
objects.  If you give no arguments, you get all of them.

=cut

sub fluxons {
    my $fc = shift;
    my $w = $fc->{world};
    if(!@_){
	@_ = $fc->fluxon_ids;
    }
    my $id;
    my @fluxons = ();
    while(defined ($id=shift)) {
	push(@fluxons, $w->fluxon($id));
    }
    return @fluxons;
}

=head2 new_fluxon

=for usage

    $fluxon = $fc0->new_fluxon($fc1, $flux, $label, $verts);

=for ref
    
Generates a new fluxon connecting a start flux concentration to an end flux concentration,
with prescribed flux, label, and vertices.  $flux should be the amount of flux to be connected.
$label should be the new unique long-int label to use for the fluxon, or 0 (or undef) to have a new
label autogenerated for you.  $verts should be a 3xN-PDL containing the locations of all non-endpoint
vertices in the fluxon, or undef to connect directly from the start to the end.

$fc0 should be a source flux concentration, and $fc1 should be a sink flux concentration.  If you 
get it wrong the code complains.

=cut

sub new_fluxon {
    my $fc0 = shift;
    my $fc1 = shift;
    my $flux = shift;
    my $label = shift;
    my $verts = shift;

    my $w = $fc0->{world};
    print "Concentration::new_fluxon: on entry world refct is $w->{refct}\n" if($w->{verbosity});

    if($fc0->{lines} && $fc0->{lines}->{fc_start}->{label} != $fc0->{label}) {
	barf("Flux::Concentration::new_fluxon: first argument (FC $fc0->{label}) should be a source, but isn't.\n");
    }

    print "Concentration::new_fluxon: after first test, world refct is $w->{refct}\n" if($w->{verbosity});

    if($fc1->{lines} && $fc1->{lines}->{fc_end}->{label} != $fc1->{label}) {
	barf("Flux::Concentration::new_fluxon: second arg (FC $fc1->{label}) should be a sink, but isn't.\n");
    }

    print "Concentration::new_fluxon: after second test, world refct is $w->{refct}\n" if($w->{verbosity});

    $flux = 1.0 unless(defined $flux);
    
    ## Actual constructor is in Flux::Fluxon...
    
    print "Concentration::new_fluxon: world refct is $w->{refct}\n" if($w->{verbosity});
    my $fl = Flux::Fluxon::new($w, $fc0, $fc1, $flux, $label, $verts);
    print "Concentration::new_fluxon: world refct is $w->{refct}\n" if($w->{verbosity});
    return $fl;
}

=head2 delete
 
=for usage
    
    $fc->delete;

=for ref

Deletes a flux concentration and all fluxons attached to it.  See also 
cancel() and open(), below, which are other ways to get rid of unwanted 
flux concentrations.

=cut

## Implemeneted in Concentration.xs


sub abdicate {
    my $me = shift;
    my $dest = shift;
    my $w = $me->{world};

    die "Flux::Concentration::abdicate needs a flux concentration source" unless(UNIVERSAL::isa($me,"Flux::Concentration"));
    die "Flux::Concentration::abdicate needs a flux concentration destination" unless(UNIVERSAL::isa($dest,"Flux::Concentration"));

    die "Flux::Concentration::abdicate - FC $me->{label} can't abdicate to itself!" if($me->{label} == $dest->{label});

    die "Flux::Concentration::abdicate - destination FC must have same sign as source" if($me->{flux} * $dest->{flux} <= 0);

    for my $fl($me->fluxons) {
	$fl->reattach( $dest );
    }

    $me->delete;
}

=head2 open

=for usage

    $fc->open

=for ref

Deletes a flux concentration, re-attaching all its fluxons to the open 
flux concentration.  The fluxon geometry isn't changed -- only the 
association at the endpoint.  If you have implemented open boundary
conditions, then the fluxons will "snap" to the open sphere on the next
update_neighbors call.

This is a convenience call to abdicate(), which does the same thing, only
to an arbitrary flux concentration.

=cut

sub open {
    my $me = shift;
    my $w = $me->{world};
    
    if($me->{flux} > 0) {
	$me->abdicate($w->{fc_ob});
    } elsif($me->{flux} < 0) {
	$me->abdicate($w->{fc_oe});
    } else {
	die "Flux::Concentration::open - confused about the sign of FC $me->{label}: flux is 0";
    }
}


=head2 cancel

=for usage

    $fc0->cancel($fc1);

=for ref

$fc0 should be a source flux concentration, $fc1 should be a sink.
The two concentrations are canceled in the most straightforward way
possible: connecting fluxons are deleted one by one until none are left
in the lesser of the two concentrations, whereupon the lesser concentration
is deleted.  If both concentrations have the same number of fluxons then 
both are deleted.  

Any fluxons that don't connect straight from one flux concentration to the
other are reconnected so that they do.  Those reconnections happen in tree
storage order (which is more or less random).

If all goes well, C<cancel> returns 0; otherwise it prints an error message
and throws an exception.

Cancellation is implemented in the C library, in C<fc_cancel()> in the model.c
source file.  This is just an XS hook to that function.

=cut

### implemented in Concentration.xs.



sub DESTROY {
    Flux::destroy_sv( $_[0] );
}

######################################################################
# TIED INTERFACE
# Mostly relies on the general utility functions in Flux....

# TIEHASH not used much - the C side uses FLUX->sv_from_ptr to do the tying.
sub TIEHASH {
    my $class = shift;
    my $me = shift;
    return bless($me,$class);
}

=pod

=begin comment

sub EXISTS {
    my ($me, $field)=@_;
    return ($FLUX::codes->{concentration}->{$field});
}

=end comment

=cut

sub FETCH {
    my($me, $field)=@_;
    my $code = $Flux::codes->{concentration}->{$field};
 
    return undef unless defined($code);
    
    Flux::r_val( $me, $Flux::typecodes->{concentration}, @$code[0..1] );
}

sub EXISTS {
    my($me,$field) = @_;
    return (defined FETCH($me,$field));
}


sub STORE {
    my($me, $field,$val) = @_;
    my $code = $Flux::codes->{concentration}->{$field};
    return undef unless defined($code);
    Flux::w_val( $me, $Flux::typecodes->{concentration}, @$code[0..1], $val );
}

sub DELETE {
    print STDERR "Warning: can't delete fields from a tied CONCENTRATION hash\n";
    return undef;
}

sub CLEAR {
    print STDERR "Warning: can't clear a tied CONCENTRATION hash\n";
    return undef;
}

sub FIRSTKEY {
    return "world";
}

sub NEXTKEY {
    my ($class,$prev) = @_;
    return $Flux::ordering->{concentration}->{$prev};
    
}

sub SCALAR {
    _stringify(@_);
}


1;
