/**********************************************************************
 * io.h -- I/O routine headers for FLEM
 *
 * Craig DeForest, 30-Sep-2000
 */

#ifndef FLEM_IO
#define FLEM_IO 1

#include "data.h"
#include <stdio.h>

#include <unistd.h>
#include <string.h> 
#include <sys/types.h>  
#include <sys/stat.h>
#include <sys/wait.h>  
#include <signal.h>
#include <stdio.h>

typedef struct FOOTPOINT_SPEC {
  long label;
  NUM x[3];
  NUM flux;
} FOOTPOINT_SPEC;

char *next_line(FILE *file);  /* Read line and skip comments */

/* Parse and act on a single non-comment line from a footpoint file */
int footpoint_action(WORLD *a, char *s);

/* Output routines */

/* Generic tree output to any file */
void fprint_tree(FILE *f, void *t, int lb, int lk, int idt, void ((*prntr)()));
void fprint_node(FILE *f, void *foo, int indent, int lab_o, int lk_o);

/* Generic tree output to stdout (hooks to above) */
void print_tree(void *t, int lab_o, int lk_o, int indent, void ((*printer)()));
void print_node(void *foo, int indent, int lab_o, int lk_o);

/* Fieldline output functions for print_tree */
void fdump_fluxon(FILE *f, FLUXON *foo, int indent);
void fprint_all_fluxon_node(FILE *f, FLUXON *foo, int indent);
void fprint_all_fluxon_tree(FILE *f, FLUXON *foo);
void print_all_fluxon_tree(FLUXON *foo);

/* Line output functions for state files */
void fprint_fc_line(FILE *f, void *foo, int indnt, int lab_o, int ln_o);
void fprint_fls_by_fc(FILE *f, void *foo, int indnt, int lab_o, int ln_o);
void fprint_fl_vertices(FILE *f, void *foo, int indnt, int lab_o, int ln_o);

/* Generic dumblist output */
void print_dumblist(DUMBLIST *foo, void ((*item_printer)()));

/* Output a whole world to a file */
int print_world(WORLD *a, char*header);
int fprint_world(FILE *file, WORLD *world, char *header);

/* Read a whole world from a file */
WORLD *read_world(FILE *file, WORLD *a);

/**********************************************************************
 **********************************************************************
 * 2-D Graphics output routines 
 */

int gl_2d_start(char *fname, float l, float r, float b, float t);
char *gl_2d_finish(float display_time, int display_mode);

void gl_2d_point(float x, float y, float radius, float colors[3]); 
void gl_2d_line (float x0, float y0, float x1, float y1, float colors[3]); 

void gl_2d_scr_poly(DUMBLIST *horde, float colors[3]);
void gl_2d_scr_list(DUMBLIST *horde,float colors[3]);

#endif /* overall file include */


