/* Purpose: the shipped-mode MeTTa reader in C, a faithful port of the two
 *   Prolog layers it accelerates: filereader.pl's top_forms//2 form splitter
 *   (string-state extent machine, exec markers, missing-paren diagnostics)
 *   and parser.pl's sexpr_mode//4 shipped grammar (layout and semicolon
 *   comments, $-variables with per-form identity, string literals with the
 *   five escapes, dcg/basics number//1 with boundary check, True/False,
 *   the quote-token fallback). Registered into module parser as
 *   metta_c_parse_source/4 and metta_c_sread/3 by parser.pl when this file's
 *   compiled reader.so sits beside it; the two extra arguments hand back the
 *   source's function-signature multiset and its declaration pairs from the
 *   same walk, the summaries filereader.pl's pre-passes used to re-walk the
 *   whole form list for [tested:
 *   reader_c:the_parse_summary_agrees_with_the_prolog_walks;
 *   commit=d1093b8bbf5d36b18a3a36fd2536eadc5d04fea3].
 * Assumes: input text arrives as an SWI atom, string, or number
 *   (PL_get_nchars CVT_ATOM|CVT_STRING|CVT_NUMBER, REP_UTF8); the engine
 *   dispatches here only while metta_reader_mode(shipped) holds, so no
 *   custom token registry needs consulting.
 * Guarantees:
 *   - metta_c_parse_source/2 answers exactly what parse_metta_source_prolog/2
 *     answers, parsed/3 and parsed/4 forms with byte-identical source
 *     strings, variant-identical terms, and name maps in the same
 *     newest-first order, over the whole example corpus and the adversarial
 *     battery [tested: reader_c in tests/prolog/suites/reader/reader_c.plt;
 *     commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
 *   - both predicates raise the Prolog reader's own error shapes:
 *     error(syntax_error(MsgAtom), none) with the identical message text for
 *     a missing ')' and for a form that does not parse, and FAIL (not raise)
 *     where the Prolog splitter fails, a stray top-level ')'
 *     [tested: reader_c:the_error_shapes_match_the_prolog_reader;
 *     commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
 *   - float literals saturate to inf/-inf past binary64 exactly as the
 *     engine's metta_saturating_parse/2 retry does, because strtod is the
 *     same correctly-rounded conversion number_codes/2 uses underneath
 *     [tested: reader_c:number_conversion_agrees_with_the_prolog_reader;
 *     commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
 * Fails when: a custom reader token is registered; parser.pl then keeps every
 *   parse on the Prolog grammar, and this file is never consulted about it.
 * Owns resources: per-call heap scratch (child stack, variable environment,
 *   string buffer), freed on every exit path; no globals beyond the
 *   install-time atom and functor handles.
 */

#define _GNU_SOURCE                    /* strtod_l, newlocale */
#include <SWI-Prolog.h>
#include "metta_token.h"
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <errno.h>
#include <locale.h>

static atom_t ATOM_expression, ATOM_function, ATOM_runnable, ATOM_none;
static atom_t ATOM_true, ATOM_false, ATOM_eq, ATOM_colon;
static functor_t FUNCTOR_parsed3, FUNCTOR_parsed4;
static functor_t FUNCTOR_error2, FUNCTOR_syntax_error1, FUNCTOR_minus2;
static locale_t c_locale;

/* ------------------------------------------------------------------ */
/* Scanner over UTF-8 bytes.  Only '\n' (a single byte) counts a line,
 * matching source_layout//2 and grab_until_balanced//6.               */

typedef struct
{ const unsigned char *s;
  size_t len;
  size_t pos;
  long line;                    /* 1-based */
} rd;

static inline int
rd_eos(const rd *r)
{ return r->pos >= r->len;
}

static inline unsigned int
rd_peek(const rd *r, int *sz)
{ return metta_utf8_decode(r->s + r->pos, r->len - r->pos, sz);
}

static inline void
rd_adv(rd *r, int sz, unsigned int cp)
{ r->pos += (size_t)sz;
  if ( cp == '\n' )
    r->line++;
}

/* The boundary tables, the UTF-8 codec and the number-token matcher live in
 * metta_token.h so this file and writer.c cannot drift apart about where a
 * token ends or what reads back as a number. */
#define cp_layout(cp)   metta_cp_layout(cp)
#define cp_boundary(cp) metta_cp_boundary(cp)

/* Layout plus semicolon comments; a comment ends only at LF or end of
 * input, source_layout//2 and metta_layout//0 alike. */
static void
rd_skip_layout(rd *r)
{ while ( !rd_eos(r) )
  { int sz;
    unsigned int cp = rd_peek(r, &sz);

    if ( cp == ';' )
    { rd_adv(r, sz, cp);
      while ( !rd_eos(r) )
      { int s2;
        unsigned int c2 = rd_peek(r, &s2);
        rd_adv(r, s2, c2);
        if ( c2 == '\n' )
          break;
      }
    } else if ( cp_layout(cp) )
    { rd_adv(r, sz, cp);
    } else
      break;
  }
}

/* string_state/3: the splitter's three-state machine (plus its comment
 * state).  Depth changes and boundary stops read the state BEFORE the
 * character, exactly as grab_until_balanced//6 and read_bare_atom//5 do. */
enum { ST_OUT, ST_STR, ST_ESC, ST_COM };

static int
st_next(int st, unsigned int cp)
{ switch ( st )
  { case ST_OUT: return cp == '"' ? ST_STR : cp == ';' ? ST_COM : ST_OUT;
    case ST_STR: return cp == '\\' ? ST_ESC : cp == '"' ? ST_OUT : ST_STR;
    case ST_ESC: return ST_STR;
    default:     return cp == '\n' ? ST_OUT : ST_COM;
  }
}

/* ------------------------------------------------------------------ */
/* Per-call growable scratch.                                          */

typedef struct
{ const unsigned char *name;
  size_t nlen;
  term_t var;
} env_entry;

/* Interned symbols of one call: a program repeats its heads endlessly, and
 * PL_new_atom_mbchars re-hashes the text every time where this open-address
 * table answers from the bytes.  Entries hold the registration PL_new_atom
 * made, so atom-GC cannot reclaim a cached atom mid-parse; the call's
 * cleanup unregisters every entry, returning the atoms to their terms'
 * ownership. */
#define ATOM_CACHE_SLOTS 1024   /* power of two */

typedef struct
{ const unsigned char *name;    /* NULL = empty slot */
  size_t nlen;
  atom_t atom;
} atom_slot;

typedef struct
{ env_entry *env;               /* $-variables, first occurrence first */
  size_t env_n, env_cap;
  term_t *kids;                 /* child stack shared across nesting */
  size_t kids_n, kids_cap;
  size_t *frames;               /* kids base per open '(' */
  size_t frames_n, frames_cap;
  unsigned char *str;           /* decoded string-literal bytes */
  size_t str_n, str_cap;
  atom_slot atoms[ATOM_CACHE_SLOTS];
} ctx;

static void
ctx_free(ctx *c)
{ size_t i;

  free(c->env);
  free(c->kids);
  free(c->frames);
  free(c->str);
  for ( i = 0; i < ATOM_CACHE_SLOTS; i++ )
  { if ( c->atoms[i].name )
      PL_unregister_atom(c->atoms[i].atom);
  }
  memset(c, 0, sizeof(*c));
}

/* FNV-1a over the token bytes. */
static inline size_t
atom_hash(const unsigned char *s, size_t n)
{ size_t h = 2166136261u;
  size_t i;

  for ( i = 0; i < n; i++ )
    h = (h ^ s[i]) * 16777619u;
  return h;
}

/* Answer the token's atom, cache-owned: the registration lives in the slot
 * until ctx_free drops it.  A full probe window EVICTS its first slot rather
 * than bypassing the cache, so the dictionary adapts to the stream's local
 * vocabulary the way an LZ dictionary does; evicting is safe because every
 * cached atom was put into a term the moment it was interned, and that term
 * holds it. */
static atom_t
intern_token(ctx *c, const unsigned char *s, size_t n)
{ size_t first = atom_hash(s, n) & (ATOM_CACHE_SLOTS - 1);
  size_t i = first;
  size_t probes;
  atom_slot *slot;

  for ( probes = 0; probes < 8; probes++, i = (i + 1) & (ATOM_CACHE_SLOTS - 1) )
  { slot = &c->atoms[i];
    if ( !slot->name )
    { slot->atom = PL_new_atom_mbchars(REP_UTF8, n, (const char *)s);
      slot->name = s;
      slot->nlen = n;
      return slot->atom;
    }
    if ( slot->nlen == n && memcmp(slot->name, s, n) == 0 )
      return slot->atom;
  }
  slot = &c->atoms[first];
  PL_unregister_atom(slot->atom);
  slot->atom = PL_new_atom_mbchars(REP_UTF8, n, (const char *)s);
  slot->name = s;
  slot->nlen = n;
  return slot->atom;
}

static int
grow(void **p, size_t *cap, size_t esize)
{ size_t ncap = *cap ? *cap * 2 : 64;
  void *np = realloc(*p, ncap * esize);
  if ( !np )
    return FALSE;
  *p = np;
  *cap = ncap;
  return TRUE;
}

static int
env_push(ctx *c, const unsigned char *name, size_t nlen, term_t var)
{ if ( c->env_n == c->env_cap &&
       !grow((void **)&c->env, &c->env_cap, sizeof(env_entry)) )
    return PL_resource_error("memory");
  c->env[c->env_n].name = name;
  c->env[c->env_n].nlen = nlen;
  c->env[c->env_n].var = var;
  c->env_n++;
  return TRUE;
}

static int
kids_push(ctx *c, term_t t)
{ if ( c->kids_n == c->kids_cap &&
       !grow((void **)&c->kids, &c->kids_cap, sizeof(term_t)) )
    return PL_resource_error("memory");
  c->kids[c->kids_n++] = t;
  return TRUE;
}

static int
frames_push(ctx *c, size_t base)
{ if ( c->frames_n == c->frames_cap &&
       !grow((void **)&c->frames, &c->frames_cap, sizeof(size_t)) )
    return PL_resource_error("memory");
  c->frames[c->frames_n++] = base;
  return TRUE;
}

static int
str_put(ctx *c, const unsigned char *bytes, size_t n)
{ while ( c->str_n + n > c->str_cap )
  { if ( !grow((void **)&c->str, &c->str_cap, 1) )
      return PL_resource_error("memory");
  }
  memcpy(c->str + c->str_n, bytes, n);
  c->str_n += n;
  return TRUE;
}

/* ------------------------------------------------------------------ */
/* The two error shapes, error(syntax_error(MsgAtom), none).           */

static int
raise_syntax_error_atom(atom_t msg)
{ term_t ex = PL_new_term_ref();
  term_t m = PL_new_term_ref();
  term_t none = PL_new_term_ref();

  PL_put_atom(m, msg);
  PL_unregister_atom(msg);
  PL_put_atom(none, ATOM_none);
  if ( !PL_cons_functor(m, FUNCTOR_syntax_error1, m) ||
       !PL_cons_functor(ex, FUNCTOR_error2, m, none) )
    return FALSE;
  return PL_raise_exception(ex);
}

/* format("missing ')', starting at line ~w:~n~s", [Line, RestOfLine]) */
static int
raise_missing_paren(long line, const unsigned char *rest, size_t restlen)
{ char head[64];
  int hlen = snprintf(head, sizeof(head),
                      "missing ')', starting at line %ld:\n", line);
  size_t total = (size_t)hlen + restlen;
  char *buf = malloc(total);
  atom_t msg;

  if ( !buf )
    return PL_resource_error("memory");
  memcpy(buf, head, (size_t)hlen);
  memcpy(buf + hlen, rest, restlen);
  msg = PL_new_atom_mbchars(REP_UTF8, total, buf);
  free(buf);
  return raise_syntax_error_atom(msg);
}

/* format('Parse error in form: ~w', [Source]) */
static int
raise_parse_error(const unsigned char *src, size_t srclen)
{ static const char head[] = "Parse error in form: ";
  size_t hlen = sizeof(head) - 1;
  char *buf = malloc(hlen + srclen);
  atom_t msg;

  if ( !buf )
    return PL_resource_error("memory");
  memcpy(buf, head, hlen);
  memcpy(buf + hlen, src, srclen);
  msg = PL_new_atom_mbchars(REP_UTF8, hlen + srclen, buf);
  free(buf);
  return raise_syntax_error_atom(msg);
}

/* ------------------------------------------------------------------ */
/* Tokens.                                                             */

static void
scan_token(rd *r)
{ while ( !rd_eos(r) )
  { int sz;
    unsigned int cp = rd_peek(r, &sz);
    if ( cp_boundary(cp) )
      break;
    rd_adv(r, sz, cp);
  }
}

#define token_is_number(t, n, fracexp) metta_token_is_number(t, n, fracexp)

static int
put_number_token(term_t out, const unsigned char *t, size_t n, int fracexp)
{ char small[64];
  char *buf = small;
  int rc;

  if ( n + 1 > sizeof(small) )
  { if ( !(buf = malloc(n + 1)) )
      return PL_resource_error("memory");
  }
  memcpy(buf, t, n);
  buf[n] = '\0';

  if ( !fracexp )
  { char *end;
    long long v;
    errno = 0;
    v = strtoll(buf, &end, 10);
    if ( errno != ERANGE )
    { rc = PL_put_int64(out, (int64_t)v);
    } else
    { /* past int64: SWI's own reader makes the bigint.  Strip a leading
       * '+', which Prolog term syntax does not accept on a literal. */
      const unsigned char *big = t;
      size_t bign = n;
      if ( big[0] == '+' )
      { big++; bign--;
      }
      rc = PL_put_term_from_chars(out, REP_UTF8, bign, (const char *)big);
    }
  } else
  { /* strtod saturates past binary64, the metta_saturating_parse/2
     * behaviour, and glibc's conversion is the same correctly rounded one
     * number_codes/2 performs. */
    double v = strtod_l(buf, NULL, c_locale);
    rc = PL_put_float(out, v);
  }

  if ( buf != small )
    free(buf);
  return rc;
}

/* atom_symbol//1's token classification: number, then the quote-delimited
 * raw-string fallback, then True/False, then a symbol. */
static int
classify_token(ctx *c, const unsigned char *t, size_t n, term_t out)
{ int fracexp;
  atom_t a;

  if ( token_is_number(t, n, &fracexp) )
    return put_number_token(out, t, n, fracexp);
  if ( t[0] == '"' )
  { /* atom_symbol//1 commits a quote-initial token to its quote branch:
     * with a closing quote it is the raw string between them, without one
     * the token FAILS, never a symbol. */
    if ( n >= 2 && t[n - 1] == '"' )
      return PL_put_chars(out, PL_STRING | REP_UTF8, n - 2,
                          (const char *)t + 1);
    return FALSE;
  }
  if ( n == 4 && memcmp(t, "True", 4) == 0 )
  { PL_put_atom(out, ATOM_true);
    return TRUE;
  }
  if ( n == 5 && memcmp(t, "False", 5) == 0 )
  { PL_put_atom(out, ATOM_false);
    return TRUE;
  }
  a = intern_token(c, t, n);
  PL_put_atom(out, a);
  return TRUE;
}

/* ------------------------------------------------------------------ */
/* sexpr_mode//4, shipped: layout, one token term, layout.  Iterative
 * with an explicit frame stack, so nesting depth is bounded by the
 * heap like the Prolog reader's, never by the native C stack.  Returns
 * FALSE for a soft parse failure with no exception; the caller turns
 * that into its own error.  A hard error (resource) raises and also
 * returns FALSE, which every path propagates unchanged.               */

/* One leaf token: a $-variable, a string literal, or a classified word. */
static int
parse_leaf(rd *r, ctx *c, term_t out)
{ int sz;
  unsigned int cp = rd_peek(r, &sz);

  if ( cp == '$' )
  { size_t save = r->pos;
    long saveline = r->line;
    size_t ts, te;

    rd_adv(r, sz, cp);
    ts = r->pos;
    scan_token(r);
    te = r->pos;
    if ( te > ts )
    { const unsigned char *name = r->s + ts;
      size_t nlen = te - ts;
      size_t i;

      if ( nlen == 1 && name[0] == '_' )
        return PL_put_variable(out);
      for ( i = 0; i < c->env_n; i++ )
      { if ( c->env[i].nlen == nlen &&
             memcmp(c->env[i].name, name, nlen) == 0 )
          return PL_put_term(out, c->env[i].var);
      }
      { term_t v = PL_new_term_ref();
        if ( !env_push(c, name, nlen, v) )
          return FALSE;
        return PL_put_term(out, v);
      }
    }
    r->pos = save;                      /* a lone $ reads as a symbol */
    r->line = saveline;
  }

  if ( cp == '"' )
  { size_t save = r->pos;
    long saveline = r->line;
    int closed = 0;

    rd_adv(r, sz, cp);
    c->str_n = 0;
    while ( !rd_eos(r) )
    { int s2;
      unsigned int c2 = rd_peek(r, &s2);

      if ( c2 == '"' )
      { rd_adv(r, s2, c2);
        closed = 1;
        break;
      }
      if ( c2 == '\\' )
      { int s3;
        unsigned int c3;
        rd_adv(r, s2, c2);
        if ( rd_eos(r) )
          break;
        c3 = rd_peek(r, &s3);
        if ( c3 == 'n' )
        { if ( !str_put(c, (const unsigned char *)"\n", 1) ) return FALSE;
        } else if ( c3 == 't' )
        { if ( !str_put(c, (const unsigned char *)"\t", 1) ) return FALSE;
        } else if ( c3 == 'r' )
        { if ( !str_put(c, (const unsigned char *)"\r", 1) ) return FALSE;
        } else
        { if ( !str_put(c, r->s + r->pos, (size_t)s3) ) return FALSE;
        }
        rd_adv(r, s3, c3);
      } else
      { if ( !str_put(c, r->s + r->pos, (size_t)s2) )
          return FALSE;
        rd_adv(r, s2, c2);
      }
    }
    if ( closed )
      return PL_put_chars(out, PL_STRING | REP_UTF8, c->str_n,
                          (const char *)c->str);
    r->pos = save;                      /* unterminated: the token fallback */
    r->line = saveline;
  }

  { size_t ts = r->pos;
    scan_token(r);
    if ( r->pos == ts )
      return FALSE;
    return classify_token(c, r->s + ts, r->pos - ts, out);
  }
}

static int
parse_sexpr(rd *r, ctx *c, term_t out)
{ size_t fbase = c->frames_n;

  for ( ;; )
  { int sz;
    unsigned int cp;
    term_t built;

    rd_skip_layout(r);
    if ( rd_eos(r) )
      goto soft_fail;
    cp = rd_peek(r, &sz);

    if ( cp == '(' )
    { rd_adv(r, sz, cp);
      if ( !frames_push(c, c->kids_n) )
        return FALSE;
      continue;
    }

    if ( cp == ')' && c->frames_n > fbase )
    { size_t base;
      rd_adv(r, sz, cp);
      built = PL_new_term_ref();
      PL_put_nil(built);
      base = c->frames[--c->frames_n];
      while ( c->kids_n > base )
      { c->kids_n--;
        if ( !PL_cons_list(built, c->kids[c->kids_n], built) )
          return FALSE;
      }
    } else
    { built = PL_new_term_ref();
      if ( !parse_leaf(r, c, built) )
      { if ( PL_exception(0) )
          return FALSE;
        goto soft_fail;
      }
    }

    if ( c->frames_n == fbase )
    { rd_skip_layout(r);
      return PL_put_term(out, built);
    }
    if ( !kids_push(c, built) )
      return FALSE;
  }

soft_fail:
  c->frames_n = fbase;
  return FALSE;
}

/* Term = [=, [F|_], _] with atom(F): the function classification of
 * parse_form_with_mode/3, read off the built term.  On success *f and
 * *arity carry the signature register_parsed_signatures/1 used to walk
 * the whole source for: F and the LENGTH of the head list [F|Args],
 * which is InputArity + 1. */
static int
function_signature(term_t t, atom_t *f, long *arity)
{ term_t l = PL_copy_term_ref(t);
  term_t h = PL_new_term_ref();
  atom_t a;

  if ( !PL_get_list(l, h, l) || !PL_get_atom(h, &a) || a != ATOM_eq )
    return 0;
  if ( !PL_get_list(l, h, l) )
    return 0;
  { term_t hh = PL_new_term_ref();
    term_t ht = PL_copy_term_ref(h);
    long n = 0;
    if ( !PL_get_list(ht, hh, ht) || !PL_get_atom(hh, f) )
      return 0;
    n = 1;
    while ( PL_get_list(ht, hh, ht) )
      n++;
    if ( !PL_get_nil(ht) )
      return 0;
    *arity = n;
  }
  if ( !PL_get_list(l, h, l) )
    return 0;
  return PL_get_nil(l);
}

/* Term = [:, Name, Type] with atom(Name): the declaration pair
 * source_declaration/4 used to walk the whole source for.  On success
 * pair holds Name-Type. */
static int
declaration_pair(term_t t, term_t pair)
{ term_t l = PL_copy_term_ref(t);
  term_t name = PL_new_term_ref();
  term_t type = PL_new_term_ref();
  term_t h = PL_new_term_ref();
  atom_t a;

  if ( !PL_get_list(l, h, l) || !PL_get_atom(h, &a) || a != ATOM_colon )
    return 0;
  if ( !PL_get_list(l, name, l) || !PL_get_atom(name, &a) )
    return 0;
  if ( !PL_get_list(l, type, l) || !PL_get_nil(l) )
    return 0;
  return PL_cons_functor(pair, FUNCTOR_minus2, name, type);
}

/* The reader's final environment, newest first: E accumulates [N-V|E0]. */
static int
put_names_list(ctx *c, term_t out)
{ size_t i;

  PL_put_nil(out);
  for ( i = 0; i < c->env_n; i++ )
  { term_t pair = PL_new_term_ref();
    term_t nt = PL_new_term_ref();
    atom_t name = PL_new_atom_mbchars(REP_UTF8, c->env[i].nlen,
                                      (const char *)c->env[i].name);

    PL_put_atom(nt, name);
    PL_unregister_atom(name);
    if ( !PL_cons_functor(pair, FUNCTOR_minus2, nt, c->env[i].var) ||
         !PL_cons_list(out, pair, out) )
      return FALSE;
  }
  return TRUE;
}

/* One source slice through the shipped grammar into parsed/3 or parsed/4,
 * unified with result.  Raises the Prolog reader's parse error when the
 * slice does not read as exactly one form.  The ctx belongs to the CALL,
 * one per foreign predicate, so the atom cache adapts across the whole
 * source; the per-form state resets here.  Variable identity is per form,
 * and the env's term refs die with the caller's per-form frame, which is
 * why env_n must reset rather than be remembered.  [measured 2026-08-24:
 * a per-form ctx spent 25% of the parse in its own memset and cleanup
 * scan, ctx_free 16.14% plus memset 9.16% of samples, and gave the cache
 * nothing to remember between forms.] */
static int
build_parsed_form(term_t result, ctx *c, const unsigned char *text,
                  size_t tlen, int runnable, term_t sig_tail,
                  term_t decl_tail)
{ rd r = { text, tlen, 0, 1 };
  term_t termt, str, kind, built;
  int ok;

  c->env_n = 0;
  c->kids_n = 0;
  c->frames_n = 0;
  c->str_n = 0;
  termt = PL_new_term_ref();
  ok = parse_sexpr(&r, c, termt);
  if ( ok && !rd_eos(&r) )
    ok = FALSE;
  if ( !ok )
  { if ( PL_exception(0) )
      return FALSE;
    return raise_parse_error(text, tlen);
  }

  str = PL_new_term_ref();
  kind = PL_new_term_ref();
  built = PL_new_term_ref();
  if ( !PL_put_chars(str, PL_STRING | REP_UTF8, tlen, (const char *)text) )
    return FALSE;
  if ( runnable )
  { term_t names = PL_new_term_ref();
    if ( !put_names_list(c, names) )
      return FALSE;
    PL_put_atom(kind, ATOM_runnable);
    ok = PL_cons_functor(built, FUNCTOR_parsed4, kind, str, termt, names);
  } else
  { atom_t f;
    long arity;
    if ( function_signature(termt, &f, &arity) )
    { term_t pair = PL_new_term_ref();
      term_t ft = PL_new_term_ref();
      term_t at = PL_new_term_ref();
      term_t shead = PL_new_term_ref();
      PL_put_atom(ft, f);
      if ( !PL_put_int64(at, arity) ||
           !PL_cons_functor(pair, FUNCTOR_minus2, ft, at) ||
           !PL_unify_list(sig_tail, shead, sig_tail) ||
           !PL_unify(shead, pair) )
        return FALSE;
      PL_put_atom(kind, ATOM_function);
    } else
    { term_t pair = PL_new_term_ref();
      if ( declaration_pair(termt, pair) )
      { term_t dhead = PL_new_term_ref();
        if ( !PL_unify_list(decl_tail, dhead, decl_tail) ||
             !PL_unify(dhead, pair) )
          return FALSE;
      }
      PL_put_atom(kind, ATOM_expression);
    }
    ok = PL_cons_functor(built, FUNCTOR_parsed3, kind, str, termt);
  }
  return ok && PL_unify(result, built);
}

/* ------------------------------------------------------------------ */
/* metta_c_parse_source(+Text, -ParsedForms): top_forms//2 fused with
 * parse_form_with_mode/3.                                             */

static foreign_t
c_parse_source(term_t source, term_t out, term_t sigs, term_t decls)
{ char *s;
  size_t len;
  rd r;
  ctx c;
  term_t tail, head, sig_tail, decl_tail;
  int rc = FALSE;

  if ( !PL_get_nchars(source, &len, &s,
                      CVT_ATOM | CVT_STRING | CVT_NUMBER | CVT_EXCEPTION |
                      REP_UTF8 | BUF_MALLOC) )
    return FALSE;

  memset(&c, 0, sizeof(c));
  r.s = (const unsigned char *)s;
  r.len = len;
  r.pos = 0;
  r.line = 1;
  tail = PL_copy_term_ref(out);
  head = PL_new_term_ref();
  sig_tail = PL_copy_term_ref(sigs);
  decl_tail = PL_copy_term_ref(decls);

  for ( ;; )
  { int sz;
    unsigned int cp;
    long form_line;
    int runnable = 0;
    size_t fstart, fend;

    rd_skip_layout(&r);
    if ( rd_eos(&r) )
      break;
    form_line = r.line;
    cp = rd_peek(&r, &sz);

    /* exec_marker//0: `!` marks only before '(', layout, or end of input */
    if ( cp == '!' )
    { size_t save = r.pos;
      long saveline = r.line;
      rd_adv(&r, sz, cp);
      if ( rd_eos(&r) )
        break;                          /* a bare marker contributes no form */
      { int s2;
        unsigned int c2 = rd_peek(&r, &s2);
        if ( c2 == '(' || cp_layout(c2) )
        { runnable = 1;
          rd_skip_layout(&r);
          if ( rd_eos(&r) )
            break;
          form_line = r.line;
          cp = rd_peek(&r, &sz);
        } else
        { r.pos = save;                 /* ordinary symbol character */
          r.line = saveline;
        }
      }
    }

    fstart = r.pos;
    if ( cp == '(' )
    { long depth = 1;
      int st = ST_OUT;
      size_t after_paren;
      int closed = 0;

      rd_adv(&r, sz, cp);
      after_paren = r.pos;
      while ( !rd_eos(&r) )
      { int s2;
        unsigned int c2 = rd_peek(&r, &s2);

        if ( st == ST_OUT )
        { if ( c2 == '(' )
            depth++;
          else if ( c2 == ')' )
            depth--;
        }
        st = st_next(st, c2);
        rd_adv(&r, s2, c2);
        if ( depth == 0 && st == ST_OUT )
        { closed = 1;
          break;
        }
      }
      if ( !closed )
      { size_t e = after_paren;
        while ( e < len && r.s[e] != '\n' )
          e++;
        raise_missing_paren(form_line, r.s + after_paren, e - after_paren);
        goto out;
      }
    } else
    { int st = ST_OUT;
      int any = 0;

      while ( !rd_eos(&r) )
      { int s2;
        unsigned int c2 = rd_peek(&r, &s2);
        if ( st == ST_OUT && cp_boundary(c2) )
          break;
        st = st_next(st, c2);
        rd_adv(&r, s2, c2);
        any = 1;
      }
      if ( !any )
        goto out;                       /* a stray ')' fails, never raises */
    }
    fend = r.pos;

    PL_put_variable(head);
    if ( !PL_unify_list(tail, head, tail) )
      goto out;
    { fid_t fid = PL_open_foreign_frame();
      int ok = build_parsed_form(head, &c, r.s + fstart, fend - fstart,
                                 runnable, sig_tail, decl_tail);
      PL_close_foreign_frame(fid);
      if ( !ok )
        goto out;
    }
  }
  rc = PL_unify_nil(tail) && PL_unify_nil(sig_tail) &&
       PL_unify_nil(decl_tail);

out:
  ctx_free(&c);
  PL_free(s);
  return rc;
}

/* ------------------------------------------------------------------ */
/* metta_c_sread(+Text, -Term, -Names): sread_with_names_mode/4 for the
 * shipped grammar, one form consuming the whole input.                */

static foreign_t
c_sread(term_t source, term_t term, term_t names)
{ char *s;
  size_t len;
  rd r;
  ctx c;
  term_t t, n;
  int ok;
  int rc = FALSE;

  if ( !PL_get_nchars(source, &len, &s,
                      CVT_ATOM | CVT_STRING | CVT_NUMBER | CVT_EXCEPTION |
                      REP_UTF8 | BUF_MALLOC) )
    return FALSE;

  r.s = (const unsigned char *)s;
  r.len = len;
  r.pos = 0;
  r.line = 1;
  memset(&c, 0, sizeof(c));

  t = PL_new_term_ref();
  ok = parse_sexpr(&r, &c, t);
  if ( ok && !rd_eos(&r) )
    ok = FALSE;
  if ( !ok )
  { if ( !PL_exception(0) )
      raise_parse_error(r.s, len);
    goto out;
  }
  n = PL_new_term_ref();
  if ( !put_names_list(&c, n) )
    goto out;
  rc = PL_unify(term, t) && PL_unify(names, n);

out:
  ctx_free(&c);
  PL_free(s);
  return rc;
}

/* ------------------------------------------------------------------ */

install_t
install_reader(void)
{ ATOM_expression = PL_new_atom("expression");
  ATOM_function = PL_new_atom("function");
  ATOM_runnable = PL_new_atom("runnable");
  ATOM_none = PL_new_atom("none");
  ATOM_true = PL_new_atom("true");
  ATOM_false = PL_new_atom("false");
  ATOM_eq = PL_new_atom("=");
  ATOM_colon = PL_new_atom(":");
  FUNCTOR_parsed3 = PL_new_functor(PL_new_atom("parsed"), 3);
  FUNCTOR_parsed4 = PL_new_functor(PL_new_atom("parsed"), 4);
  FUNCTOR_error2 = PL_new_functor(PL_new_atom("error"), 2);
  FUNCTOR_syntax_error1 = PL_new_functor(PL_new_atom("syntax_error"), 1);
  FUNCTOR_minus2 = PL_new_functor(PL_new_atom("-"), 2);
  c_locale = newlocale(LC_ALL_MASK, "C", (locale_t)0);

  PL_register_foreign_in_module("parser", "metta_c_parse_source", 4,
                                c_parse_source, 0);
  PL_register_foreign_in_module("parser", "metta_c_sread", 3, c_sread, 0);
}
