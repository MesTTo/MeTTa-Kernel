% Loads the compiled C extension. use_foreign_library/2 wants an absolute path
% or a foreign(Name) alias; a path relative to the working directory resolves
% but SWI deprecates it and warns on every load.
:- use_module(library(shlib)).
:- initialization(( absolute_file_name('examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/cbump.so', Abs),
                    use_foreign_library(Abs, install_cbump) )).
