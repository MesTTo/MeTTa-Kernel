/* Purpose: JSON text to and from Prolog terms in C, a fast path beside
 *   SWI-Prolog's own library(json), which stays the specification. Registered
 *   into module json_codec as metta_c_json_read/3 and metta_c_json_write/3 by
 *   json_codec.pl when this file's compiled json_codec.so sits beside it.
 *
 *   The cost this removes is measured, not assumed. SWI's reader takes JSON
 *   apart one character at a time in Prolog: an SWI profile of json_read_dict/3
 *   over a 25,017-byte document puts 35.1% of self time in system:get_code/2
 *   and 21.2% in json:json_string_codes/3, and its dict door parses the whole
 *   document into the classic json(Pairs) shape before converting that to
 *   dicts. This file scans bytes and builds the answer once.
 *
 * Assumes: text arrives as an SWI atom, string, number or code list
 *   (PL_get_nchars CVT_ATOM|CVT_STRING|CVT_NUMBER|CVT_LIST, REP_UTF8), so the
 *   bytes scanned here are already valid UTF-8; and the option term names the
 *   shape and the three literals, which json_codec.pl builds.
 *
 * Guarantees:
 *   - both predicates either answer EXACTLY what the Prolog implementation
 *     answers, or FAIL, and a failure is the seam's signal to run the Prolog
 *     implementation. Nothing here approximates: every construct this file is
 *     not certain about is declined, including a lone surrogate, a number
 *     outside strict JSON syntax, a trailing comma, text after the value, a
 *     duplicate key, a nesting deeper than J_MAX_DEPTH, a non-finite or
 *     rational number, and any term the writer does not recognise
 *     [tested: json_codec_differential:the_c_path_declines_rather_than_guessing,
 *     json_codec_differential:the_c_writer_declines_rather_than_guessing].
 *   - no exception leaves either predicate except a resource error. Every JSON
 *     error is raised by the Prolog implementation, so error terms, messages
 *     and stream positions are the ones library(json) has always produced
 *     [tested: json_codec_differential:every_document_reads_the_same_through_both_paths].
 *   - numbers are converted by SWI itself. Reading hands the collected token
 *     to PL_put_term_from_chars, exactly as SWI's own json_read_number/3 does,
 *     so unbounded integers stay exact; writing takes the number's text from
 *     PL_get_nchars(CVT_NUMBER), which is the same format_float() call write/1
 *     makes [source: swipl-devel src/os/pl-text.c PL_get_text CVT_FLOAT branch
 *     and src/pl-write.c writeNumber].
 *
 * Fails when: the artefact is absent or METTA_C_JSON=off, in which case
 *   json_codec.pl never calls here and library(json) answers everything.
 *
 * Owns resources: per-call heap scratch (the input copy from BUF_MALLOC, the
 *   string and output buffers, the per-object key and value vectors), freed on
 *   every exit path; and one reference per object key atom, released as soon
 *   as the dict or the pair list holds it.
 *
 * Open Obligations:
 *   To Do: None
 *   Hacks: None
 *   Future Enhancements: None
 */

#define _GNU_SOURCE                     /* strtod_l, newlocale */
#include <SWI-Prolog.h>
#include <errno.h>
#include <locale.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* Every function that walks JSON answers one of these. J_DECLINE means "the
 * Prolog implementation should do this one", never "the input is bad". */
#define J_DECLINE 0
#define J_OK      1
#define J_ERROR (-1)

/* Deeper than this and the C stack, not JSON, is the limit. The Prolog reader
 * this declines to recurses on Prolog's own stacks, which grow, so a document
 * past this depth is still answered, just not here. */
#define J_MAX_DEPTH 1000

static functor_t FUNCTOR_json1, FUNCTOR_equals2;
static atom_t ATOM_true;
/* JSON's decimal point is '.' whatever the process locale says, so the
 * conversion is done in the C locale, as engine/reader.c does for the same
 * reason. */
static locale_t c_locale;

                 /*******************************
                 *        GROWABLE BYTES        *
                 *******************************/

typedef struct
{ char  *data;
  size_t len;
  size_t cap;
  char   fixed[1024];
} buf;

static void
buf_init(buf *b)
{ b->data = b->fixed;
  b->len = 0;
  b->cap = sizeof(b->fixed);
}

static void
buf_free(buf *b)
{ if ( b->data != b->fixed )
    free(b->data);
}

static int
buf_reserve(buf *b, size_t extra)
{ size_t want;
  char *grown;

  if ( b->len + extra <= b->cap )
    return TRUE;
  want = b->cap;
  while ( want < b->len + extra )
    want *= 2;
  if ( b->data == b->fixed )
  { if ( !(grown = malloc(want)) )
      return FALSE;
    memcpy(grown, b->fixed, b->len);
  } else if ( !(grown = realloc(b->data, want)) )
    return FALSE;
  b->data = grown;
  b->cap = want;
  return TRUE;
}

static int
buf_putn(buf *b, const void *s, size_t n)
{ if ( !buf_reserve(b, n) )
    return FALSE;
  memcpy(b->data + b->len, s, n);
  b->len += n;
  return TRUE;
}

static int
buf_putc(buf *b, char c)
{ if ( !buf_reserve(b, 1) )
    return FALSE;
  b->data[b->len++] = c;
  return TRUE;
}

static int
buf_put_utf8(buf *b, unsigned int c)
{ char t[4];
  size_t n;

  if ( c < 0x80 )
  { t[0] = (char)c;
    n = 1;
  } else if ( c < 0x800 )
  { t[0] = (char)(0xC0 | (c >> 6));
    t[1] = (char)(0x80 | (c & 0x3F));
    n = 2;
  } else if ( c < 0x10000 )
  { t[0] = (char)(0xE0 | (c >> 12));
    t[1] = (char)(0x80 | ((c >> 6) & 0x3F));
    t[2] = (char)(0x80 | (c & 0x3F));
    n = 3;
  } else
  { t[0] = (char)(0xF0 | (c >> 18));
    t[1] = (char)(0x80 | ((c >> 12) & 0x3F));
    t[2] = (char)(0x80 | ((c >> 6) & 0x3F));
    t[3] = (char)(0x80 | (c & 0x3F));
    n = 4;
  }
  return buf_putn(b, t, n);
}

                 /*******************************
                 *          THE OPTIONS         *
                 *******************************/

/* A literal is the term the caller uses for JSON's true, false and null. Both
 * shapes library(json) is given here are covered: a plain atom, and a
 * one-argument compound over an atom, which is @(true) and its siblings. */
typedef struct
{ int       compound;
  functor_t functor;
  atom_t    name;
} jliteral;

typedef struct
{ int      dicts;                       /* dict shape, else json(Pairs) */
  atom_t   tag;                         /* what a decoded object is tagged */
  jliteral t, f, n;
  term_t   scratch;                     /* one reusable ref for literal tests */
} jopts;

static int
literal_from(term_t t, jliteral *l)
{ atom_t a;
  functor_t f;

  if ( PL_get_atom(t, &a) )
  { l->compound = FALSE;
    l->name = a;
    return J_OK;
  }
  if ( PL_get_functor(t, &f) && PL_functor_arity(f) == 1 )
  { term_t arg = PL_new_term_ref();

    if ( PL_get_arg(1, t, arg) && PL_get_atom(arg, &a) )
    { l->compound = TRUE;
      l->functor = f;
      l->name = a;
      return J_OK;
    }
  }
  return J_DECLINE;
}

static int
unify_literal(term_t out, const jliteral *l)
{ if ( !l->compound )
    return PL_unify_atom(out, l->name);
  return PL_unify_term(out, PL_FUNCTOR, l->functor, PL_ATOM, l->name);
}

static int
is_literal(term_t t, const jliteral *l, term_t scratch)
{ atom_t a;
  functor_t f;

  if ( !l->compound )
    return PL_get_atom(t, &a) && a == l->name;
  return ( PL_get_functor(t, &f) && f == l->functor &&
           PL_get_arg(1, t, scratch) && PL_get_atom(scratch, &a) &&
           a == l->name );
}

/* json_codec_options(Dicts, Tag, True, False, Null), built by json_codec.pl.
 * The tag is json_read_dict/3's default_tag, which json_codec.pl names once so
 * the C reader and the Prolog reader cannot drift apart on it. */
static int
options_from(term_t t, jopts *o)
{ term_t arg = PL_new_term_ref();
  atom_t shape;
  functor_t f;

  if ( !PL_get_functor(t, &f) || PL_functor_arity(f) != 5 )
    return J_DECLINE;
  if ( !PL_get_arg(1, t, arg) || !PL_get_atom(arg, &shape) )
    return J_DECLINE;
  o->dicts = ( shape == ATOM_true );
  if ( !PL_get_arg(2, t, arg) || !PL_get_atom(arg, &o->tag) )
    return J_DECLINE;
  if ( !PL_get_arg(3, t, arg) || literal_from(arg, &o->t) != J_OK ||
       !PL_get_arg(4, t, arg) || literal_from(arg, &o->f) != J_OK ||
       !PL_get_arg(5, t, arg) || literal_from(arg, &o->n) != J_OK )
    return J_DECLINE;
  o->scratch = PL_new_term_ref();
  return J_OK;
}

                 /*******************************
                 *            READING           *
                 *******************************/

typedef struct
{ const unsigned char *s;
  size_t len;
  size_t pos;
} scan;

/* Exactly json_skip_ws()'s set in SWI's own json.c: space, tab, newline and
 * carriage return. JSON has no comments and neither does the implementation
 * this matches. */
static void
skip_ws(scan *r)
{ while ( r->pos < r->len )
  { unsigned char c = r->s[r->pos];

    if ( c == ' ' || c == '\t' || c == '\n' || c == '\r' )
      r->pos++;
    else
      break;
  }
}

static int
hex_digit(unsigned char c)
{ if ( c >= '0' && c <= '9' ) return c - '0';
  if ( c >= 'a' && c <= 'f' ) return c - 'a' + 10;
  if ( c >= 'A' && c <= 'F' ) return c - 'A' + 10;
  return -1;
}

static int
read_4hex(scan *r, unsigned int *out)
{ unsigned int v = 0;
  int i;

  if ( r->pos + 4 > r->len )
    return FALSE;
  for(i = 0; i < 4; i++)
  { int d = hex_digit(r->s[r->pos + i]);

    if ( d < 0 )
      return FALSE;
    v = v * 16 + (unsigned int)d;
  }
  r->pos += 4;
  *out = v;
  return TRUE;
}

/* r->pos sits just past the opening quote; on J_OK it sits just past the
 * closing one and b holds the decoded UTF-8 bytes. Unescaped runs are copied
 * whole, which is where the win over a per-character Prolog loop comes from. */
static int
read_string(scan *r, buf *b)
{ size_t run = r->pos;

  for(;;)
  { unsigned char c;

    if ( r->pos >= r->len )
      return J_DECLINE;                 /* eof_in_string; Prolog names it */
    c = r->s[r->pos];
    if ( c == '"' )
    { if ( !buf_putn(b, r->s + run, r->pos - run) )
        return J_ERROR;
      r->pos++;
      return J_OK;
    }
    if ( c != '\\' )
    { r->pos++;
      continue;
    }
    if ( !buf_putn(b, r->s + run, r->pos - run) )
      return J_ERROR;
    r->pos++;
    if ( r->pos >= r->len )
      return J_DECLINE;
    c = r->s[r->pos++];
    switch(c)
    { case '"':  if ( !buf_putc(b, '"') )  return J_ERROR; break;
      case '\\': if ( !buf_putc(b, '\\') ) return J_ERROR; break;
      case '/':  if ( !buf_putc(b, '/') )  return J_ERROR; break;
      case 'b':  if ( !buf_putc(b, '\b') ) return J_ERROR; break;
      case 'f':  if ( !buf_putc(b, '\f') ) return J_ERROR; break;
      case 'n':  if ( !buf_putc(b, '\n') ) return J_ERROR; break;
      case 'r':  if ( !buf_putc(b, '\r') ) return J_ERROR; break;
      case 't':  if ( !buf_putc(b, '\t') ) return J_ERROR; break;
      case 'u':
      { unsigned int code;

        if ( !read_4hex(r, &code) )
          return J_DECLINE;
        if ( code >= 0xD800 && code < 0xDC00 )
        { unsigned int low;

          /* A high surrogate must be followed by \uDC00..\uDFFF. Anything
           * else is a syntax error in the Prolog reader, and a LONE low
           * surrogate reaches it as an out-of-range character code, so both
           * go back rather than being guessed at here. */
          if ( r->pos + 2 > r->len ||
               r->s[r->pos] != '\\' || r->s[r->pos + 1] != 'u' )
            return J_DECLINE;
          r->pos += 2;
          if ( !read_4hex(r, &low) || low < 0xDC00 || low >= 0xE000 )
            return J_DECLINE;
          code = (code - 0xD800) * 0x400 + (low - 0xDC00) + 0x10000;
        } else if ( code >= 0xDC00 && code < 0xE000 )
          return J_DECLINE;
        if ( !buf_put_utf8(b, code) )
          return J_ERROR;
        break;
      }
      default:
        return J_DECLINE;               /* illegal_string_escape */
    }
    run = r->pos;
  }
}

/* Strict JSON number syntax over the text already collected. SWI's reader is
 * laxer: it hands whatever it collected to Prolog's own number parser, which
 * reads 01 as 1 and stops `1.` at the dot. Anything outside the strict grammar
 * is declined so the Prolog reader gives it its own reading. */
static int
strict_number(const unsigned char *s, size_t n)
{ size_t i = 0;

  if ( i < n && s[i] == '-' )
    i++;
  if ( i >= n )
    return FALSE;
  if ( s[i] == '0' )
    i++;
  else if ( s[i] >= '1' && s[i] <= '9' )
  { while ( i < n && s[i] >= '0' && s[i] <= '9' )
      i++;
  } else
    return FALSE;
  if ( i < n && s[i] == '.' )
  { size_t start;

    i++;
    start = i;
    while ( i < n && s[i] >= '0' && s[i] <= '9' )
      i++;
    if ( i == start )
      return FALSE;
  }
  if ( i < n && (s[i] == 'e' || s[i] == 'E') )
  { size_t start;

    i++;
    if ( i < n && (s[i] == '+' || s[i] == '-') )
      i++;
    start = i;
    while ( i < n && s[i] >= '0' && s[i] <= '9' )
      i++;
    if ( i == start )
      return FALSE;
  }
  return i == n;
}

/* The character set SWI's json_read_number/3 collects, so the token this ends
 * at is the token the Prolog reader would end at. */
static int
number_char(unsigned char c)
{ return ( (c >= '0' && c <= '9') ||
           c == '.' || c == '-' || c == '+' || c == 'e' || c == 'E' );
}

/* An integer this many digits wide always fits in int64_t: 10^18 - 1 is below
 * 2^63 - 1, and one more digit is not. */
#define J_SAFE_DIGITS 18

static int
read_number(scan *r, term_t out)
{ const unsigned char *text;
  size_t start = r->pos;
  size_t n;
  int fractional = FALSE;
  term_t tmp;

  while ( r->pos < r->len && number_char(r->s[r->pos]) )
  { unsigned char c = r->s[r->pos];

    if ( c == '.' || c == 'e' || c == 'E' )
      fractional = TRUE;
    r->pos++;
  }
  n = r->pos - start;
  text = r->s + start;
  if ( n == 0 || !strict_number(text, n) )
    return J_DECLINE;

  if ( !fractional )
  { size_t sign = ( text[0] == '-' ) ? 1 : 0;

    if ( n - sign <= J_SAFE_DIGITS )
    { int64_t value = 0;
      size_t i;

      for(i = sign; i < n; i++)
        value = value * 10 + (text[i] - '0');
      if ( sign )
        value = -value;
      return PL_unify_int64(out, value) ? J_OK : J_ERROR;
    }
  } else if ( c_locale )
  { char  small[64];
    char *copy = small;
    char *end;
    double value;
    int ok;

    if ( n + 1 > sizeof(small) && !(copy = malloc(n + 1)) )
    { PL_resource_error("memory");
      return J_ERROR;
    }
    memcpy(copy, text, n);
    copy[n] = '\0';
    errno = 0;
    value = strtod_l(copy, &end, c_locale);
    /* strtod is the same correctly-rounded conversion Prolog's own number
     * parser uses, which is why engine/reader.c leans on it too. ERANGE means
     * the value overflowed or is denormal, and Prolog answers both of those
     * its own way, so they go back. */
    ok = ( errno == 0 && end == copy + n );
    if ( copy != small )
      free(copy);
    if ( ok )
      return PL_unify_float(out, value) ? J_OK : J_ERROR;
  }

  /* An unbounded integer, a float Prolog reads its own way, or any float at
   * all if newlocale() could not give us a C locale to convert in. SWI's own
   * conversion answers all of them, exactly as its json_read_number/3 does. An
   * overflowing exponent leaves an exception, cleared here so the seam sees a
   * plain decline and the Prolog reader raises it with its own context. */
  tmp = PL_new_term_ref();
  if ( !PL_put_term_from_chars(tmp, REP_ISO_LATIN_1, n, (const char *)text) ||
       !PL_is_number(tmp) )
  { if ( PL_exception(0) )
      PL_clear_exception();
    return J_DECLINE;
  }
  return PL_unify(out, tmp) ? J_OK : J_ERROR;
}

static int read_value(scan *r, term_t out, const jopts *o, int depth);

/* One element or one object value, with its scratch term references reclaimed
 * before the next one. Without this a long array leaves a reference per node
 * on the stack; reader.c does the same around build_parsed_form. */
static int
read_into(scan *r, term_t out, const jopts *o, int depth)
{ fid_t frame = PL_open_foreign_frame();
  int rc;

  if ( !frame )
    return J_ERROR;
  rc = read_value(r, out, o, depth);
  PL_close_foreign_frame(frame);
  return rc;
}

/* An object in dict shape. The pairs are collected first because PL_put_dict
 * wants the values in one consecutive term-reference vector and the count is
 * not known until the closing brace. */
static int
read_object_dict(scan *r, term_t out, const jopts *o, int depth)
{ atom_t  fixed_keys[16];
  term_t  fixed_values[16];
  atom_t *keys = fixed_keys;
  term_t *held = fixed_values;
  size_t  size = 16, used = 0, i;
  int     rc = J_DECLINE;
  term_t  values, built;

  for(;;)
  { buf name;
    unsigned char c;
    int sub;

    skip_ws(r);
    if ( r->pos >= r->len )
      goto out;
    c = r->s[r->pos];
    if ( c == '}' && used == 0 )
    { r->pos++;
      break;
    }
    if ( c != '"' )
      goto out;
    r->pos++;
    if ( used == size )
    { size_t want = size * 2;
      atom_t *grown_keys;
      term_t *grown_values;

      grown_keys = ( keys == fixed_keys )
                       ? malloc(want * sizeof(*grown_keys))
                       : realloc(keys, want * sizeof(*grown_keys));
      if ( !grown_keys )
      { PL_resource_error("memory");
        rc = J_ERROR;
        goto out;
      }
      if ( keys == fixed_keys )
        memcpy(grown_keys, fixed_keys, used * sizeof(*grown_keys));
      keys = grown_keys;
      grown_values = ( held == fixed_values )
                         ? malloc(want * sizeof(*grown_values))
                         : realloc(held, want * sizeof(*grown_values));
      if ( !grown_values )
      { PL_resource_error("memory");
        rc = J_ERROR;
        goto out;
      }
      if ( held == fixed_values )
        memcpy(grown_values, fixed_values, used * sizeof(*grown_values));
      held = grown_values;
      size = want;
    }
    buf_init(&name);
    if ( read_string(r, &name) != J_OK )
    { buf_free(&name);
      goto out;
    }
    keys[used] = PL_new_atom_mbchars(REP_UTF8, name.len, name.data);
    buf_free(&name);
    /* A failed atom is a resource error, and handing 0 to PL_put_dict is not
     * an error it reports: an invalid key is a fatal ABI abort there
     * [source: the PL_put_dict footnote in the foreign interface manual]. */
    if ( !keys[used] )
    { PL_resource_error("memory");
      rc = J_ERROR;
      goto out;
    }
    held[used] = PL_new_term_ref();
    used++;
    skip_ws(r);
    if ( r->pos >= r->len || r->s[r->pos] != ':' )
      goto out;
    r->pos++;
    skip_ws(r);
    if ( (sub = read_into(r, held[used - 1], o, depth + 1)) != J_OK )
    { rc = sub;
      goto out;
    }
    skip_ws(r);
    if ( r->pos >= r->len )
      goto out;
    c = r->s[r->pos++];
    if ( c == '}' )
      break;
    if ( c != ',' )
      goto out;
  }

  values = PL_new_term_refs(used);
  built = PL_new_term_ref();
  for(i = 0; i < used; i++)
  { if ( !PL_put_term(values + i, held[i]) )
    { rc = J_ERROR;
      goto out;
    }
  }
  /* The tag json_read_dict/3 gives every object it reads, which is NOT the
   * unbound one dict_create/3 would leave: its default_tag is the atom #, and
   * a C reader that left the tag open disagreed with the Prolog reader on
   * every object [source: SWI-Prolog 10.1 library(json),
   * default_json_dict_options/1]. A duplicate key raises here; that is cleared
   * and declined so every JSON error has exactly one source, the Prolog
   * implementation. */
  /* Compared against TRUE rather than tested for truth: SWI-Prolog through
   * 10.1.3 returned -1 for an invalid tag or key and -2 for a duplicate, both
   * of which a plain `if (PL_put_dict(...))` reads as success
   * [source: swipl-devel src/pl-fli.c at tags V10.1.3 and V10.1.4, and the
   * footnote on PL_put_dict in the foreign interface manual]. */
  if ( PL_put_dict(built, o->tag, used, keys, values) != TRUE )
  { if ( PL_exception(0) )
      PL_clear_exception();
    rc = J_DECLINE;
    goto out;
  }
  rc = PL_unify(out, built) ? J_OK : J_ERROR;

out:
  for(i = 0; i < used; i++)
    PL_unregister_atom(keys[i]);
  if ( keys != fixed_keys )
    free(keys);
  if ( held != fixed_values )
    free(held);
  return rc;
}

/* An object in the classic json([Name=Value|...]) shape, in document order. */
static int
read_object_classic(scan *r, term_t out, const jopts *o, int depth)
{ term_t list = PL_new_term_ref();
  term_t tail = PL_copy_term_ref(list);
  term_t head = PL_new_term_ref();
  term_t built = PL_new_term_ref();
  int first = TRUE;

  for(;;)
  { buf key;
    unsigned char c;
    atom_t name;
    int sub, ok = FALSE;

    skip_ws(r);
    if ( r->pos >= r->len )
      return J_DECLINE;
    c = r->s[r->pos];
    if ( c == '}' && first )
    { r->pos++;
      break;
    }
    first = FALSE;
    if ( c != '"' )
      return J_DECLINE;
    r->pos++;
    buf_init(&key);
    if ( read_string(r, &key) != J_OK )
    { buf_free(&key);
      return J_DECLINE;
    }
    name = PL_new_atom_mbchars(REP_UTF8, key.len, key.data);
    buf_free(&key);
    if ( !name )
    { PL_resource_error("memory");
      return J_ERROR;
    }
    skip_ws(r);
    if ( r->pos >= r->len || r->s[r->pos] != ':' )
    { PL_unregister_atom(name);
      return J_DECLINE;
    }
    r->pos++;
    skip_ws(r);
    PL_put_variable(head);
    if ( !PL_unify_list(tail, head, tail) )
    { PL_unregister_atom(name);
      return J_ERROR;
    }
    { fid_t frame = PL_open_foreign_frame();
      term_t value = PL_new_term_ref();

      if ( !frame )
      { PL_unregister_atom(name);
        return J_ERROR;
      }
      sub = read_value(r, value, o, depth + 1);
      ok = ( sub == J_OK ) &&
           PL_unify_term(head, PL_FUNCTOR, FUNCTOR_equals2,
                         PL_ATOM, name, PL_TERM, value);
      PL_close_foreign_frame(frame);
    }
    PL_unregister_atom(name);
    if ( sub != J_OK )
      return sub;
    if ( !ok )
      return J_ERROR;
    skip_ws(r);
    if ( r->pos >= r->len )
      return J_DECLINE;
    c = r->s[r->pos++];
    if ( c == '}' )
      break;
    if ( c != ',' )
      return J_DECLINE;
  }
  if ( !PL_unify_nil(tail) ||
       !PL_cons_functor(built, FUNCTOR_json1, list) )
    return J_ERROR;
  return PL_unify(out, built) ? J_OK : J_ERROR;
}

static int
read_array(scan *r, term_t out, const jopts *o, int depth)
{ term_t tail = PL_copy_term_ref(out);
  term_t head = PL_new_term_ref();
  int first = TRUE;

  for(;;)
  { unsigned char c;
    int sub;

    skip_ws(r);
    if ( r->pos >= r->len )
      return J_DECLINE;
    c = r->s[r->pos];
    if ( c == ']' && first )
    { r->pos++;
      break;
    }
    first = FALSE;
    PL_put_variable(head);
    if ( !PL_unify_list(tail, head, tail) )
      return J_ERROR;
    if ( (sub = read_into(r, head, o, depth + 1)) != J_OK )
      return sub;
    skip_ws(r);
    if ( r->pos >= r->len )
      return J_DECLINE;
    c = r->s[r->pos++];
    if ( c == ']' )
      break;
    if ( c != ',' )
      return J_DECLINE;
  }
  return PL_unify_nil(tail) ? J_OK : J_ERROR;
}

static int
constant(scan *r, const char *word, size_t n)
{ if ( r->pos + n > r->len || memcmp(r->s + r->pos, word, n) != 0 )
    return FALSE;
  r->pos += n;
  return TRUE;
}

/* out is UNIFIED, never overwritten, so a caller may pass the head of a list
 * cell it has already built. */
static int
read_value(scan *r, term_t out, const jopts *o, int depth)
{ unsigned char c;

  if ( depth > J_MAX_DEPTH || r->pos >= r->len )
    return J_DECLINE;
  c = r->s[r->pos];
  switch(c)
  { case '{':
      r->pos++;
      return o->dicts ? read_object_dict(r, out, o, depth)
                      : read_object_classic(r, out, o, depth);
    case '[':
      r->pos++;
      return read_array(r, out, o, depth);
    case '"':
    { buf text;
      int rc;

      r->pos++;
      buf_init(&text);
      rc = read_string(r, &text);
      if ( rc == J_OK )
        rc = PL_unify_chars(out, PL_STRING | REP_UTF8, text.len, text.data)
                 ? J_OK : J_ERROR;
      buf_free(&text);
      return rc;
    }
    case 't':
      if ( !constant(r, "true", 4) )
        return J_DECLINE;
      return unify_literal(out, &o->t) ? J_OK : J_ERROR;
    case 'f':
      if ( !constant(r, "false", 5) )
        return J_DECLINE;
      return unify_literal(out, &o->f) ? J_OK : J_ERROR;
    case 'n':
      if ( !constant(r, "null", 4) )
        return J_DECLINE;
      return unify_literal(out, &o->n) ? J_OK : J_ERROR;
    default:
      return read_number(r, out);
  }
}

                 /*******************************
                 *            WRITING           *
                 *******************************/

/* json_put_code() from SWI's own json.c, character for character: the seven
 * named escapes, \u00xx for every other control character in lowercase hex,
 * </ written as <\/ so a document is safe inside an HTML script element, and
 * everything else, non-ASCII included, emitted as it stands. */
/* The bytes that need no escape are copied in runs rather than one at a time,
 * which is the whole difference between this and the loop it replaces: a
 * per-character bounds check was 4.75% of the writer's profile.
 *
 * Working on UTF-8 BYTES is equivalent to working on characters, as SWI does,
 * because every byte of a multi-byte sequence is 0x80 or above and so is
 * neither a named escape, nor a control character, nor the '<' or '/' the
 * HTML rule looks at. */
static int
write_json_string(buf *b, const unsigned char *s, size_t n)
{ size_t i, run = 0;

  if ( !buf_putc(b, '"') )
    return FALSE;
  for(i = 0; i < n; i++)
  { unsigned char c = s[i];
    const char *replacement = NULL;
    size_t length = 2;
    char escape[6];

    switch(c)
    { case '"':  replacement = "\\\""; break;
      case '\\': replacement = "\\\\"; break;
      case '\b': replacement = "\\b"; break;
      case '\f': replacement = "\\f"; break;
      case '\n': replacement = "\\n"; break;
      case '\r': replacement = "\\r"; break;
      case '\t': replacement = "\\t"; break;
      case '/':
        if ( i > 0 && s[i - 1] == '<' )
          replacement = "\\/";
        break;
      default:
        if ( c < ' ' )
        { escape[0] = '\\';
          escape[1] = 'u';
          escape[2] = '0';
          escape[3] = '0';
          escape[4] = "0123456789abcdef"[(c >> 4) & 0xF];
          escape[5] = "0123456789abcdef"[c & 0xF];
          replacement = escape;
          length = 6;
        }
        break;
    }
    if ( replacement )
    { if ( !buf_putn(b, s + run, i - run) ||
           !buf_putn(b, replacement, length) )
        return FALSE;
      run = i + 1;
    }
  }
  return buf_putn(b, s + run, n - run) && buf_putc(b, '"');
}

static int
all_ascii(const char *s, size_t n)
{ size_t i;

  for(i = 0; i < n; i++)
  { if ( (unsigned char)s[i] >= 0x80 )
      return FALSE;
  }
  return TRUE;
}

/* Two things keep this off the allocator. BUF_STACK inside a strings mark
 * rather than BUF_MALLOC, because the text is copied into b before this
 * returns and a malloc and free per string and per key put the allocator's
 * lock at 10.6% of the writer's profile. And the ISO-Latin-1 attempt first,
 * because ASCII text needs no conversion at all -- its Latin-1 bytes ARE its
 * UTF-8 bytes and PL_get_nchars hands back a pointer into the atom -- whereas
 * asking for REP_UTF8 converts byte by byte into a fresh buffer whether or not
 * anything changes [source: swipl-devel src/os/pl-text.c, PL_mb_text's
 * ENC_ISO_LATIN_1 to ENC_UTF8 branch and PL_save_text's PL_CHARS_HEAP case]. */
static int
write_text_of(term_t t, buf *b, int flags)
{ int rc;

  PL_STRINGS_MARK();
  { char *s;
    size_t n;

    if ( PL_get_nchars(t, &n, &s, flags | REP_ISO_LATIN_1 | BUF_STACK) &&
         all_ascii(s, n) )
      rc = write_json_string(b, (const unsigned char *)s, n) ? J_OK : J_ERROR;
    else
    { if ( PL_exception(0) )
        PL_clear_exception();
      if ( PL_get_nchars(t, &n, &s, flags | REP_UTF8 | BUF_STACK) )
        rc = write_json_string(b, (const unsigned char *)s, n) ? J_OK : J_ERROR;
      else
        rc = J_DECLINE;
    }
  }
  PL_STRINGS_RELEASE();
  return rc;
}

static int write_value(term_t v, buf *b, const jopts *o, int depth);

typedef struct
{ buf         *out;
  const jopts *options;
  int          depth;
  int          first;
  int          status;
} dict_writer;

static int
write_dict_pair(term_t key, term_t value, void *closure)
{ dict_writer *w = closure;

  if ( !w->first && !buf_putc(w->out, ',') )
  { w->status = J_ERROR;
    return 1;
  }
  w->first = FALSE;
  /* A dict key can be a small integer, and json_write_string/2 REFUSES one:
   * its conversion is CVT_ATOM|CVT_STRING|CVT_LIST and a number is none of
   * those, so `{1: "x"}` from janus is a type error rather than the key "1".
   * Adding CVT_NUMBER here silently made it "1" instead [measured 2026-08-28,
   * the hazard census before and after the seam landed]. */
  w->status = write_text_of(key, w->out, CVT_ATOM | CVT_STRING);
  if ( w->status != J_OK )
    return 1;
  if ( !buf_putc(w->out, ':') )
  { w->status = J_ERROR;
    return 1;
  }
  w->status = write_value(value, w->out, w->options, w->depth + 1);
  return w->status == J_OK ? 0 : 1;
}

/* json_write_object/4 under width(0): a space first unless nothing has been
 * written yet, which is space_if_not_at_left_margin/2 with the indent still
 * zero, then the pairs separated by a bare comma.
 *
 * The keys come out in the standard order of terms, PL_FOR_DICT_SORTED, which
 * is what dict_pairs/3 asks for too; a dict's own storage order is by atom
 * handle and would put them in an order that changes between runs
 * [source: swipl-devel src/pl-dict.c compare_dict_entry and PRED_IMPL
 * "dict_pairs"]. */
static int
write_dict(term_t v, buf *b, const jopts *o, int depth)
{ dict_writer w;

  if ( b->len > 0 && !buf_putc(b, ' ') )
    return J_ERROR;
  if ( !buf_putc(b, '{') )
    return J_ERROR;
  w.out = b;
  w.options = o;
  w.depth = depth;
  w.first = TRUE;
  w.status = J_OK;
  PL_for_dict(v, write_dict_pair, &w, PL_FOR_DICT_SORTED);
  if ( w.status != J_OK )
    return w.status;
  return buf_putc(b, '}') ? J_OK : J_ERROR;
}

static int
write_classic_object(term_t pairs, buf *b, const jopts *o, int depth)
{ term_t tail = PL_copy_term_ref(pairs);
  term_t head = PL_new_term_ref();
  term_t part = PL_new_term_ref();
  functor_t f;
  int first = TRUE;

  if ( b->len > 0 && !buf_putc(b, ' ') )
    return J_ERROR;
  if ( !buf_putc(b, '{') )
    return J_ERROR;
  while ( PL_get_list(tail, head, tail) )
  { int rc;

    if ( !first && !buf_putc(b, ',') )
      return J_ERROR;
    first = FALSE;
    /* json_pair/3 also accepts Name-Value and Name(Value); only the = shape
     * is written here and the rest go back to Prolog. */
    if ( !PL_get_functor(head, &f) || f != FUNCTOR_equals2 )
      return J_DECLINE;
    if ( !PL_get_arg(1, head, part) )
      return J_ERROR;
    if ( (rc = write_text_of(part, b, CVT_ATOM | CVT_STRING)) != J_OK )
      return rc;
    if ( !buf_putc(b, ':') )
      return J_ERROR;
    if ( !PL_get_arg(2, head, part) )
      return J_ERROR;
    if ( (rc = write_value(part, b, o, depth + 1)) != J_OK )
      return rc;
  }
  if ( !PL_get_nil(tail) )
    return J_DECLINE;
  return buf_putc(b, '}') ? J_OK : J_ERROR;
}

/* write_array_hor/4: elements separated by ", " and one space before the
 * closing bracket when the array is not empty. */
static int
write_array(term_t list, buf *b, const jopts *o, int depth)
{ term_t tail = PL_copy_term_ref(list);
  term_t head = PL_new_term_ref();
  int first = TRUE;

  if ( b->len > 0 && !buf_putc(b, ' ') )
    return J_ERROR;
  if ( !buf_putc(b, '[') )
    return J_ERROR;
  while ( PL_get_list(tail, head, tail) )
  { int rc;

    if ( !first && !buf_putn(b, ", ", 2) )
      return J_ERROR;
    first = FALSE;
    if ( (rc = write_value(head, b, o, depth + 1)) != J_OK )
      return rc;
  }
  if ( !first && !buf_putc(b, ' ') )
    return J_ERROR;
  return buf_putc(b, ']') ? J_OK : J_ERROR;
}

static int
write_number(term_t v, buf *b)
{ int rc;

  if ( PL_is_float(v) )
  { double d;

    /* json_write_term writes SWI's own float syntax for a non-finite number,
     * which no JSON reader accepts back; refusing it is the caller's job and
     * the caller's error message. */
    if ( !PL_get_float(v, &d) || !isfinite(d) )
      return J_DECLINE;
  } else if ( !PL_is_integer(v) )
    return J_DECLINE;                   /* a rational; Prolog floats it */
  PL_STRINGS_MARK();
  { char *s;
    size_t n;

    if ( PL_get_nchars(v, &n, &s, CVT_NUMBER | REP_ISO_LATIN_1 | BUF_STACK) )
      rc = buf_putn(b, s, n) ? J_OK : J_ERROR;
    else
      rc = J_DECLINE;
  }
  PL_STRINGS_RELEASE();
  return rc;
}

static int
write_literal_or_text(term_t v, buf *b, const jopts *o, int flags)
{ if ( is_literal(v, &o->t, o->scratch) )
    return buf_putn(b, "true", 4) ? J_OK : J_ERROR;
  if ( is_literal(v, &o->f, o->scratch) )
    return buf_putn(b, "false", 5) ? J_OK : J_ERROR;
  if ( is_literal(v, &o->n, o->scratch) )
    return buf_putn(b, "null", 4) ? J_OK : J_ERROR;
  if ( flags == 0 )
    return J_DECLINE;
  return write_text_of(v, b, flags);
}

/* One PL_term_type call decides the shape, rather than the nine type probes a
 * clause-by-clause transcription of json_write_term/4 would make per leaf.
 * The ORDER that transcription encodes is preserved, because it is what a
 * term MEANS when two readings are possible: json(Pairs) before a dict, a dict
 * before a list, a list before the literals, and a number before all three.
 * Nothing here can read two ways at once, since a dict is never json/1, a
 * number is never a literal, and a literal is an atom or a compound. */
static int
write_value(term_t v, buf *b, const jopts *o, int depth)
{ size_t length;

  if ( depth > J_MAX_DEPTH )
    return J_DECLINE;
  switch( PL_term_type(v) )
  { case PL_DICT:
      return write_dict(v, b, o, depth);
    case PL_NIL:
      return write_array(v, b, o, depth);
    case PL_LIST_PAIR:
      /* A partial, improper or cyclic list is not a JSON array and is not
       * anything else json_write_term/4 accepts either. */
      if ( PL_skip_list(v, 0, &length) != PL_LIST )
        return J_DECLINE;
      return write_array(v, b, o, depth);
    case PL_INTEGER:
    case PL_FLOAT:
    case PL_RATIONAL:
      return write_number(v, b);
    case PL_STRING:
      return write_text_of(v, b, CVT_STRING);
    case PL_ATOM:
      return write_literal_or_text(v, b, o, CVT_ATOM);
    case PL_TERM:
    { functor_t f;

      if ( PL_get_functor(v, &f) && f == FUNCTOR_json1 )
      { term_t pairs = PL_new_term_ref();

        if ( !PL_get_arg(1, v, pairs) )
          return J_ERROR;
        return write_classic_object(pairs, b, o, depth);
      }
      return write_literal_or_text(v, b, o, 0);
    }
    default:                            /* a variable, a blob, anything else */
      return J_DECLINE;
  }
}

                 /*******************************
                 *           THE SEAM           *
                 *******************************/

static foreign_t
c_json_read(term_t text, term_t value, term_t options)
{ char *s;
  size_t len;
  jopts o;
  scan r;
  term_t built;
  int rc;

  if ( options_from(options, &o) != J_OK )
    return FALSE;
  if ( !PL_get_nchars(text, &len, &s,
                      CVT_ATOM | CVT_STRING | CVT_NUMBER | CVT_LIST |
                      REP_UTF8 | BUF_MALLOC) )
    return FALSE;
  r.s = (const unsigned char *)s;
  r.len = len;
  r.pos = 0;
  built = PL_new_term_ref();
  skip_ws(&r);
  rc = read_value(&r, built, &o, 0);
  if ( rc == J_OK )
  { /* Anything but layout after the value is the caller's error to raise, and
     * the two callers disagree about which error that is, so it goes back. */
    skip_ws(&r);
    if ( r.pos != r.len )
      rc = J_DECLINE;
  }
  PL_free(s);
  if ( rc != J_OK )
    return FALSE;
  return PL_unify(value, built);
}

static foreign_t
c_json_write(term_t value, term_t text, term_t options)
{ jopts o;
  buf b;
  int rc;

  if ( options_from(options, &o) != J_OK )
    return FALSE;
  buf_init(&b);
  rc = write_value(value, &b, &o, 0);
  if ( rc == J_OK )
    rc = PL_unify_chars(text, PL_STRING | REP_UTF8, b.len, b.data)
             ? J_OK : J_ERROR;
  buf_free(&b);
  return rc == J_OK;
}

install_t
install_json_codec(void)
{ FUNCTOR_json1 = PL_new_functor(PL_new_atom("json"), 1);
  FUNCTOR_equals2 = PL_new_functor(PL_new_atom("="), 2);
  ATOM_true = PL_new_atom("true");
  c_locale = newlocale(LC_ALL_MASK, "C", (locale_t)0);

  PL_register_foreign_in_module("json_codec", "metta_c_json_read", 3,
                                c_json_read, 0);
  PL_register_foreign_in_module("json_codec", "metta_c_json_write", 3,
                                c_json_write, 0);
}
