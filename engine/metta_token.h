/* Purpose: the lexical rules the C reader (engine/reader.c) and the C writer
 *   (engine/writer.c) must agree on, in one place: how a UTF-8 byte run
 *   decodes and re-encodes, where a token ends, and whether a whole token is
 *   a number literal. engine/parser.pl's metta_token_boundary/2 and its
 *   shipped number grammar remain the specification; this header is their
 *   single C transcription, so a change to the language's lexis cannot land
 *   in the reader and not in the writer.
 * Assumes: callers hand these functions UTF-8 bytes, which is what
 *   PL_get_nchars(..., REP_UTF8) and this engine's own atom transcription
 *   produce, and read the result as Unicode codepoints.
 * Guarantees:
 *   - metta_cp_layout/1 answers for exactly the 25 Unicode White_Space
 *     codepoints metta_token_boundary(_, layout) lists, and
 *     metta_cp_boundary/1 additionally for '(' ')' and ';'
 *     [tested: parser_unicode_layout; reader_c and writer_c differentials;
 *     commit=a9663314a626d6227ef948658b5de769992c0afa].
 *   - metta_token_is_number/3 answers for exactly the tokens dcg/basics'
 *     number//1 followed by parser.pl's number_ends//2 accepts whole, and
 *     sets *fracexp when a fraction or an exponent occurred, which is what
 *     decides integer against float in number_codes/2
 *     [tested: reader_c:number_conversion_agrees_with_the_prolog_reader;
 *     commit=a9663314a626d6227ef948658b5de769992c0afa].
 * Fails when: a custom reader token is registered. Both callers are gated on
 *   metta_reader_mode(shipped) and never consult this header while a custom
 *   class could change what a token means.
 * Open Obligations:
 *   To Do: None
 *   Hacks: None
 *   Future Enhancements: None
 */

#ifndef METTA_TOKEN_H_INCLUDED
#define METTA_TOKEN_H_INCLUDED

#include <stddef.h>

/* One codepoint at `s`, with `rem` bytes available; *sz is its byte width.
 * A truncated or invalid sequence yields the lead byte itself in one byte,
 * which cannot occur for REP_UTF8 output and keeps the scan advancing. */
static inline unsigned int
metta_utf8_decode(const unsigned char *s, size_t rem, int *sz)
{ unsigned char b = s[0];

  if ( b < 0x80 )
  { *sz = 1; return b;
  }
  if ( (b & 0xE0) == 0xC0 && rem >= 2 )
  { *sz = 2; return ((unsigned)(b & 0x1F) << 6) | (s[1] & 0x3F);
  }
  if ( (b & 0xF0) == 0xE0 && rem >= 3 )
  { *sz = 3; return ((unsigned)(b & 0x0F) << 12) | ((unsigned)(s[1] & 0x3F) << 6)
                  | (s[2] & 0x3F);
  }
  if ( (b & 0xF8) == 0xF0 && rem >= 4 )
  { *sz = 4; return ((unsigned)(b & 0x07) << 18) | ((unsigned)(s[1] & 0x3F) << 12)
                  | ((unsigned)(s[2] & 0x3F) << 6) | (s[3] & 0x3F);
  }
  *sz = 1;
  return b;
}

/* The inverse, into at least four bytes; answers how many it wrote. */
static inline int
metta_utf8_put(unsigned char *out, unsigned int cp)
{ if ( cp < 0x80 )
  { out[0] = (unsigned char)cp;
    return 1;
  }
  if ( cp < 0x800 )
  { out[0] = (unsigned char)(0xC0 | (cp >> 6));
    out[1] = (unsigned char)(0x80 | (cp & 0x3F));
    return 2;
  }
  if ( cp < 0x10000 )
  { out[0] = (unsigned char)(0xE0 | (cp >> 12));
    out[1] = (unsigned char)(0x80 | ((cp >> 6) & 0x3F));
    out[2] = (unsigned char)(0x80 | (cp & 0x3F));
    return 3;
  }
  out[0] = (unsigned char)(0xF0 | (cp >> 18));
  out[1] = (unsigned char)(0x80 | ((cp >> 12) & 0x3F));
  out[2] = (unsigned char)(0x80 | ((cp >> 6) & 0x3F));
  out[3] = (unsigned char)(0x80 | (cp & 0x3F));
  return 4;
}

/* The 25 White_Space codepoints plus nothing else, metta_token_boundary's
 * layout rows verbatim. */
static inline int
metta_cp_layout(unsigned int cp)
{ if ( cp == 0x20 || cp == 0x09 || cp == 0x0A || cp == 0x0D )
    return 1;
  switch ( cp )
  { case 0x0B: case 0x0C: case 0x85: case 0xA0: case 0x1680:
    case 0x2028: case 0x2029: case 0x202F: case 0x205F: case 0x3000:
      return 1;
    default:
      return cp >= 0x2000 && cp <= 0x200A;
  }
}

static inline int
metta_cp_boundary(unsigned int cp)
{ return cp == '(' || cp == ')' || cp == ';' || metta_cp_layout(cp);
}

static inline int
metta_is_ascii_digit(unsigned char c)
{ return c >= '0' && c <= '9';
}

/* dcg/basics number//1 followed by number_ends//2, as an anchored whole-token
 * match: [+-]? digits ('.' digits)? ([eE] [+-]? digits)?.  *fracexp says
 * whether a fraction or exponent occurred, which is what decides integer
 * against float in number_codes/2.  The digit class is ASCII only, which is
 * not an approximation of code_type(C, digit): that predicate answers for
 * codepoints 48 through 57 and no others, under en_AU.UTF-8 and under
 * LC_ALL=C alike [measured 2026-08-28 by enumerating 0..0x10FFFF, where the
 * same enumeration reports 21 and 6 codepoints for code_type(C, space), so
 * the locale dependence parser.pl records for whitespace does not reach the
 * digits]. */
static inline int
metta_token_is_number(const unsigned char *t, size_t n, int *fracexp)
{ size_t i = 0;

  *fracexp = 0;
  if ( i < n && (t[i] == '+' || t[i] == '-') )
    i++;
  if ( i >= n || !metta_is_ascii_digit(t[i]) )
    return 0;
  while ( i < n && metta_is_ascii_digit(t[i]) )
    i++;
  if ( i < n && t[i] == '.' )
  { if ( i + 1 < n && metta_is_ascii_digit(t[i + 1]) )
    { *fracexp = 1;
      i += 2;
      while ( i < n && metta_is_ascii_digit(t[i]) )
        i++;
    } else
      return 0;
  }
  if ( i < n && (t[i] == 'e' || t[i] == 'E') )
  { size_t j = i + 1;
    if ( j < n && (t[j] == '+' || t[j] == '-') )
      j++;
    if ( j < n && metta_is_ascii_digit(t[j]) )
    { *fracexp = 1;
      j++;
      while ( j < n && metta_is_ascii_digit(t[j]) )
        j++;
      i = j;
    } else
      return 0;
  }
  return i == n;
}

#endif /*METTA_TOKEN_H_INCLUDED*/
