/* Purpose: a space whose atoms live in C, the smallest native instance of
 *   the foreign-space seam: a mutex-guarded store of engine-written text
 *   lines behind four foreign predicates.
 * Assumes:
 *   - atoms cross this boundary as the engine's own text (the .pl beside
 *     this file calls swrite/2 and sread/2), so equality here is exact
 *     text equality and unification stays the engine's job
 *   - callers arrive from any engine thread (hyperpose workers, Python
 *     worker threads), so every entry point takes the store mutex
 * Guarantees:
 *   - an enumeration answers the store as it stood when it began: each
 *     open enumeration walks its own snapshot, so a concurrent add or
 *     remove never skips or doubles a line it did not touch
 *     [tested: examples/ch19-spaces-backed-by-anything/19-02-a-space-in-c/01-c_space.metta and
 *     extensions/python/tests/ch19_spaces_backed_by_anything/test_c_space.py, the threaded block]
 *   - removal takes ONE exact-text occurrence, the oldest, and answers 1
 *     or 0, so the store is honestly a multiset under subtraction
 * Owns:
 *   - the store's strdup'ed lines, freed by removal and clear; each
 *     snapshot's copies, freed when its enumeration completes, fails or
 *     is pruned
 * Open Obligations:
 *   To Do: None
 *   Hacks: None
 *   Future Enhancements: None
 */

#include <SWI-Prolog.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static pthread_mutex_t store_lock = PTHREAD_MUTEX_INITIALIZER;
static char **lines = NULL;
static size_t line_count = 0;
static size_t line_capacity = 0;

/* Grow under the lock; zero means the allocation failed and the caller
   raises resource_error(memory) with the store unchanged. */
static int ensure_capacity(void)
{ if ( line_count < line_capacity )
    return 1;
  { size_t grown = line_capacity ? line_capacity * 2 : 64;
    char **resized = realloc(lines, grown * sizeof(char *));
    if ( !resized )
      return 0;
    lines = resized;
    line_capacity = grown;
    return 1;
  }
}

static foreign_t pl_cstore_add(term_t text)
{ char *s;
  char *copy;
  if ( !PL_get_chars(text, &s,
                     CVT_ATOM|CVT_STRING|BUF_STACK|REP_UTF8|CVT_EXCEPTION) )
    return FALSE;
  copy = strdup(s);
  if ( !copy )
    return PL_resource_error("memory");
  pthread_mutex_lock(&store_lock);
  if ( !ensure_capacity() )
  { pthread_mutex_unlock(&store_lock);
    free(copy);
    return PL_resource_error("memory");
  }
  lines[line_count++] = copy;
  pthread_mutex_unlock(&store_lock);
  return TRUE;
}

/* Remove the FIRST line equal to the text and answer 1 or 0, which is what
   makes the store a multiset the way remove-atom expects: three identical
   lines take three removals. Insertion order is preserved by shifting the
   tail down, so the store keeps answering enumerations in the order it was
   written and the removal takes the oldest copy, as retract/1 does. */
static foreign_t pl_cstore_remove_text(term_t text, term_t removed)
{ char *s;
  int64_t gone = 0;
  size_t i;
  if ( !PL_get_chars(text, &s,
                     CVT_ATOM|CVT_STRING|BUF_STACK|REP_UTF8|CVT_EXCEPTION) )
    return FALSE;
  pthread_mutex_lock(&store_lock);
  for ( i = 0; i < line_count; i++ )
  { if ( strcmp(lines[i], s) == 0 )
    { free(lines[i]);
      memmove(&lines[i], &lines[i+1], (line_count - i - 1) * sizeof(char *));
      line_count--;
      gone = 1;
      break;
    }
  }
  pthread_mutex_unlock(&store_lock);
  return PL_unify_int64(removed, gone);
}

static foreign_t pl_cstore_clear(void)
{ size_t i;
  pthread_mutex_lock(&store_lock);
  for ( i = 0; i < line_count; i++ )
    free(lines[i]);
  line_count = 0;
  pthread_mutex_unlock(&store_lock);
  return TRUE;
}

/* One open enumeration: its own copies of the lines, so the store's
   mutex is held only while the snapshot is taken and a concurrent write
   cannot tear the walk. */
typedef struct
{ char **items;
  size_t count;
  size_t next;
} snapshot_t;

static void free_snapshot(snapshot_t *snap)
{ size_t i;
  for ( i = 0; i < snap->count; i++ )
    free(snap->items[i]);
  free(snap->items);
  free(snap);
}

static foreign_t pl_cstore_text(term_t text, control_t handle)
{ snapshot_t *snap;
  switch ( PL_foreign_control(handle) )
  { case PL_FIRST_CALL:
    { size_t i;
      pthread_mutex_lock(&store_lock);
      snap = malloc(sizeof(*snap));
      if ( !snap )
      { pthread_mutex_unlock(&store_lock);
        return PL_resource_error("memory");
      }
      snap->count = line_count;
      snap->next = 0;
      snap->items = malloc((line_count ? line_count : 1) * sizeof(char *));
      if ( !snap->items )
      { pthread_mutex_unlock(&store_lock);
        free(snap);
        return PL_resource_error("memory");
      }
      for ( i = 0; i < line_count; i++ )
      { snap->items[i] = strdup(lines[i]);
        if ( !snap->items[i] )
        { snap->count = i;
          pthread_mutex_unlock(&store_lock);
          free_snapshot(snap);
          return PL_resource_error("memory");
        }
      }
      pthread_mutex_unlock(&store_lock);
      break;
    }
    case PL_REDO:
      snap = PL_foreign_context_address(handle);
      break;
    case PL_PRUNED:
      snap = PL_foreign_context_address(handle);
      free_snapshot(snap);
      return TRUE;
    default:
      return FALSE;
  }
  while ( snap->next < snap->count )
  { const char *line = snap->items[snap->next++];
    if ( PL_unify_chars(text, PL_STRING|REP_UTF8, (size_t)-1, line) )
    { if ( snap->next < snap->count )
        PL_retry_address(snap);
      free_snapshot(snap);
      return TRUE;
    }
  }
  free_snapshot(snap);
  return FALSE;
}

install_t install_cstore(void)
{ PL_register_foreign("cstore_add", 1, pl_cstore_add, 0);
  PL_register_foreign("cstore_remove_text", 2, pl_cstore_remove_text, 0);
  PL_register_foreign("cstore_clear", 0, pl_cstore_clear, 0);
  PL_register_foreign("cstore_text", 1, pl_cstore_text,
                      PL_FA_NONDETERMINISTIC);
}
