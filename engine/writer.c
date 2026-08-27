/* Purpose: the shipped-mode MeTTa writer in C, a faithful port of the three
 *   Prolog layers it accelerates in engine/parser.pl: swrite_mode//2's
 *   structural emit (booleans, numbers, strings with the five escapes,
 *   symbols, parenthesised lists, the two numbered-variable markers),
 *   metta_finite_float_codes/2's arbiter float layout, and
 *   metta_unwritable_walk/2's round-trip guard, which are one walk here and
 *   three there.  Registered into module parser as metta_c_write/3 and
 *   metta_c_unwritable/2 by parser.pl when this file's compiled writer.so
 *   sits beside it.
 * Assumes:
 *   - the caller dispatches here only while metta_reader_mode(shipped)
 *     holds for the two strict modes, so no custom token class can change
 *     what a symbol's spelling reads back as; display mode consults no
 *     writability and needs no such gate.
 *   - variables are numbered by first occurrence, which is what
 *     numbervars/3 does over the same left-to-right traversal, so the C walk
 *     reproduces stable_print_term/2 without copying the term.
 * Guarantees:
 *   - metta_c_write(T, strict, written(S)) answers exactly what
 *     swrite/2 answers, metta_c_write(T, display, written(S)) exactly what
 *     sdisplay/2 answers, and metta_c_write(P, strict_numbered, written(S))
 *     exactly what phrase(swrite_numbered(P)) answers, byte for byte over
 *     the whole shipped corpus and an adversarial battery
 *     [tested: writer_c in tests/prolog/suites/reader/writer_c.plt;
 *     commit=a9663314a626d6227ef948658b5de769992c0afa].
 *   - `unwritable(Bad)` names the same first offending subterm
 *     metta_unwritable_symbol/2 names, so parser.pl raises one error term
 *     from one place [tested: writer_c:the_refusal_names_the_same_culprit;
 *     commit=a9663314a626d6227ef948658b5de769992c0afa].
 *   - every float leaf spells SWI's own shortest-round-trip digits, taken
 *     from the same PL_get_text(CVT_FLOAT) call number_codes/2 makes
 *     [source: swipl-devel src/pl-prims.c x_chars/4 calls PL_get_text with
 *     CVT_NUMBER, and src/os/pl-text.c's CVT_FLOAT branch calls
 *     format_float(buf, size, valFloat(w), 3, 'e'); commit=a9663314a626d6227ef948658b5de769992c0afa], so no
 *     decimal conversion is reimplemented and no float can round differently
 *     here than in the Prolog writer.
 * Fails when: a term shape falls outside the ported fragment.  Every such
 *   shape answers `declined` and the Prolog writer, which is the
 *   specification, answers instead: an improper list, a rational, a
 *   non-marker compound or a blob in display mode, a term holding more than
 *   METTA_WRITER_VARS distinct variables, and a float or bignum whose SWI
 *   spelling does not fit this file's scratch.  Approximate bytes are never
 *   emitted.  metta_c_unwritable/2 runs the same walk with its bytes
 *   dropped, so the variable bound does not reach it.
 * Owns resources: per-call heap scratch (output buffer, list-frame stack,
 *   symbol transcription buffer), each with an inline first tier and freed on
 *   every exit path; no globals beyond the install-time atom and functor
 *   handles.
 * Open Obligations:
 *   To Do: None
 *   Hacks: None
 *   Future Enhancements: None
 */

#include <SWI-Prolog.h>
#include "metta_token.h"
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

static atom_t ATOM_true, ATOM_false;
static atom_t ATOM_strict, ATOM_strict_numbered, ATOM_display;
static atom_t ATOM_writable, ATOM_declined;
static functor_t FUNCTOR_written1, FUNCTOR_unwritable1;
static functor_t FUNCTOR_metta_variable1, FUNCTOR_metta_named_variable1;

/* swrite_mode//2's three usable modes.  STRICT is swrite/2's own: a
 * '$metta_variable'(N) compound reaching it is an ordinary compound, which
 * metta_text_writable/1 refuses, because swrite/2 asks that question before
 * numbering.  NUMBERED is the same emit over a term stable_print_term/2 or
 * named_print_term/3 already numbered, where the two markers ARE variables.
 * DISPLAY is sdisplay/2's lossy presentation, which asks nothing about
 * round-tripping. */
#define MODE_STRICT   0
#define MODE_NUMBERED 1
#define MODE_DISPLAY  2

/* Walk outcomes.  W_ERROR always carries a pending exception. */
#define W_OK       0
#define W_UNWRIT   1
#define W_DECLINE  2
#define W_ERROR    3

/* Distinct variables one call numbers before declining.  Identity of a
 * Prolog variable is only answerable by comparison (PL_compare answers 0 for
 * two references to one variable and the standard order is not stable across
 * a shift, so a sorted index is not available), which makes the scan
 * quadratic in the count.  MeTTa terms carry a handful; a term past this
 * bound is handed back to numbervars/3, which is linear. */
#define METTA_WRITER_VARS 64

#define OBUF_INLINE 1024
#define FRAME_INLINE 32
#define SYM_INLINE 256
/* Room for SWI's longest finite float spelling (sign, 17 digits, a dot and
 * an e+NNN exponent) with the arbiter layout's widest expansion (up to 15
 * padding zeros and ".0") on top. */
#define FLOAT_SCRATCH 96

/* ------------------------------------------------------------------ */
/* Output buffer: an inline first tier covers the ordinary answer (the
 * shipped corpus averages 64 written bytes per form), and only a larger
 * term reaches the heap.                                              */

typedef struct
{ unsigned char *b;
  size_t n, cap;
  int silent;                   /* metta_c_unwritable/2 wants the verdict
                                   only, so the same walk drops its bytes */
  unsigned char inl[OBUF_INLINE];
} obuf;

static int
ob_grow(obuf *o, size_t need)
{ size_t ncap = o->cap ? o->cap * 2 : OBUF_INLINE;
  unsigned char *nb;

  while ( ncap < need )
    ncap *= 2;
  if ( o->b == o->inl )
  { if ( !(nb = malloc(ncap)) )
      return PL_resource_error("memory");
    memcpy(nb, o->inl, o->n);
  } else
  { if ( !(nb = realloc(o->b, ncap)) )
      return PL_resource_error("memory");
  }
  o->b = nb;
  o->cap = ncap;
  return TRUE;
}

static int
ob_put(obuf *o, const void *s, size_t n)
{ if ( o->silent )
    return TRUE;
  if ( o->n + n > o->cap && !ob_grow(o, o->n + n) )
    return FALSE;
  memcpy(o->b + o->n, s, n);
  o->n += n;
  return TRUE;
}

static int
ob_putc(obuf *o, char c)
{ if ( o->silent )
    return TRUE;
  if ( o->n + 1 > o->cap && !ob_grow(o, o->n + 1) )
    return FALSE;
  o->b[o->n++] = (unsigned char)c;
  return TRUE;
}

/* number_codes/2's integer spelling: SWI's i64toa, which is an optional
 * minus and decimal digits with no padding [source: swipl-devel
 * src/os/pl-text.c, PL_get_text's V_INTEGER branch]. */
static int
ob_put_int64(obuf *o, int64_t v)
{ char tmp[24];
  char *p = tmp + sizeof(tmp);
  uint64_t u = v < 0 ? -(uint64_t)v : (uint64_t)v;

  do
  { *--p = (char)('0' + (u % 10));
    u /= 10;
  } while ( u );
  if ( v < 0 )
    *--p = '-';
  return ob_put(o, p, (size_t)(tmp + sizeof(tmp) - p));
}

static int
ob_put_zeros(obuf *o, int n)
{ static const char zeros[] = "0000000000000000";
  while ( n > 0 )
  { int chunk = n > 16 ? 16 : n;
    if ( !ob_put(o, zeros, (size_t)chunk) )
      return FALSE;
    n -= chunk;
  }
  return TRUE;
}

/* ------------------------------------------------------------------ */
/* Per-call state.                                                     */

typedef struct
{ term_t rest;                  /* the remaining list tail, its own cursor */
  int first;                    /* no separator before the first element */
} wframe;

typedef struct
{ obuf out;
  int mode;
  term_t bad;                   /* the culprit an `unwritable` answer names */
  term_t cur;                   /* the subterm being printed */
  term_t arg;                   /* scratch for a marker's argument */
  term_t vars[METTA_WRITER_VARS];
  size_t vars_n;
  wframe *fr;
  size_t fr_n, fr_cap, fr_ready;
  unsigned char *sym;           /* transcribed non-ASCII symbol text */
  size_t sym_cap;
  wframe fr_inl[FRAME_INLINE];
  unsigned char sym_inl[SYM_INLINE];
} wctx;

static int
ctx_init(wctx *c, int mode, int silent)
{ memset(c, 0, sizeof(*c));
  c->mode = mode;
  c->out.b = c->out.inl;
  c->out.cap = OBUF_INLINE;
  c->out.silent = silent;
  c->fr = c->fr_inl;
  c->fr_cap = FRAME_INLINE;
  c->sym = c->sym_inl;
  c->sym_cap = SYM_INLINE;
  return ( (c->bad = PL_new_term_ref()) &&
           (c->cur = PL_new_term_ref()) &&
           (c->arg = PL_new_term_ref()) );
}

static void
ctx_free(wctx *c)
{ if ( c->out.b != c->out.inl )
    free(c->out.b);
  if ( c->fr != c->fr_inl )
    free(c->fr);
  if ( c->sym != c->sym_inl )
    free(c->sym);
}

static int
sym_reserve(wctx *c, size_t need)
{ size_t ncap = c->sym_cap;
  unsigned char *ns;

  if ( need <= c->sym_cap )
    return TRUE;
  while ( ncap < need )
    ncap *= 2;
  ns = ( c->sym == c->sym_inl ) ? malloc(ncap) : realloc(c->sym, ncap);
  if ( !ns )
    return PL_resource_error("memory");
  c->sym = ns;
  c->sym_cap = ncap;
  return TRUE;
}

/* One open '(' and the tail still to print inside it.  Each frame owns a
 * term reference for its cursor; references already made are reused as the
 * walk leaves and re-enters a depth, so nesting costs one reference per
 * LEVEL rather than one per element. */
static int
push_frame(wctx *c, term_t from)
{ wframe *f;

  if ( c->fr_n == c->fr_cap )
  { size_t ncap = c->fr_cap * 2;
    wframe *nf = ( c->fr == c->fr_inl ) ? malloc(ncap * sizeof(wframe))
                                        : realloc(c->fr, ncap * sizeof(wframe));
    if ( !nf )
      return PL_resource_error("memory");
    if ( c->fr == c->fr_inl )
      memcpy(nf, c->fr_inl, c->fr_cap * sizeof(wframe));
    c->fr = nf;
    c->fr_cap = ncap;
  }
  f = &c->fr[c->fr_n];
  if ( c->fr_n >= c->fr_ready )
  { if ( !(f->rest = PL_new_term_ref()) )
      return FALSE;
    c->fr_ready = c->fr_n + 1;
  }
  if ( !PL_put_term(f->rest, from) )
    return FALSE;
  f->first = 1;
  c->fr_n++;
  return TRUE;
}

/* ------------------------------------------------------------------ */
/* Text.                                                               */

/* The atom's text as UTF-8 bytes.  A Latin-1 atom holding only ASCII is
 * already UTF-8 and is answered in place, with no copy and no string buffer,
 * which is every ordinary MeTTa symbol; a Latin-1 atom above ASCII and a
 * wide atom are transcoded into the call's own scratch, so the MM2 operators
 * and every other non-ASCII name take one deterministic path instead of
 * depending on the process locale. */
static int
atom_utf8(wctx *c, atom_t a, const unsigned char **sp, size_t *np)
{ size_t len, i, o;
  const char *n = PL_atom_nchars(a, &len);

  if ( n )
  { for ( i = 0; i < len; i++ )
    { if ( (unsigned char)n[i] >= 0x80 )
        break;
    }
    if ( i == len )
    { *sp = (const unsigned char *)n;
      *np = len;
      return TRUE;
    }
    if ( !sym_reserve(c, len * 2) )
      return FALSE;
    for ( i = 0, o = 0; i < len; i++ )
      o += (size_t)metta_utf8_put(c->sym + o, (unsigned char)n[i]);
    *sp = c->sym;
    *np = o;
    return TRUE;
  }

  { const pl_wchar_t *w = PL_atom_wchars(a, &len);

    if ( !w )
      return FALSE;
    if ( !sym_reserve(c, len * 4 + 4) )
      return FALSE;
    for ( i = 0, o = 0; i < len; )
    { unsigned int cp = (unsigned int)w[i++];

      /* wchar_t is UCS-4 wherever this engine builds; the surrogate join
       * keeps the transcription right on a UTF-16 wchar_t too. */
      if ( cp >= 0xD800 && cp <= 0xDBFF && i < len &&
           (unsigned int)w[i] >= 0xDC00 && (unsigned int)w[i] <= 0xDFFF )
        cp = 0x10000 + ((cp - 0xD800) << 10) + ((unsigned int)w[i++] - 0xDC00);
      o += (size_t)metta_utf8_put(c->sym + o, cp);
    }
    *sp = c->sym;
    *np = o;
    return TRUE;
  }
}

/* metta_symbol_writable/1 over the symbol's UTF-8 text: whether the spelling
 * reads back as this same symbol.  Its first two questions are one scan --
 * writable_token//1 refuses a quote and any token boundary -- and the third
 * is metta_symbol_ordinary/2, which admits a name whose first character
 * cannot open a variable, a number or a boolean.  A name that fails THAT is
 * read back in full, which for a token holding no boundary and no quote is
 * exactly: a '$' opens a variable unless nothing follows it, True and False
 * are the booleans' own spellings, and everything else turns on whether the
 * whole token is a number literal. */
static int
symbol_writable(const unsigned char *s, size_t n)
{ size_t i;
  unsigned char first;
  int fracexp;

  if ( n == 0 )                 /* Codes = [First|_] has no answer */
    return 0;

  for ( i = 0; i < n; )
  { unsigned char b = s[i];

    if ( b < 0x80 )
    { if ( b == '"' || metta_cp_boundary(b) )
        return 0;
      i++;
    } else
    { int sz;
      unsigned int cp = metta_utf8_decode(s + i, n - i, &sz);

      if ( metta_cp_boundary(cp) )
        return 0;
      i += (size_t)sz;
    }
  }

  first = s[0];
  if ( first == '$' )
    return n == 1;              /* "$name" reads back as a variable */
  if ( n == 4 && memcmp(s, "True", 4) == 0 )
    return 0;
  if ( n == 5 && memcmp(s, "False", 5) == 0 )
    return 0;
  if ( first == '.' || first == '-' || first == '+' ||
       metta_is_ascii_digit(first) )
    return !metta_token_is_number(s, n, &fracexp);
  return 1;                     /* metta_symbol_ordinary/2 */
}

/* escape_quotes//2: the five escapes hyperon's Str Display emits and this
 * reader decodes.  Each is ASCII and no UTF-8 continuation byte can carry
 * one, so escaping bytes is escaping codepoints; the unescaped run between
 * two of them copies whole. */
static int
emit_escaped(obuf *o, const unsigned char *s, size_t n)
{ size_t i, run = 0;

  if ( !ob_putc(o, '"') )
    return FALSE;
  for ( i = 0; i < n; i++ )
  { const char *esc;

    switch ( s[i] )
    { case '\\': esc = "\\\\"; break;
      case '"':  esc = "\\\""; break;
      case '\n': esc = "\\n";  break;
      case '\t': esc = "\\t";  break;
      case '\r': esc = "\\r";  break;
      default:   run++; continue;
    }
    if ( run && !ob_put(o, s + i - run, run) )
      return FALSE;
    run = 0;
    if ( !ob_put(o, esc, 2) )
      return FALSE;
  }
  if ( run && !ob_put(o, s + n - run, run) )
    return FALSE;
  return ob_putc(o, '"');
}

/* ------------------------------------------------------------------ */
/* Leaves.                                                             */

static int
refuse(wctx *c, term_t t)
{ return PL_put_term(c->bad, t) ? W_UNWRIT : W_ERROR;
}

/* A number or a string straight from SWI's own conversion, which for
 * CVT_INTEGER, CVT_RATIONAL and CVT_STRING is the same PL_get_text call
 * number_codes/2 and string_codes/2 reach.  The buffer stack is marked and
 * released per leaf so a large term cannot pile one buffer per atom up to
 * the foreign call's return. */
static int
emit_via_swi(wctx *c, term_t t, unsigned int cvt)
{ char *s;
  size_t n;
  int rc = W_DECLINE;

  PL_STRINGS_MARK();
  if ( PL_get_nchars(t, &n, &s, cvt) )
    rc = ob_put(&c->out, s, n) ? W_OK : W_ERROR;
  else if ( PL_exception(0) )
    rc = W_ERROR;
  PL_STRINGS_RELEASE();
  return rc;
}

static int
emit_string(wctx *c, term_t t)
{ char *s;
  size_t n;
  int rc = W_DECLINE;

  PL_STRINGS_MARK();
  if ( PL_get_nchars(t, &n, &s, CVT_STRING | REP_UTF8) )
    rc = emit_escaped(&c->out, (const unsigned char *)s, n) ? W_OK : W_ERROR;
  else if ( PL_exception(0) )
    rc = W_ERROR;
  PL_STRINGS_RELEASE();
  return rc;
}

static int
emit_integer(wctx *c, term_t t)
{ int64_t v;

  if ( PL_get_int64(t, &v) )
    return ob_put_int64(&c->out, v) ? W_OK : W_ERROR;
  return emit_via_swi(c, t, CVT_INTEGER);  /* past int64: mpz_get_str */
}

/* metta_finite_float_codes/2: SWI's spelling relaid in the arbiter's
 * layout.  The split recovers the digits D and the power of ten E with
 * value = D * 10^E, strips the leading and trailing zeros the layout does
 * not want (dropping a trailing zero divides D by ten, so E rises with it),
 * and then chooses among five branches on KK, the exponent making the value
 * 0.D * 10^KK.  The five branches and their bounds are the ones LeaTTa's
 * RyuLean4/Runtime.lean:371-396 pins and CeTTa reaches the same way
 * [source: CeTTa src/atom.c, cetta_format_float, at
 * MesTTo/CeTTa@0ca2f4bad47205174608d7af54dd12a4c12b2e0b, reached through
 * CETTA_PATH the way tests/conformance/cetta.py reaches the fork; its
 * closing branch table is this one character for character, and that
 * file selects its own digits by trial and records that the closest
 * candidate is outside the rounding interval for 46 of the 2098 powers of
 * two, which is exactly the reason the digits here come from SWI rather
 * than from a reimplementation]. */
static int
emit_finite_float(wctx *c, const char *swi, size_t len)
{ char digits[64];
  size_t nd = 0, i = 0, frac_len = 0;
  int neg = 0, tens, kk, point;

  if ( len > 0 && swi[0] == '-' )
  { neg = 1;
    i = 1;
  }
  { size_t e = i;

    while ( e < len && swi[e] != 'e' && swi[e] != 'E' )
      e++;
    if ( e < len )
    { int sign = 1;
      size_t p = e + 1;
      int exp = 0;

      if ( p < len && (swi[p] == '+' || swi[p] == '-') )
      { sign = swi[p] == '-' ? -1 : 1;
        p++;
      }
      if ( p == len )
        return W_DECLINE;
      for ( ; p < len; p++ )
      { if ( !metta_is_ascii_digit((unsigned char)swi[p]) )
          return W_DECLINE;
        exp = exp * 10 + (swi[p] - '0');
      }
      tens = sign * exp;
      len = e;
    } else
      tens = 0;
  }
  for ( ; i < len; i++ )
  { if ( swi[i] == '.' )
    { frac_len = len - i - 1;
      continue;
    }
    if ( !metta_is_ascii_digit((unsigned char)swi[i]) || nd == sizeof(digits) )
      return W_DECLINE;
    digits[nd++] = swi[i];
  }
  if ( nd == 0 )
    return W_DECLINE;
  tens -= (int)frac_len;

  { size_t lead = 0;

    while ( lead + 1 < nd && digits[lead] == '0' )
      lead++;
    if ( lead )
    { memmove(digits, digits + lead, nd - lead);
      nd -= lead;
    }
  }
  while ( nd > 1 && digits[nd - 1] == '0' )
  { nd--;
    tens++;
  }

  if ( neg && !ob_putc(&c->out, '-') )
    return W_ERROR;
  if ( nd == 1 && digits[0] == '0' )
    return ob_put(&c->out, "0.0", 3) ? W_OK : W_ERROR;

  kk = (int)nd + tens;
  point = kk - (int)nd;
  if ( point >= 0 && kk <= 16 )
  { if ( !ob_put(&c->out, digits, nd) ||
         !ob_put_zeros(&c->out, point) ||
         !ob_put(&c->out, ".0", 2) )
      return W_ERROR;
  } else if ( kk > 0 && kk <= 16 )
  { if ( !ob_put(&c->out, digits, (size_t)kk) ||
         !ob_putc(&c->out, '.') ||
         !ob_put(&c->out, digits + kk, nd - (size_t)kk) )
      return W_ERROR;
  } else if ( kk > -5 && kk <= 0 )
  { if ( !ob_put(&c->out, "0.", 2) ||
         !ob_put_zeros(&c->out, -kk) ||
         !ob_put(&c->out, digits, nd) )
      return W_ERROR;
  } else
  { if ( nd == 1 )
    { if ( !ob_put(&c->out, digits, 1) )
        return W_ERROR;
    } else
    { if ( !ob_put(&c->out, digits, 1) ||
           !ob_putc(&c->out, '.') ||
           !ob_put(&c->out, digits + 1, nd - 1) )
        return W_ERROR;
    }
    if ( !ob_putc(&c->out, 'e') || !ob_put_int64(&c->out, (int64_t)(kk - 1)) )
      return W_ERROR;
  }
  return W_OK;
}

/* metta_float_codes/2.  The non-finite classes print the arbiter's
 * spellings, and the strict writer refuses them because those spellings read
 * back as SYMBOLS of that name, which is what metta_number_writable/1 says
 * with float_class/2. */
static int
emit_float(wctx *c, term_t t)
{ double v;
  char swi[FLOAT_SCRATCH];
  char *s;
  size_t n;
  int rc;

  if ( !PL_get_float(t, &v) )
    return W_ERROR;
  if ( isinf(v) )
  { if ( c->mode != MODE_DISPLAY )
      return refuse(c, t);
    return ( v > 0.0 ? ob_put(&c->out, "inf", 3)
                     : ob_put(&c->out, "-inf", 4) ) ? W_OK : W_ERROR;
  }
  if ( isnan(v) )
  { if ( c->mode != MODE_DISPLAY )
      return refuse(c, t);
    return ob_put(&c->out, "NaN", 3) ? W_OK : W_ERROR;
  }

  rc = W_DECLINE;
  PL_STRINGS_MARK();
  if ( PL_get_nchars(t, &n, &s, CVT_FLOAT) && n < sizeof(swi) )
  { memcpy(swi, s, n);
    rc = W_OK;
  } else if ( PL_exception(0) )
    rc = W_ERROR;
  PL_STRINGS_RELEASE();
  if ( rc != W_OK )
    return rc;
  return emit_finite_float(c, swi, n);
}

static int
emit_variable(wctx *c, term_t t)
{ size_t i;

  for ( i = 0; i < c->vars_n; i++ )
  { if ( PL_compare(c->vars[i], t) == 0 )
      break;
  }
  if ( i == c->vars_n )
  { if ( c->vars_n == METTA_WRITER_VARS )
      return W_DECLINE;
    if ( !(c->vars[i] = PL_new_term_ref()) || !PL_put_term(c->vars[i], t) )
      return W_ERROR;
    c->vars_n++;
  }
  return ( ob_put(&c->out, "$_", 2) && ob_put_int64(&c->out, (int64_t)i) )
         ? W_OK : W_ERROR;
}

static int
emit_atom(wctx *c, term_t t)
{ atom_t a;
  const unsigned char *s;
  size_t n;

  if ( !PL_get_atom(t, &a) )
    return W_ERROR;
  if ( a == ATOM_true )
    return ob_put(&c->out, "True", 4) ? W_OK : W_ERROR;
  if ( a == ATOM_false )
    return ob_put(&c->out, "False", 5) ? W_OK : W_ERROR;
  if ( !atom_utf8(c, a, &s, &n) )
    return PL_exception(0) ? W_ERROR : W_DECLINE;
  if ( c->mode != MODE_DISPLAY && !symbol_writable(s, n) )
    return refuse(c, t);
  return ob_put(&c->out, s, n) ? W_OK : W_ERROR;
}

static int
emit_compound(wctx *c, term_t t)
{ if ( c->mode != MODE_STRICT )
  { if ( PL_is_functor(t, FUNCTOR_metta_variable1) )
    { int64_t ix;

      if ( !PL_get_arg(1, t, c->arg) )
        return W_ERROR;
      if ( !PL_get_int64(c->arg, &ix) )
        return W_DECLINE;
      return ( ob_put(&c->out, "$_", 2) && ob_put_int64(&c->out, ix) )
             ? W_OK : W_ERROR;
    }
    if ( PL_is_functor(t, FUNCTOR_metta_named_variable1) )
    { atom_t na;
      const unsigned char *s;
      size_t n;

      if ( !PL_get_arg(1, t, c->arg) )
        return W_ERROR;
      if ( !PL_get_atom(c->arg, &na) )
        return W_DECLINE;
      if ( !atom_utf8(c, na, &s, &n) )
        return PL_exception(0) ? W_ERROR : W_DECLINE;
      return ( ob_putc(&c->out, '$') && ob_put(&c->out, s, n) )
             ? W_OK : W_ERROR;
    }
  }
  if ( c->mode == MODE_DISPLAY )
    return W_DECLINE;           /* seam:grounded_text/2, then term_string/2 */
  return refuse(c, t);
}

static int
emit_leaf(wctx *c, term_t t, int type)
{ /* metta_c_unwritable/2 asks only whether a leaf HAS a text form, and under
   * the shipped reader four kinds always do: metta_string_writable/1 answers
   * true with no custom class registered, metta_number_writable/1 answers
   * true for every integer, and metta_unwritable_walk/2 fails outright on []
   * and on a variable. Spelling those out only to drop the bytes is the whole
   * of what this skips, and it is not nothing: a UTF-8 conversion per string,
   * a decimal per integer, and the first-occurrence scan per variable, which
   * also lets the guard answer for a term past the walk's variable bound
   * where the emit would decline. */
  if ( c->out.silent )
  { switch ( type )
    { case PL_STRING:
      case PL_INTEGER:
      case PL_NIL:
      case PL_VARIABLE:
        return W_OK;
      default:
        break;
    }
  }

  switch ( type )
  { case PL_VARIABLE:
      return emit_variable(c, t);
    case PL_NIL:
      return ob_put(&c->out, "()", 2) ? W_OK : W_ERROR;
    case PL_ATOM:
      return emit_atom(c, t);
    case PL_STRING:
      return emit_string(c, t);
    case PL_INTEGER:
      return emit_integer(c, t);
    case PL_FLOAT:
      return emit_float(c, t);
    case PL_RATIONAL:
      /* strict refuses every rational, its NrD spelling reading back as a
       * symbol; the Prolog writer says so by running the grammar, so it
       * answers rather than this file guessing. */
      return c->mode == MODE_DISPLAY ? emit_via_swi(c, t, CVT_RATIONAL)
                                     : W_DECLINE;
    case PL_TERM:
      return emit_compound(c, t);
    case PL_BLOB:
      return c->mode == MODE_DISPLAY ? W_DECLINE : refuse(c, t);
    default:
      return W_DECLINE;         /* a dict, and whatever SWI adds next */
  }
}

/* ------------------------------------------------------------------ */
/* The walk.  Iterative with an explicit frame stack, so nesting depth is
 * bounded by the heap and never by the native C stack, the shape CeTTa's
 * atom_print_mode uses for the same reason
 * [source: CeTTa src/atom.c, AtomPrintStack, at
 * MesTTo/CeTTa@0ca2f4bad47205174608d7af54dd12a4c12b2e0b].              */

static int
emit_term(wctx *c, term_t t0)
{ size_t base = c->fr_n;

  if ( !PL_put_term(c->cur, t0) )
    return W_ERROR;

  for ( ;; )
  { int type = PL_term_type(c->cur);

    if ( type == PL_LIST_PAIR )
    { if ( !ob_putc(&c->out, '(') )
        return W_ERROR;
      if ( !push_frame(c, c->cur) )
        return W_ERROR;
    } else
    { int r = emit_leaf(c, c->cur, type);

      if ( r != W_OK )
        return r;
    }

    for ( ;; )
    { wframe *f;

      if ( c->fr_n == base )
        return W_OK;
      f = &c->fr[c->fr_n - 1];
      if ( PL_get_list(f->rest, c->cur, f->rest) )
      { if ( f->first )
          f->first = 0;
        else if ( !ob_putc(&c->out, ' ') )
          return W_ERROR;
        break;
      }
      if ( !PL_get_nil(f->rest) )
        return W_DECLINE;       /* an improper list: swrite/2 refuses the
                                   NUMBERED tail, which only its own
                                   numbering can name */
      if ( !ob_putc(&c->out, ')') )
        return W_ERROR;
      c->fr_n--;
    }
  }
}

/* ------------------------------------------------------------------ */

static int
unify_declined(term_t result)
{ return PL_unify_atom(result, ATOM_declined);
}

static int
unify_unwritable(term_t result, term_t bad)
{ term_t r = PL_new_term_ref();

  return PL_cons_functor(r, FUNCTOR_unwritable1, bad) && PL_unify(result, r);
}

/* metta_c_write(+Term, +Mode, -Result) */
static foreign_t
c_write(term_t term, term_t mode, term_t result)
{ wctx c;
  atom_t m;
  int r, rc, wmode;

  if ( !PL_get_atom(mode, &m) )
    return FALSE;
  if ( m == ATOM_strict )
    wmode = MODE_STRICT;
  else if ( m == ATOM_strict_numbered )
    wmode = MODE_NUMBERED;
  else if ( m == ATOM_display )
    wmode = MODE_DISPLAY;
  else
    return FALSE;

  if ( !ctx_init(&c, wmode, FALSE) )
    return FALSE;
  r = emit_term(&c, term);
  switch ( r )
  { case W_OK:
    { term_t s = PL_new_term_ref();
      term_t w = PL_new_term_ref();

      rc = s && w &&
           PL_put_chars(s, PL_STRING | REP_UTF8, c.out.n,
                        (const char *)c.out.b) &&
           PL_cons_functor(w, FUNCTOR_written1, s) &&
           PL_unify(result, w);
      break;
    }
    case W_UNWRIT:
      rc = unify_unwritable(result, c.bad);
      break;
    case W_DECLINE:
      rc = unify_declined(result);
      break;
    default:
      rc = FALSE;
      break;
  }
  ctx_free(&c);
  return rc;
}

/* metta_c_unwritable(+Term, -Result): the same walk with its bytes dropped,
 * which is why the guard and the emit here cannot disagree the way two
 * Prolog walks can. */
static foreign_t
c_unwritable(term_t term, term_t result)
{ wctx c;
  int r, rc;

  if ( !ctx_init(&c, MODE_STRICT, TRUE) )
    return FALSE;
  r = emit_term(&c, term);
  switch ( r )
  { case W_OK:
      rc = PL_unify_atom(result, ATOM_writable);
      break;
    case W_UNWRIT:
      rc = unify_unwritable(result, c.bad);
      break;
    case W_DECLINE:
      rc = unify_declined(result);
      break;
    default:
      rc = FALSE;
      break;
  }
  ctx_free(&c);
  return rc;
}

/* ------------------------------------------------------------------ */

install_t
install_writer(void)
{ ATOM_true = PL_new_atom("true");
  ATOM_false = PL_new_atom("false");
  ATOM_strict = PL_new_atom("strict");
  ATOM_strict_numbered = PL_new_atom("strict_numbered");
  ATOM_display = PL_new_atom("display");
  ATOM_writable = PL_new_atom("writable");
  ATOM_declined = PL_new_atom("declined");
  FUNCTOR_written1 = PL_new_functor(PL_new_atom("written"), 1);
  FUNCTOR_unwritable1 = PL_new_functor(PL_new_atom("unwritable"), 1);
  FUNCTOR_metta_variable1 = PL_new_functor(PL_new_atom("$metta_variable"), 1);
  FUNCTOR_metta_named_variable1 =
      PL_new_functor(PL_new_atom("$metta_named_variable"), 1);

  PL_register_foreign_in_module("parser", "metta_c_write", 3, c_write, 0);
  PL_register_foreign_in_module("parser", "metta_c_unwritable", 2,
                                c_unwritable, 0);
}
