=head1 NAME

Flux::Fluxon - discretized field line object

=head1 SYNOPSIS

  use PDL;
  use Flux;

  $world = new Flux::World;
  $fluxon = $world->fluxon(19);
  print $fluxon;

=head1 DESCRIPTION

Flux::Fluxon objects are the perl representation of fluxons within the
MHD simulator.  They are represented as tied hashes, to keep the interface
as flexible as possible.

VERSION

This file is part of the FLUX 2.0 release (31-Oct-2007).

=head1 METHODS

=cut

BEGIN {
package Flux::Fluxon;
use PDL;

require Exporter;
require DynaLoader;
@ISA = qw( Exporter DynaLoader Flux);
@EXPORT = qw(  ) ;

bootstrap Flux::Fluxon;
}

package Flux::Fluxon;
use overload '""' => \&stringify;


=pod

=head2 new

=for usage

    $fl = Flux::Fluxon->new($world, $fc0, $fc1, $flux, $label, $verts);
    $fl = Flux::Fluxon::new($world, $fc0, $fc1, $flux, $label, $verts);

=for ref

Generates a new fluxon connecting fc0 to fc1. with $flux units of
flux, label $label (or an autogenerated label if $label is undef or 0),
and intermediate vertices $verts (specified as a 3xN PDL).

You can omit $label and/or $verts.

=cut

sub new {
    if( (!ref($_[0])) ) {
	shift;
    }
    my ($world, $fc0, $fc1, $flux, $label, $verts) = @_;

    barf("Flux::Fluxon::new - Usage: $world, $fc0, $fc1, $flux, [$label, [$verts]]") 
	unless ( 
		 ( ref $world eq 'Flux::World' ) and
		 ( ref $fc0 eq 'Flux::Concentration' ) and
		 ( ref $fc1 eq 'Flux::Concentration' )
		 );
    
    $flux = 1.0 unless($flux);
    $label = 0 unless($label);

    if(defined $verts) {
	unless(
	       ref $verts eq 'PDL' and
	       $verts->dim(0) == 3
	       ) {
	    print "Flux::Fluxon::new - vertices must be a 3xN PDL\n" ;
	    die;
	}
    }

    return _new($world, $fc0, $fc1, $flux, $label, $verts);
}
	    

=pod

=head2 stringify

=for ref

Generate a string summary of a fluxon; overloaded with "".

=cut

# XS function doesn't get called right if not wrapped up...
sub stringify {
    my $f = shift;
    &_stringify($f);
}


=pod

=head2 vertex

=for usage

  $vertex = $fluxon->vertex(2);

=for ref

Retrieve the nth vertex from a particular fluxon (n begins at 0)

=cut

# Implemented in Fluxon.xs



=pod

=head2 vertices

=for usage
  
  @vertices = $fluxon->vertices();

=for ref

Retrieve all the vertices in a fluxon, as a perl list.

=cut

sub vertices { 
  my $me = shift;
  my $ct = $me->{v_ct};
  return map { vertex($me,$_) } 0..$ct-1;
}


=pod

=head2 polyline

=for usage

  $polyline = $fluxon->polyline;

=for ref

Return all the vertex locations in a fluxon, as a 3xn PDL.

(mainly useful for visualizations).  the 0th dim is, of course, (x,y,z).

=cut

# Implemented in Fluxon.xs

=pod

=head2 bfield

=for usage
  
  $bfield = $fluxon->bfield;

=for ref

Return the B vector at each vertex location in the simulation.

=cut

# Implemented in Fluxon.xs

=pod

=head2 dump_vecs

=for usage

  $stuff = $fluxon->dump_vecs;

=for ref

Returns a xN PDL containing, in each row:

=over 3

=item cols  0- 2: vertex location

=item cols  3- 5: B field vector

=item cols  6- 8: following segment partial force

=item cols  9-11: vertex partial force
    
=item col   12:   sum-of-magnitudes for the segment force components

=item col   13:   sum-of-magnitudes for the vertex force components

=item col   14:   r_s  - projected neighborhood radius for segment forces

=item col   15:   r_v  - projected neighborhood radius for vertex forces

=item col   16:   r_cl - closest neighbor approach projected radius

=back

=cut

# Implemented in Fluxon.xs

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
    bless($me,$class);
    return $me;
}

sub EXISTS {
    my ($me, $field)=@_;
    return ($FLUX::codes->{fluxon}->{$field});
}

sub FETCH {
    my($me, $field)=@_;
    my $code = $Flux::codes->{fluxon}->{$field};

    return undef unless defined($code);
    Flux::r_val( $me, $Flux::typecodes->{fluxon}, @$code[0..1] );
}

sub STORE {
    my($me, $field,$val) = @_;
    my $code = $Flux::codes->{fluxon}->{$field};
    return undef unless defined($code);
    Flux::w_val( $me, $Flux::typecodes->{fluxon}, @$code[0..1], $val );
}

sub DELETE {
    print STDERR "Warning: can't delete fields from a tied FLUXON hash\n";
    return undef;
}

sub CLEAR {
    print STDERR "Warning: can't clear a tied FLUXON hash\n";
    return undef;
}

sub FIRSTKEY {
    return "flux";
}

sub NEXTKEY {
    my ($class,$prev) = @_;
    return $Flux::ordering->{fluxon}->{$prev};
    
}

sub SCALAR {
    _stringify(@_);
}


1;
