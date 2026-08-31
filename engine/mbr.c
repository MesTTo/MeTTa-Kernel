/* Purpose: merge_branch_returns/3's occurrence analysis and branch rewrite in
 *   C, a faithful port of the Prolog pass in engine/translator/runtime.pl.
 *   The pass restores last-call optimization: a branch of an if-then-else or
 *   disjunction that ends (Out = V), where V is produced inside the branch,
 *   absent from the head and used nowhere else, is rewritten to end at its
 *   producer, and the binding V = Out is made once at translate time. This
 *   file computes each variable's occurrence count and first/last traversal
 *   positions, decides the candidates, rebuilds the body SHARING every
 *   subterm it does not change, and hands the delayed bindings back as a
 *   list; the Prolog caller binds them, so the two implementations bind at
 *   the same moment. Registered into module translator as
 *   metta_c_mbr_analyze/4 by engine/translator/runtime.pl when mbr.so sits
 *   beside the engine, exactly the reader's artifact-presence pattern.
 * Assumes: Head and Body are acyclic (clause terms; the translator never
 *   builds a cyclic body); the caller treats a FAILURE as "analyze in
 *   Prolog instead", which is how the variable-table cap degrades.
 * Guarantees:
 *   - answers exactly what the Prolog pass answers: the same rewritten body
 *     up to variance and the same binding set, over the translator suite's
 *     generator fuzzer and the whole example corpus under
 *     METTA_C_MBR=differential [tested:
 *     mbr_c_differential:the_c_and_prolog_analyzers_agree_on_every_canonical_shape,
 *     mbr_c_differential:six_hundred_generated_control_spines_agree].
 *   - never binds a variable: the rewrite shares the caller's terms, and the
 *     bindings list carries the variables themselves for the caller to bind.
 * Fails when: more than MBR_MAX_VARS distinct variables appear (the Prolog
 *   pass then owns the clause), or a control node is malformed.
 * Owns resources: per-call heap scratch (the variable table and stats),
 *   freed on every exit path; no globals beyond install-time functor
 *   handles.
 */

#include <SWI-Prolog.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static functor_t F_comma2, F_semicolon2, F_arrow2, F_unify2, F_minus2;
static atom_t A_true;

#define MBR_MAX_VARS 512

typedef struct {
    term_t ref;        /* a held reference to the variable itself */
    intptr_t count;    /* body occurrences (head vars stay 0) */
    intptr_t first;    /* first body position */
    intptr_t last;     /* last body position */
    int in_head;
} var_slot;

typedef struct {
    var_slot *slots;
    size_t nslots;
    intptr_t position;
    int overflow;
} mbr_state;

/* The variable table is identity-keyed through PL_compare, which for two
 * variables is an address comparison. Linear scan: a clause rarely holds
 * more than a few dozen distinct variables, and the cap fails over to the
 * Prolog pass rather than growing without bound. */
static var_slot *
lookup_var(mbr_state *st, term_t v, int insert)
{ for ( size_t i = 0; i < st->nslots; i++ )
  { if ( PL_compare(st->slots[i].ref, v) == 0 )
      return &st->slots[i];
  }
  if ( !insert )
    return NULL;
  if ( st->nslots >= MBR_MAX_VARS )
  { st->overflow = 1;
    return NULL;
  }
  var_slot *s = &st->slots[st->nslots++];
  s->ref = PL_copy_term_ref(v);
  s->count = 0;
  s->first = -1;
  s->last = -1;
  s->in_head = 0;
  return s;
}

/* One walk shape serves marking, stats and advancing; `mode` picks what a
 * variable occurrence does. Loops on a compound's LAST argument so a long
 * list or conjunction costs recursion only as deep as its non-tail parts. */
#define WALK_MARK_HEAD 0
#define WALK_STATS     1
#define WALK_ADVANCE   2

static int
walk_term(mbr_state *st, term_t t0, int mode)
{ term_t t = PL_copy_term_ref(t0);

  for (;;)
  { if ( PL_is_variable(t) )
    { if ( mode == WALK_MARK_HEAD )
      { var_slot *s = lookup_var(st, t, 1);
        if ( st->overflow ) return FALSE;
        if ( s ) s->in_head = 1;
      } else if ( mode == WALK_STATS )
      { var_slot *s = lookup_var(st, t, 1);
        if ( st->overflow ) return FALSE;
        if ( s && !s->in_head )
        { if ( s->count == 0 ) s->first = st->position;
          s->count++;
          s->last = st->position;
        }
        st->position++;
      } else
      { st->position++;
      }
      return TRUE;
    }
    if ( PL_is_compound(t) )
    { atom_t name;
      size_t arity;
      if ( !PL_get_name_arity(t, &name, &arity) )
        return FALSE;
      term_t a = PL_new_term_ref();
      for ( size_t i = 1; i < arity; i++ )
      { _PL_get_arg(i, t, a);
        if ( !walk_term(st, a, mode) )
          return FALSE;
        if ( st->overflow ) return FALSE;
      }
      _PL_get_arg(arity, t, t);   /* loop on the tail argument */
      continue;
    }
    return TRUE;                  /* atomic: contributes nothing */
  }
}

/* Split a rebuilt conjunction from its last conjunct: everything-but-last
 * comes back in *prefix (A_true when the last conjunct stood alone). The
 * walk mirrors mbr_split/3. */
static int
split_last(term_t conj, term_t prefix, term_t last)
{ if ( PL_is_functor(conj, F_comma2) )
  { term_t a = PL_new_term_ref();
    term_t b = PL_new_term_ref();
    _PL_get_arg(1, conj, a);
    _PL_get_arg(2, conj, b);
    term_t p1 = PL_new_term_ref();
    if ( !split_last(b, p1, last) )
      return FALSE;
    if ( PL_is_atom(p1) )
    { atom_t at;
      if ( PL_get_atom(p1, &at) && at == A_true )
        return PL_put_term(prefix, a);
    }
    return PL_cons_functor(prefix, F_comma2, a, p1);
  }
  if ( !PL_put_atom(prefix, A_true) )
    return FALSE;
  return PL_put_term(last, conj);
}

typedef struct binding_cell {
    term_t v;
    term_t out;
    struct binding_cell *next;
} binding_cell;

typedef struct {
    mbr_state *st;
    binding_cell *bindings;    /* collected newest-first */
    int failed;
} rewrite_state;

static int rewrite_goal(rewrite_state *rw, term_t g, term_t out);

/* A branch: rewrite its body, then apply mbr_merge_candidate/5's exact
 * conditions against the ORIGINAL branch term and the position interval the
 * rewritten walk just covered. */
static int
rewrite_branch(rewrite_state *rw, term_t b0, term_t out)
{ intptr_t p_before = rw->st->position;
  term_t b1 = PL_new_term_ref();
  if ( !rewrite_goal(rw, b0, b1) )
    return FALSE;
  intptr_t p_after = rw->st->position;

  /* candidate: b0's last conjunct is (Out = V) with both unbound and
   * distinct, V not in the head, produced (count>1) and confined to
   * [p_before, p_after). */
  term_t prefix0 = PL_new_term_ref();
  term_t last0 = PL_new_term_ref();
  if ( !split_last(b0, prefix0, last0) )
    return FALSE;
  if ( PL_is_functor(last0, F_unify2) )
  { term_t o = PL_new_term_ref();
    term_t v = PL_new_term_ref();
    _PL_get_arg(1, last0, o);
    _PL_get_arg(2, last0, v);
    if ( PL_is_variable(o) && PL_is_variable(v) && PL_compare(o, v) != 0 )
    { var_slot *s = lookup_var(rw->st, v, 0);
      if ( s && !s->in_head && s->count > 1 &&
           s->first >= p_before && s->last < p_after )
      { term_t prefix1 = PL_new_term_ref();
        term_t last1 = PL_new_term_ref();
        if ( !split_last(b1, prefix1, last1) ||
             !PL_put_term(out, prefix1) )
          return FALSE;
        binding_cell *cell = malloc(sizeof(*cell));
        if ( !cell ) return FALSE;
        cell->v = PL_copy_term_ref(v);
        cell->out = PL_copy_term_ref(o);
        cell->next = rw->bindings;
        rw->bindings = cell;
        return TRUE;
      }
    }
  }
  return PL_put_term(out, b1);
}

/* mbr_goal/6's control grammar exactly: conjunction spine, (C->T;E),
 * (A;B), (C->T); everything else advances as a leaf, a variable goal
 * included. Conjunctions loop rather than recurse. */
static int
rewrite_goal(rewrite_state *rw, term_t g0, term_t out)
{ if ( PL_is_variable(g0) )
  { rw->st->position++;
    return PL_put_term(out, g0);
  }
  if ( PL_is_functor(g0, F_comma2) )
  { term_t a = PL_new_term_ref();
    term_t b = PL_new_term_ref();
    _PL_get_arg(1, g0, a);
    _PL_get_arg(2, g0, b);
    term_t a1 = PL_new_term_ref();
    term_t b1 = PL_new_term_ref();
    if ( !rewrite_goal(rw, a, a1) || !rewrite_goal(rw, b, b1) )
      return FALSE;
    return PL_cons_functor(out, F_comma2, a1, b1);
  }
  if ( PL_is_functor(g0, F_semicolon2) )
  { term_t l = PL_new_term_ref();
    term_t r = PL_new_term_ref();
    _PL_get_arg(1, g0, l);
    _PL_get_arg(2, g0, r);
    if ( PL_is_functor(l, F_arrow2) )
    { term_t c = PL_new_term_ref();
      term_t t = PL_new_term_ref();
      _PL_get_arg(1, l, c);
      _PL_get_arg(2, l, t);
      if ( !walk_term(rw->st, c, WALK_ADVANCE) )
        return FALSE;
      term_t t1 = PL_new_term_ref();
      term_t e1 = PL_new_term_ref();
      if ( !rewrite_branch(rw, t, t1) || !rewrite_branch(rw, r, e1) )
        return FALSE;
      term_t l1 = PL_new_term_ref();
      if ( !PL_cons_functor(l1, F_arrow2, c, t1) )
        return FALSE;
      return PL_cons_functor(out, F_semicolon2, l1, e1);
    }
    term_t l1 = PL_new_term_ref();
    term_t r1 = PL_new_term_ref();
    if ( !rewrite_branch(rw, l, l1) || !rewrite_branch(rw, r, r1) )
      return FALSE;
    return PL_cons_functor(out, F_semicolon2, l1, r1);
  }
  if ( PL_is_functor(g0, F_arrow2) )
  { term_t c = PL_new_term_ref();
    term_t t = PL_new_term_ref();
    _PL_get_arg(1, g0, c);
    _PL_get_arg(2, g0, t);
    if ( !walk_term(rw->st, c, WALK_ADVANCE) )
      return FALSE;
    term_t t1 = PL_new_term_ref();
    if ( !rewrite_branch(rw, t, t1) )
      return FALSE;
    return PL_cons_functor(out, F_arrow2, c, t1);
  }
  if ( !walk_term(rw->st, g0, WALK_ADVANCE) )
    return FALSE;
  return PL_put_term(out, g0);
}

static void
free_bindings(binding_cell *b)
{ while ( b )
  { binding_cell *next = b->next;
    free(b);
    b = next;
  }
}

/* metta_c_mbr_analyze(+Head, +Body, -NewBody, -Bindings) */
static foreign_t
mbr_analyze(term_t head, term_t body, term_t newbody, term_t bindings)
{ mbr_state st;
  st.slots = malloc(sizeof(var_slot) * MBR_MAX_VARS);
  if ( !st.slots )
    return FALSE;
  st.nslots = 0;
  st.position = 0;
  st.overflow = 0;

  int ok = walk_term(&st, head, WALK_MARK_HEAD);
  st.position = 0;
  if ( ok && !st.overflow )
    ok = walk_term(&st, body, WALK_STATS);

  rewrite_state rw;
  rw.st = &st;
  rw.bindings = NULL;
  rw.failed = 0;

  term_t rebuilt = PL_new_term_ref();
  if ( ok && !st.overflow )
  { st.position = 0;
    ok = rewrite_goal(&rw, body, rebuilt);
  }

  if ( !ok || st.overflow )
  { free_bindings(rw.bindings);
    free(st.slots);
    return FALSE;
  }

  /* The bindings were collected newest-first; the Prolog pass binds in
   * source order, and unification is order-insensitive here because every
   * pair is variable-to-variable, so the order is presentation only. */
  term_t list = PL_new_term_ref();
  int built = PL_put_nil(list);
  for ( binding_cell *cell = rw.bindings; built && cell; cell = cell->next )
  { term_t pair = PL_new_term_ref();
    built = PL_cons_functor(pair, F_minus2, cell->v, cell->out) &&
            PL_cons_list(list, pair, list);
  }
  if ( !built )
  { free_bindings(rw.bindings);
    free(st.slots);
    return FALSE;
  }
  free_bindings(rw.bindings);
  free(st.slots);

  if ( !PL_unify(newbody, rebuilt) )
    return FALSE;
  return PL_unify(bindings, list);
}

install_t
install_mbr(void)
{ F_comma2 = PL_new_functor(PL_new_atom(","), 2);
  F_semicolon2 = PL_new_functor(PL_new_atom(";"), 2);
  F_arrow2 = PL_new_functor(PL_new_atom("->"), 2);
  F_unify2 = PL_new_functor(PL_new_atom("="), 2);
  F_minus2 = PL_new_functor(PL_new_atom("-"), 2);
  A_true = PL_new_atom("true");
  PL_register_foreign("metta_c_mbr_analyze", 4, mbr_analyze, 0);
}
