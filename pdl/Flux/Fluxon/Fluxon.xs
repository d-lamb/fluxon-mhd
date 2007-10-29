/* Fluxon.xs - glue code for the Flux::Fluxon object
 * in perl.
 *
 * This file is part of FLUX, the Field Line Universal relaXer.
 * Copyright (c) 2004 Craig DeForest.  You may distribute this
 * file under the terms of the Gnu Public License (GPL), version 2.
 * You should have received a copy of the GPL with this file.
 * If not, you may retrieve it from "http://www.gnu.org".
 *
 * Codes covered here:
 *  PERL INTERFACE     FLUX SUBROUTINE / FUNCTION
 *
 *  _stringify          <NA>
 *  vertex		<NA> - returns the corresponding vertex counting from start to finish.
 *  polyline            returns the locations of all the vertices in the fluxon as a 3xN PDL
 *  bfield              returns locations and B-field values of all vertices as a 6xN PDL
 *  dump_vecs           dumps a 17xN PDL containing a bunch of stuff (see Fluxon.pm).
 * 
 * This is version 1.1 of Fluxon.xs - part of the FLUX 1.1 release.
 */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"


/* Includes for libflux.a - don't bother with geomview stuff */
#include <flux/data.h>
#include <flux/geometry.h>
#include <flux/io.h>
#include <flux/model.h>
#include <flux/physics.h>
#include <flux/fluxperl.h>

#include <stdio.h>

#include "pdl.h"
#include "pdlcore.h"


static FluxCore* FLUX; /* FLUX core functions (run-time linking) */
static SV *FluxCoreSV;

static Core* PDL;  /* PDL core functions (run-time linking) */
static SV* CoreSV; /* gets perl var holding the core structures */

MODULE = Flux::Fluxon      PACKAGE = Flux::Fluxon

char *
_stringify(flx)
 SV *flx
PREINIT:
 FLUXON *f;
 char str[BUFSIZ];
/**********************************************************************
 * _stringify - generate a summary string about a fluxon. 
 */
CODE: 
  f = SvFluxon(flx,"Flux::Fluxon::_stringify");
  sprintf(str,"Fluxon %5.5d: start-fc %d, end-fc %d   %d vertices\n",f->label,f->fc0->label,f->fc1->label,f->v_ct);
  RETVAL = str;
OUTPUT:
  RETVAL

SV *
vertex(flx,vno)
 SV *flx
 IV vno
PREINIT:
 FLUXON *f;
 VERTEX *v;
 SV *sv;
 long i;
/**********************************************************************
 * vertex - given a vertex index location, return a Flux::Vertex object
 * pointing to it.
 */
CODE:
  f = SvFluxon(flx,"Flux::Fluxon::vertex");
  v = (VERTEX *)0;
  if(vno >= 0) 
    for(i=0, v=f->start; i<vno && v; i++, v=v->next)
      ;
  if(v) {
	/* What a mess!  Just calls the vertex constructor... */
      I32 foo;

      ENTER;
      SAVETMPS;

      PUSHMARK(SP);
      XPUSHs(sv_2mortal(newSVpv("Flux::Vertex",0)));
      XPUSHs(sv_2mortal(newSViv((IV)v)));
      PUTBACK;
      foo = call_pv("Flux::Vertex::new_from_ptr",G_SCALAR);
      SPAGAIN;

      if(foo==1) 
	RETVAL = POPs;
      else 
	croak("Big trouble - Vertex::new_from_ptr gave bad return value on stack");

      SvREFCNT_inc(RETVAL);

      PUTBACK;
      FREETMPS;
      LEAVE;

  } else {
      RETVAL = &PL_sv_undef;
  }
OUTPUT:
  RETVAL

SV *
polyline(flx)
 SV *flx
PREINIT:
 FLUXON *f;
 VERTEX *v;
 PDL_Double *d;
 pdl *p;
 SV *psv;
 int i;
 PDL_Long dims[2];
/**********************************************************************
 * polyline - return a 3xn PDL containing the coordinates of each 
 * VERTEX in the fluxon.  Useful for rendering.
 */
CODE:
 f = SvFluxon(flx,"Flux::Fluxon::polyline");

 /* Create the PDL and allocate its data */
 dims[0] = 3;
 dims[1] = f->v_ct;
 p = PDL->create(PDL_PERM);
 PDL->setdims(p,dims,2);
 p->datatype = PDL_D;
 PDL->allocdata(p);
 PDL->make_physical(p);
 d = p->data;

 /* Loop along the vertices, adding coordinates as we go */
 for(i=0, v=f->start; 
     i<f->v_ct && v;
     v=v->next, i++) {
  *(d++) = v->x[0];
  *(d++) = v->x[1];
  *(d++) = v->x[2];
 }
 RETVAL = NEWSV(546,0); /* 546 is arbitrary tag */
 PDL->SetSV_PDL(RETVAL, p);
OUTPUT:
 RETVAL

SV *
bfield(flx)
 SV *flx
PREINIT:
 FLUXON *f;
 VERTEX *v;
 PDL_Double *d;
 pdl *p;
 SV *psv;
 int i;
 PDL_Long dims[2];
/**********************************************************************
 * bfield - return a 6xN PDL containing the coordinates of each VERTEX
 * in the fluxon, together with the B-field components at that
 * location.
 */
CODE:
 f = SvFluxon(flx,"Flux::Fluxon::bfield");
 /* Create the PDL and allocate its data */
 dims[0] = 6;
 dims[1] = f->v_ct;
 p = PDL->create(PDL_PERM);
 PDL->setdims(p,dims,2);
 p->datatype = PDL_D;
 PDL->allocdata(p);
 PDL->make_physical(p);
 d = p->data;

 /* Loop along the vertices, adding coordinates as we go */
 for(i=0, v=f->start; 
     i<f->v_ct && v;
     v=v->next, i++) {
  *(d++) = v->x[0];
  *(d++) = v->x[1];
  *(d++) = v->x[2];
  *(d++) = v->b_vec[0];
  *(d++) = v->b_vec[1];
  *(d++) = v->b_vec[2];
 }
 RETVAL = NEWSV(547,0); /* 546 is arbitrary tag */
 PDL->SetSV_PDL(RETVAL, p);
OUTPUT:
 RETVAL


SV *
dump_vecs(flx)
 SV *flx
PREINIT:
 FLUXON *f;
 VERTEX *v;
 PDL_Double *d;
 pdl *p;
 SV *psv;
 int i;
 PDL_Long dims[2];
/**********************************************************************
 * dump_vecs - return a 17xN PDL containing the coordinates of each VERTEX
 * in the fluxon, together with the B-field components at that
 * location and forces.
 */
CODE:
 f = SvFluxon(flx,"Flux::Fluxon::dump_vecs");
 /* Create the PDL and allocate its data */
 dims[0] = 17;
 dims[1] = f->v_ct;
 p = PDL->create(PDL_PERM);
 PDL->setdims(p,dims,2);
 p->datatype = PDL_D;
 PDL->allocdata(p);
 PDL->make_physical(p);
 d = p->data;

 /* Loop along the vertices, adding coordinates as we go */
 for(i=0, v=f->start; 
     i<f->v_ct && v;
     v=v->next, i++) {
  *(d++) = v->x[0];
  *(d++) = v->x[1];
  *(d++) = v->x[2];
  *(d++) = v->b_vec[0];
  *(d++) = v->b_vec[1];
  *(d++) = v->b_vec[2];
  *(d++) = v->f_s[0];
  *(d++) = v->f_s[1];
  *(d++) = v->f_s[2];
  *(d++) = v->f_v[0];
  *(d++) = v->f_v[1];
  *(d++) = v->f_v[2];
  *(d++) = v->f_s_tot;
  *(d++) = v->f_v_tot;
  *(d++) = v->r_s;
  *(d++) = v->r_v;
  *(d++) = v->r_cl;
 }
 RETVAL = NEWSV(547,0); /* 546 is arbitrary tag */
 PDL->SetSV_PDL(RETVAL, p);
OUTPUT:
 RETVAL



SV *
_new(wsv, fc0sv, fc1sv, flux, labelsv, vertssv)
 SV *wsv
 SV *fc0sv
 SV *fc1sv
 NV flux
 SV *labelsv
 SV *vertssv
PREINIT:
 FLUXON *f;
 VERTEX *v;
 WORLD *w;
 FLUX_CONCENTRATION *fc0;
 FLUX_CONCENTRATION *fc1;
 pdl *verts;
 PDL_Double *data;
 long label;
 /******************************
  * _new - generates a new fluxon.  For more options use the 
  * standard constructor Flux::Fluxon::new (in Fluxon.pm).
  * Two vertices are automagically created at the endpoints,
  * whether you specify intermediate vertices or no.
  * 
  * Returns a perl structure pointing to the new fluxon.
  */
CODE:
  w   = SvWorld(wsv,  "Flux::Fluxon::_new - world");
  fc0 = SvConc (fc0sv,"Flux::Fluxon::_new - fc0");
  fc1 = SvConc (fc1sv,"Flux::Fluxon::_new - fc1");

  if(!vertssv || vertssv == &PL_sv_undef || !(*(SvPV_nolen(vertssv)))) {
 	verts = 0;
  } else {
 	verts = PDL->SvPDLV(vertssv);

 	if(!verts) 
 		croak("Flux::Fluxon::_new - couldn't understand verts argument");
 	if(verts->ndims<1 || verts->ndims > 2) 
 		croak("Flux::Fluxon::_new - 3-PDL or 3xn-PDL required for verts argument");
 	if(verts->dims[0] != 3) 
 		croak("Flux::Fluxon::_new - 0th dim of verts argument must have size 3");
 	if(verts->ndims==1) {
 		verts->ndims=2;
 		verts->dims[1]=1;
  		verts->dimincs[1]=3*verts->dimincs[0];
 	}
 	PDL->converttype(&verts, PDL_D, 1);
         PDL->make_physical(verts);
 }

 label = SvIV(labelsv);
 f = FLUX->new_fluxon(1.0, fc0, fc1, label, 0);

 fc0->lines  = FLUX->tree_binsert(fc0->lines, f, fl_lab_of, fl_start_ln_of);
 fc1->lines  = FLUX->tree_binsert(fc1->lines, f, fl_lab_of, fl_end_ln_of);
 w->lines    = FLUX->tree_binsert(w->lines,   f, fl_lab_of, fl_all_ln_of);
 f->start = FLUX->new_vertex( -(f->label*2),   fc0->x[0], fc0->x[1], fc0->x[2], f );
 f->end   = FLUX->new_vertex( -(f->label*2)+1, fc1->x[0], fc1->x[1], fc1->x[2], f );
 f->start->next = f->end;
 f->end->prev = f->start;
 f->v_ct = 2;
 if(verts) {
 	long vno;
 	VERTEX *vlast = f->start;
 	long st = verts->dimincs[0];
 
 	for(vno=0;vno<verts->dims[1];vno++) {
 		long of = verts->dimincs[1] * vno;
 		FLUX->add_vertex_after(f, vlast, FLUX->new_vertex( 0,
 								   ((PDL_Double *)(verts->data))[ of           ],
 								   ((PDL_Double *)(verts->data))[ of + st      ],
 								   ((PDL_Double *)(verts->data))[ of + st + st ],
 								   f
 								 )
 					);
		vlast = vlast->next;
 	}
 }
 {
  I32 foo;
  ENTER;
  SAVETMPS;
  PUSHMARK(SP);
  XPUSHs(sv_2mortal(newSVpv("Flux::Fluxon",0)));
  XPUSHs(sv_2mortal(newSViv((IV)(f))));
  PUTBACK;
  foo = call_pv("Flux::Fluxon::new_from_ptr",G_SCALAR);
  SPAGAIN;
  if(foo==1) 
 	RETVAL=POPs;
  else
 	croak("Big trouble in Flux::Fluxon::_new!");
  SvREFCNT_inc(RETVAL);
  PUTBACK;
  FREETMPS;
  LEAVE;
 }
OUTPUT:
	 RETVAL		
  

void 
_inc_world_refct(svfl)
SV *svfl
PREINIT:
 FLUXON *f;
CODE:
 f = SvFluxon(svfl, "Flux::Fluxon::_inc_world_refct");
 f->fc0->world->refct++;  
 if(f->fc0->world->verbosity) 
	printf("Fluxon: world refct++ (now %d)\n",f->fc0->world->refct);


void
_dec_refct_destroy_world(svfl)
SV *svfl
PREINIT:
 FLUXON *f;
CODE:
 f = SvFluxon(svfl, "Flux::Fluxon::_dec_refct_destroy_world");
 f->fc0->world->refct--;
 if(f->fc0->world->verbosity)
	printf("Flux::Fluxon::_dec_refct_destroy_world - world refcount is now %d\n",f->fc0->world->refct);
 if(f->fc0->world->refct <= 0) 
	free_world(f->fc0->world);

BOOT:
/**********************************************************************
 **********************************************************************
 **** bootstrap code -- load-time dynamic linking to pre-loaded PDL
 **** modules and core functions.   **/
 perl_require_pv("PDL::Core");
 CoreSV = perl_get_sv("PDL::SHARE",FALSE);
 if(CoreSV==NULL)     Perl_croak(aTHX_ "Can't load PDL::Core module (required by Flux::Fluxon)");

 PDL = INT2PTR(Core*, SvIV( CoreSV ));  /* Core* value */
 if (PDL->Version != PDL_CORE_VERSION)
    Perl_croak(aTHX_ "Flux::Fluxon needs to be recompiled against the newly installed PDL");


 perl_require_pv("Flux::Core");
 FluxCoreSV = perl_get_sv("Flux::Core::FLUX",FALSE);
 if(FluxCoreSV == NULL)      Perl_croak(aTHX_ "Can't load Flux::Core module (required b Flux)");
 
 FLUX = INT2PTR(FluxCore*, SvIV(FluxCoreSV));
 if(FLUX->CoreVersion != FLUX_CORE_VERSION) {
	Perl_croak(aTHX_ "Flux needs to be recompiled against the newly installed FLUX libraries");
}

 