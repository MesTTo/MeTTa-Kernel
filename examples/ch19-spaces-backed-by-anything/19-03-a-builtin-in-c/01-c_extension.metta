;A C foreign predicate, called from MeTTa with nothing in between. See the
;README beside this file for the build line, and EXTENDING.md section 3 for the
;calling convention and what it obliges you to do.
;
;The example skips itself when cbump.so has not been built, because a C
;compiler is not one of the engine's requirements. It says so when it skips
;rather than passing quietly.

!(import! &self (library lib_import))
!(import! &self (library lib_file))

;The import has to be its own runnable. A runnable is compiled just before it
;runs, so a call written in the SAME runnable as its import compiles while the
;name is still unregistered and stays unreduced: (c-bump 41) came back as the
;expression (c-bump 41) rather than 42. By the time the next runnable is
;compiled the registration has happened and the call compiles direct.
!(if (file-exists "./examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/cbump.so")
     (import_prolog_functions_from_file
        "./examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/loader.pl" (c-bump))
     (println! "SKIPPED c_extension: cbump.so is not built, see the README beside this file"))

!(if (file-exists "./examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/cbump.so")
     (test (eval (c-bump 41)) 42)
     True)
