/*
 * physics.c
 * 
 * Contains force laws and other directly physics-related 
 * calculations.  The 'force laws' manipulate vertex-local 
 * quantities; you may include additional local simulation steps
 * by adding additional routines that carry them out. 
 *
 * The force laws actually calculate force per unit length along
 * the fluxon; the relaxation step should multiply the f/l times
 * the length of each segment.
 * 
 * Quasi-local simulation steps such as reconnection that require
 * physical quantities in the neighbors will require a second
 * pass through the data (to update all local calculations such as
 * magnetic field), but can also be implemented using the same 
 * force-law structure.
 *
 *
 * This file is part of FLUX, the Field Line Universal relaXer.
 * Copyright (c) Southwest Research Institute, 2004
 * 
 * You may modify and/or distribute this software under the temrs of
 * the Gnu Public License, version 2.  You should have received a copy
 * of the license with this software, in the file COPYING to be found
 * in the top level directory of the distribution.  You may obtain
 * additional copies of the licesnse via http://www.gnu.org or by
 * writing to the Free Software Foundation, 59 Temple Place - Suite
 * 330, Boston, MA 02111-1307 USA.
 *
 * The software comes with NO WARRANTY.
 * 
 * You may direct questions, kudos, gripes, and/or patches to the
 * author, Craig DeForest, at "deforest@boulder.swri.edu".
 * 
 */

#include <math.h>
#include "physics.h"
#include "geometry.h"

/* global force name table */
struct FLUX_FORCES FLUX_FORCES[] = {
  {"b_eqa","2004 angular equipartion B calculation (B required at start of list)",b_eqa},
  {"f_curvature","(OLD) simple curvature force over B (DEPRECATED)",f_curvature},
  {"f_pressure_equi","(OLD) 2001 pressure law over B (DEPRECATED)",f_pressure_equi},
  {"f_curv_hm","Curvature force law (harmonic mean curvature)",f_curv_hm},
  {"f_curv_m","Curvature force law (mean curvature)",f_curv_m},
  {"f_p_eqa_radial","Angular equipartition pressure, radial forces",f_p_eqa_radial},
  {"f_vertex","Vertex distribution pseudo-force",f_vertex},
  {0,0,0}
};


/* fluxon physics routines get called like this:
 *    force = routine( VERTEX *v );
 * where, on return, force is 0 (error) or a pointer to a static area 
 * containing the force 3-vector.
 * 
 * Later, there will be other routines for more complex models
 * handled along the fluxon. 
 */

/**********************************************************************
 **********************************************************************
 * The older forces used for field line manipulation had |B| divided out of
 * them, to simplify their calculation.   They are kept here, warts and
 * all, for reference.  But they are deprecated.  So instead of 
 * f_curvature and f_pressure_equi, use f_curv and f_p_eqa
 *
 *

/**********************************************************************
 * f_curvature
 * Curvature `force':   (B^ . \del) B^ 
 *      = b^_x ( db^_x / dx ) + b^_y ( db^_y / dy ) + b^_z ( db^_z / dz )
 * 
 * but b^ is just l^.
 *
 * The curvature force is a vertex-centered force.  There's actually 
 * a little too much information:  not only do we get an angle and a 
 * length, we get an extra length too (there are *two* legs out of the
 * segment, not just one, and they have differing lengths).  I use 
 * the harmonic mean because that's dominated by the smaller of the
 * two lengths rather than by the larger.
 * 
 */
void f_curvature(VERTEX *V, HULL_VERTEX *verts) {
  NUM recip_l1, recip_l2, recip_len, len;
  NUM b1hat[3];
  NUM b2hat[3];
  NUM curve[3];
  NUM force[3];


  if(!V->next || !V->prev) 
    return;

  diff_3d(b2hat,V->next->x,V->x);
  scale_3d(b2hat,b2hat, (recip_l2 = 1.0 / norm_3d(b2hat)));

  diff_3d(b1hat,V->x,V->prev->x);
  scale_3d(b1hat,b1hat, (recip_l1 = 1.0 /norm_3d(b1hat)));

  recip_len =  ( recip_l1 + recip_l2 ) / 2;
  
  diff_3d(curve,b2hat,b1hat);
  scale_3d(curve,curve, recip_len);
  sum_3d(V->f_v,V->f_v,curve);
  V->f_v_tot += norm_3d(curve);


}
  
/**********************************************************************
 * f_pressure_equi
 * Magnetic pressure `force' : - \del_perp(|B|) / |B|
 *
 * Magnetic pressure force, using the equipartition method 
 * which distributes a given fluxon's flux equally by delta-phi.
 * This method distributes current throughout each fluxon's cross-section.
 * 
 * This uses the Kankelborg/DeForest discretization:
 * del_perp(|B|) / |B| ~ \sum_i ( n^_i delta\phi_i / (pi r_i) )
 * where n^_i is the vector from the current point to the ith neighbor,
 * delta\phi is the angular extent of the ith line segment in the 
 * Voronoi hull, and r_i is the radius to the closest approach of the
 * ith line segment (see DeForest notebook V, pp. 69-70)
 */
void f_pressure_equi(VERTEX *V, HULL_VERTEX *verts) {
  NUM force[3]; /* force accumulator */
  static HULL_VERTEX *point_cache = 0;  /* Workspace grows and sticks */
  static int pc_size = 0;               /* Workspace size */
  int i;
  NUM pmatrix[9];

  force[0] = force[1] = force[2] = 0;

  if(!V->next) 
    return;

  /* Get the perpendicular-plane projection matrix */
  /* (This is wasteful -- it's already generated in geometry.c.  Is
     there an easy way to send it back?) */
  projmatrix(pmatrix, V->x, V->next->x);

  /*printf("f_pressure_equi:  V%4d,  n=%d\n",V->label, V->neighbors.n);*/

  for(i=0;i<V->neighbors.n;i++) {
    NUM f_i[3];
    NUM phi_l, phi_r, deltaphi, f;
    HULL_VERTEX *left, *right;
    VERTEX *N = (VERTEX *)V->neighbors.stuff[i];

    left = &verts[i];
    right = (i==0) ? &verts[V->neighbors.n - 1] : &verts[i-1];
    
    /* Calculate delta-phi by calculating the maximal phis and subtracting. 
     * In the open case, the endpoint phi is the angle at which the 
     * perpendicular bisector to r_i goes away.  In the closed case, 
     * it's the angle to the vertex.
     */

    deltaphi = (left->a_l - right->a_r);
    TRIM_ANGLE(deltaphi);

    if(deltaphi < -EPSILON)
      fprintf(stderr,"Assertion failed!  deltaphi <0 in f_pressure_equi (%18.12g deg)\n",deltaphi*180/M_PI);
    
    /*    fprintf(stderr," VERTEX #%d, i=%d: deltaphi=%g\tr=%g\n",N->label,i,deltaphi,N->r);*/


    f = deltaphi / M_PI / N->r;

    N->scr[2] = 0; /* Make sure we're operating in the perp. plane */
    
    vec_mmult_3d(f_i,pmatrix,N->scr);       /* Put back into 3-D */
    /*    printf("  in plane: (%g,%g,%g); projects back to (%g,%g,%g)\n",N->scr[0],N->scr[1],N->scr[2],f_i[0],f_i[1],f_i[2]); */

    {
      /* Scale to the proper force */
      NUM a = norm_3d(f_i);
      if(a==0) {
	fprintf(stderr,"Assertion failed in physics.c!  f_i has 0 norm!\n");
	exit(99);
      }
      scale_3d(f_i,f_i, - f / a);  /* Scale to the calc. force */
    }

    sum_3d(force,force,f_i);
    V->f_s_tot += fabs(f);
  }

  sum_3d(V->f_s,V->f_s,force);

  /*printf("f_pressure_equi -- force is (%8g,%8g,%8g), total is (%8g,%8g,%8g)\n\n",force[0],force[1],force[2],V->f_s[0],V->f_s[1],V->f_s[2]);*/

  {
    NUM r;
    int ii;
    /* Accumulate closest neighbor */
    /* This code will need updating if fluxons get variable flux! */
    r = -1;
    for(ii=0;ii<V->neighbors.n;ii++) {
      NUM a;
      a = ((VERTEX *)(V->neighbors.stuff[ii]))->r;
      if(r<0 || a<r)
	r = a;
    }
    V->r =  r / 2;  /* If all fluxons have the same amount of flux, then the min.
		       radius is always half of the closest neighbor's distance. */
  }
  
  return;
}

/**********************************************************************
 * fluxon_vertex_force
 * Pseudoforce that moves vertices along field lines.  Used to keep them 
 * nicely evened out along the lines and to attract them to 
 * curvature.
 * 
 * Strictly speaking, this is two forces:  a vertex repulsive force
 * and another force that attracts vertices toward curvature.  But
 * the two should always be used together, so they're included together.
 * 
 */
void f_vertex(VERTEX *V, HULL_VERTEX *verts) {
  NUM force[3];
  NUM d1[3], d2[3];
  NUM d1nr,d2nr,fn,d1n,d2n;

  /* Exclude endpoints */
  if(!V->next || !V->prev)
    return;


  /* Repulsive force from nearest neighbors.  The force drops as 
   *  1/r.
   */
  diff_3d(d1,V->x,V->prev->x);
  scale_3d(d1, d1, (d1nr = 1.0 / norm_3d(d1))); /* assignment */

  diff_3d(d2,V->next->x, V->x);
  scale_3d(d2, d2, (d2nr = 1.0 / norm_3d(d2)));  /* assignment */
  
  fn = (d1nr - d2nr);
  V->f_v_tot += fabs(fn);

  /* Proximity-attractive force.  This attracts vertices toward places
   * where field lines are interacting. 
   */
  if(V->prev && V->next) {
    NUM r_clp, r_cln;

    r_clp = 1.0 / V->prev->r_cl;
    r_cln = 1.0 / V->r_cl;

    V->f_v_tot += fabs(0.5 * (r_cln - r_clp));
    fn += 0.5 * (r_cln - r_clp);
  }
    

  /* Generate a vector along the field line and scale it to the 
   * calculated force.  
   *
   * Finally, stick the force where it belongs in the VERTEX's force vector.
   */

  sum_3d(force,d1, d2);
  scale_3d(force, force, 0.5 * fn / norm_3d(force));

  /*printf("f_vertex: V%4d, force=(%g,%g,%g)\n",V->label,force[0],force[1],force[2]);*/

  sum_3d(V->f_v, V->f_v, force);

  return;
}
 
 

/**********************************************************************
 **********************************************************************
 *****
 ***** newer forces are NOT divided by B.
 * 
 * Note that you need a B calculation _in_advance_ of any of the other
 * force or geometrical calculations.  The B routines must calculate
 * not only the magnetic field but also the projected distances and 
 * angles to the relevant other points.
 *
 */

/**********************************************************************
 * b_eqa
 *  
 * Not truly a force, but required for the others.  Calculates 
 * B and |B| and inserts them into the VERTEX.  b_eqa uses the 
 * angular equiparition estimate, and delivers a phi-averaged
 * magnitude.  See DeForest notebooks v. VIII, p. 70.
 *
 * As a side effect, also accumulates the smallest neighbor distance.
 *
 * The flux is taken from the fluxon itself, in preparation for 
 * future non-uniform-flux-per-fluxon simulations although now 
 * (august 2004) it's not here.
 * 
 */
void b_eqa(VERTEX *V, HULL_VERTEX *verts) {
  NUM Bmag = 0;
  static NUM vec1[3],vec2[3];
  VERTEX **nv = (VERTEX **)(V->neighbors.stuff);
  int n = V->neighbors.n;
  int i;

  for(i=0;i<n;i++) {
    HULL_VERTEX *left = &(verts[i]);
    HULL_VERTEX *right = (i==0) ? &(verts[n-1]) : &(verts[i-1]);
    VERTEX *v = nv[i];
    NUM righta, lefta;
    /* open left vertices are OK; open right vertices must be calculated 
     * from the current vertex.
     */
    righta = right->a_r - v->a;
    TRIM_ANGLE(righta);

    lefta = left->a_l - v->a;
    TRIM_ANGLE(lefta);

    if(righta > lefta) {
      printf("ASSERTION FAILED in b_eqa: left rel. angle %7.3g(%c) > right rel. angle %7.3g(%c), vertex %d (neighbor %d, %d of %d)\n",lefta*180/PI,left->open?'o':'c', righta*180/PI, right->open?'o':'c',V->label, v->label, i, n);

      {
	int j;
	for(j=0;j<n;j++) 
	  printf("\t%s corner %2d (%c): a_l=%7.3g,a_r=%7.3g (rel. %7.3g)\n",(j==i)?"==>":"   ",j,(verts[j].open?'o':'c'),verts[j].a_l*180/PI,verts[j].a_r*180/PI,verts[j].a_l*180/PI-v->a*180/PI);
      }
    }
    
    if(V->line->fc0->world->verbosity >= 4) {printf("b_eqa force: VERTEX %5d, neighbor %5d, a=%7.3g, r=%7.3g, righta = %7.3g(%c), lefta=%7.3g(%c)\n",V->label, v->label,v->a*180/PI, v->r, righta*180/PI,right->open?'o':'c',lefta*180/PI,left->open?'o':'c');
    }

    /* formula wants \frac{1}{2r_p^2}; but VERTEX r is 2r, so
     * we instead use \frac{2}{r^2}...
     */
    Bmag +=  
      ( 0.5 * ( sin( 2 * lefta ) - sin( 2 * righta ) )
	  + lefta - righta
       ) 
      / 
      (nv[i]->r * nv[i]->r) ;

  }
  
  Bmag *= V->line->flux * ( 1 / ( PI * PI ) );

  V->b_mag = Bmag;

  /********************
   * Now calculate the B direction -- it's the average direction of the
   * two unit vectors associated with the VERTEX (unless the VERTEX is
   * an endpoint in which case it's the direction of the endpoint!)
   * Since final endpoints don't have neighbors or forces (fenceposting), 
   * the no-next-guy case should never happen, but it's here for completeness.
   */
  if(V->next && V->prev) { 

    Bmag *= 0.5;  /* WARNING - Bmag no good below here */
    diff_3d(vec1,V->next->x,V->x);
    diff_3d(vec2,V->x,V->prev->x);

    if(V->line->fc0->world->verbosity >= 4) { printf("b_eqa: vec1=%7.3g,%7.3g,%7.3g; vec2=%7.3g,%7.3g,%7.3g\n",vec1[0],vec1[1],vec1[2],vec2[0],vec2[1],vec2[2]); }

    scale_3d(vec1,vec1,Bmag/norm_3d(vec1));
    scale_3d(vec2,vec2,Bmag/norm_3d(vec2));

    sum_3d(V->b_vec,vec1,vec2);


  } else if(V->next) {

    diff_3d(vec1,V->next->x,V->x);
    scale_3d(V->b_vec,vec1,Bmag/norm_3d(vec1));

  } else if(V->prev) {

    diff_3d(vec1,V->x,V->prev->x);
    scale_3d(V->b_vec,vec1,Bmag/norm_3d(vec1));

  } else {

    fprintf(stderr,"b_eqa: got an invalid VERTEX! I quit!\n");
    exit(99);

  }

  if(V->line->fc0->world->verbosity >= 3) { fprintf(stderr,"b_eqa: VERTEX %4d (fluxon %4d); magnetic field mag. is %7.3g (vec is %7.3g, %7.3g, %7.3g)\n", V->label, V->line->label, V->b_mag, V->b_vec[0],V->b_vec[1],V->b_vec[2]); }


}


/**********************************************************************
 * f_curv_hm
 * Curvature `force':   (B^ . \del) B^ 
 *      = b^_x ( db^_x / dx ) + b^_y ( db^_y / dy ) + b^_z ( db^_z / dz )
 * 
 * but b^ is just l^.
 *
 * The curvature force is a vertex-centered force.  There's actually 
 * a little too much information:  not only do we get an angle and a 
 * length, we get an extra length too (there are *two* legs out of the
 * segment, not just one, and they have differing lengths).  
 *
 * f_curv_hm uses the harmonic mean to find the curvature at the vertex,
 * which lets the smaller radius dominate the curvature.
 *
 * f_curv is multiplied by the magnetic field magnitude, unlike
 * its deprecated predecessor, f_curvature.
 * 
 */
void f_curv_hm(VERTEX *V, HULL_VERTEX *verts) {
  NUM recip_l1, recip_l2, recip_len, len;
  NUM b1hat[3];
  NUM b2hat[3];
  NUM curve[3];
  NUM force[3];


  if(!V->next || !V->prev) 
    return;

  diff_3d(b2hat,V->next->x,V->x);
  scale_3d(b2hat,b2hat, (recip_l2 = 1.0 / norm_3d(b2hat)));

  diff_3d(b1hat,V->x,V->prev->x);
  scale_3d(b1hat,b1hat, (recip_l1 = 1.0 /norm_3d(b1hat)));

  recip_len =  ( recip_l1 + recip_l2 ) / 2;
  
  diff_3d(curve,b2hat,b1hat);
  scale_3d(curve,curve, recip_len * V->b_mag);

  sum_3d(V->f_v,V->f_v,curve);

  V->f_v_tot += norm_3d(curve);

  if(V->a < 0 || V->a > (len = ( (recip_l2 > recip_l1) ? (1.0/recip_l2) : (1.0/recip_l1) ) ) );
    V->a = len;
}

/**********************************************************************
 * f_curv_m
 * Curvature `force':   (B^ . \del) B^ 
 *      = b^_x ( db^_x / dx ) + b^_y ( db^_y / dy ) + b^_z ( db^_z / dz )
 * 
 * but b^ is just l^.
 *
 * The curvature force is a vertex-centered force.  There's actually 
 * a little too much information:  not only do we get an angle and a 
 * length, we get an extra length too (there are *two* legs out of the
 * segment, not just one, and they have differing lengths).  
 *
 * f_curv_m uses the standard mean to find the curvature at the vertex;
 * this treats the curvature as spread throughout the fluxon.
 *
 * f_curv is multiplied by the magnetic field magnitude, unlike
 * its deprecated predecessor, f_curvature.
 * 
 */
void f_curv_m(VERTEX *V, HULL_VERTEX *verts) {
  NUM l1, l2, recip_len, len;
  NUM b1hat[3];
  NUM b2hat[3];
  NUM curve[3];
  NUM force[3];


  if(!V->next || !V->prev) 
    return;

  diff_3d(b2hat,V->next->x,V->x);
  scale_3d(b2hat,b2hat, 1.0 / (l2 = norm_3d(b2hat)));

  diff_3d(b1hat,V->x,V->prev->x);
  scale_3d(b1hat,b1hat, 1.0 / (l1 = norm_3d(b1hat)));

  recip_len =  2 / ( l1 + l2 );
  
  diff_3d(curve,b2hat,b1hat);
  scale_3d(curve,curve, recip_len * V->b_mag);

  sum_3d(V->f_v,V->f_v,curve);

  V->f_v_tot += norm_3d(curve);

  if(V->a < 0 || V->a > ( len = ( (l2  < l1) ? l2 : l1) ) ) /* assignment */
    V->a = len;
}

/**********************************************************************
 *
 * f_p_eqa_radial
 *
 * Magnetic pressure force, acting radially all the way around the 
 * Voronoi cell boundary (acts like springs on a corrugated boundary)
 *
 * See DeForest notebooks, Vol. VIII, pp 75-76.
 *
 */

void f_p_eqa_radial(VERTEX *V, HULL_VERTEX *verts) {
  static NUM scr2d[3],scr3d[3];
  int i,n;
  NUM sina, cosa;
  NUM pmatrix[9];
  VERTEX **nv = (VERTEX **)(V->neighbors.stuff);
  NUM fac = V->line->flux * V->line->flux / (PI*PI*PI);
  
  if(!(V->next))
    return;

  /* Get the perpendicular-plane projection matrix */
  /* (This is wasteful - it is generated in geometry.c as well. */
  /* Is there an easy way to pass it around? */
  projmatrix(pmatrix,V->x,V->next->x);
  
  scr2d[0] = scr2d[1] = scr2d[2] = 0;

  n = V->neighbors.n;
  for(i=0; i< n; i++) {
    NUM fperp;
    NUM fpar;
    NUM factor;
    HULL_VERTEX *left = &(verts[i]);
    HULL_VERTEX *right = (i!=0) ? &(verts[i-1]) : &(verts[n-1]);
    VERTEX *v = nv[i];
    NUM righta, lefta;

    righta = right->a_r - v->a;   
    TRIM_ANGLE(righta);

    lefta = left->a_l - v->a;
    TRIM_ANGLE(lefta);

    
    /* Assemble perpendicular and parallel force components */
    factor = -fac / (v->r * v->r * v->r);
    
    fperp= factor * (0.25 * (sin(2*lefta) - sin(2*righta)) 
		     + 0.5 * (lefta-righta)
		     );
    fpar = factor * ( cos(2*righta) - cos(2*lefta) );

    {
      NUM s, c;
      s = sin(v->a);
      c = cos(v->a);
      scr2d[0] += c * fperp - s * fpar;
      scr2d[1] += s * fperp +  c * fpar;
    }

    if(V->line->fc0->world->verbosity >= 4) {printf("f_p_eqa_radial: VERTEX %4d, neighbor %5d, a=%7.3g, r=%7.3g, righta=%7.3g(%c), lefta=%7.3g(%c), fperp=%7.3g, fpar=%7.3g\n",V->label,v->label,v->a*180/PI,v->r,lefta*180/PI,left->open?'o':'c',righta*180/PI,right->open?'o':'c',fperp,fpar);
    }


  } /* end of neighbor loop */
  
   vec_mmult_3d(scr3d,pmatrix,scr2d); /* Convert to 3-D */
   //  mat_vmult_3d(scr3d,pmatrix,scr2d); /* COnvert to 3-D */

  if(V->line->fc0->world->verbosity >= 3) { printf("f_p_eqa_radial: VERTEX %4d (fluxon %4d); total force is %7.3g, %7.3g, %7.3g\n", V->label, V->line->label, scr3d[0],scr3d[1],scr3d[2]); }


  sum_3d(V->f_s,V->f_s,scr3d);
  V->f_s_tot += norm_3d(scr3d);
  
  return;
}
	
