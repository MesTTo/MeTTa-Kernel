#include <SWI-Prolog.h>

/* c-bump(+X, -Y) : Y is X + 1, following the compiled calling convention
   PeTTa uses, inputs first and one output last. */
static foreign_t pl_c_bump(term_t x, term_t y)
{ int64_t v;
  if ( !PL_get_int64_ex(x, &v) ) return FALSE;
  return PL_unify_int64(y, v + 1);
}

install_t install_cbump(void)
{ PL_register_foreign("c-bump", 2, pl_c_bump, 0);
}
