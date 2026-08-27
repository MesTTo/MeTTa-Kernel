/* Purpose: an opaque native handle that reaches MeTTa as an ordinary value,
 *   so a C or Rust structure can be held and used without serialising it.
 * Assumes:
 *   - PL_BLOB_NOCOPY means SWI keeps the pointer given to PL_unify_blob, so
 *     the pointer must own heap memory rather than name a local
 *     [source: SWI-Prolog 10.1 Reference Manual, PL_register_blob_type].
 * Guarantees:
 *   - a handle answers 'Grounded' to get-metatype, compares by identity, and
 *     prints through this file's write callback [tested 2026-08-16:
 *     examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/02-handle.metta].
 *   - state behind a handle survives across MeTTa calls
 *     [tested 2026-08-16: handle.metta's bump sequence].
 * Owns:
 *   - each handle's malloc'ed buffer, released by release_vector when SWI
 *     garbage-collects the blob.
 * Open Obligations:
 *   To Do: None
 *   Hacks: None
 *   Future Enhancements: None
 */

#include <SWI-Prolog.h>
#include <SWI-Stream.h>
#include <stdlib.h>

typedef struct
{ size_t length;
  long *items;
} vector_t;

static int write_vector(IOSTREAM *s, atom_t a, int flags)
{ vector_t *v = PL_blob_data(a, NULL, NULL);
  (void)flags;
  /* Deliberately not the contents: a handle prints as what it IS, and the
     whole point is that its contents never become text. */
  Sfprintf(s, "<vector %zu>", v->length);
  return TRUE;
}

static int release_vector(atom_t a)
{ vector_t *v = PL_blob_data(a, NULL, NULL);
  free(v->items);
  free(v);
  return TRUE;
}

static PL_blob_t vector_blob =
{ PL_BLOB_MAGIC, PL_BLOB_NOCOPY, "vector",
  release_vector, NULL, write_vector, NULL
};

static int get_vector(term_t t, vector_t **v)
{ PL_blob_t *type;
  size_t len;
  if ( !PL_get_blob(t, (void **)v, &len, &type) || type != &vector_blob )
    return PL_type_error("vector", t);
  return TRUE;
}

/* vector-new(+Length, -Handle): a native vector of 0..Length-1. */
static foreign_t pl_vector_new(term_t length, term_t out)
{ int64_t n;
  vector_t *v;
  size_t i;
  if ( !PL_get_int64_ex(length, &n) ) return FALSE;
  if ( n < 0 ) return PL_domain_error("non_negative_integer", length);
  if ( !(v = malloc(sizeof(*v))) ) return PL_resource_error("memory");
  v->length = (size_t)n;
  if ( !(v->items = malloc(sizeof(long) * (v->length ? v->length : 1))) )
  { free(v);
    return PL_resource_error("memory");
  }
  for (i = 0; i < v->length; i++) v->items[i] = (long)i;
  return PL_unify_blob(out, v, sizeof(*v), &vector_blob);
}

/* vector-nth(+Handle, +Index, -Value): one element, without touching the rest. */
static foreign_t pl_vector_nth(term_t handle, term_t index, term_t out)
{ vector_t *v;
  int64_t i;
  if ( !get_vector(handle, &v) ) return FALSE;
  if ( !PL_get_int64_ex(index, &i) ) return FALSE;
  if ( i < 0 || (size_t)i >= v->length )
    return PL_domain_error("vector_index", index);
  return PL_unify_int64(out, v->items[i]);
}

/* vector-bump(+Handle, +Index, -Value): mutate through the handle, so a
   caller can see that the state is the native one and not a copy. */
static foreign_t pl_vector_bump(term_t handle, term_t index, term_t out)
{ vector_t *v;
  int64_t i;
  if ( !get_vector(handle, &v) ) return FALSE;
  if ( !PL_get_int64_ex(index, &i) ) return FALSE;
  if ( i < 0 || (size_t)i >= v->length )
    return PL_domain_error("vector_index", index);
  v->items[i]++;
  return PL_unify_int64(out, v->items[i]);
}

/* vector-length(+Handle, -Length). */
static foreign_t pl_vector_length(term_t handle, term_t out)
{ vector_t *v;
  if ( !get_vector(handle, &v) ) return FALSE;
  return PL_unify_int64(out, (int64_t)v->length);
}

install_t install_handle(void)
{ PL_register_foreign("vector-new", 2, pl_vector_new, 0);
  PL_register_foreign("vector-nth", 3, pl_vector_nth, 0);
  PL_register_foreign("vector-bump", 3, pl_vector_bump, 0);
  PL_register_foreign("vector-length", 2, pl_vector_length, 0);
}
