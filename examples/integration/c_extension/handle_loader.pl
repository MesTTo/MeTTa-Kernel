% Loads the opaque-handle C extension. Same rule as loader.pl beside it:
% use_foreign_library/2 wants an absolute path or a foreign(Name) alias.
:- use_module(library(shlib)).
:- initialization(( absolute_file_name('examples/integration/c_extension/handle.so', Abs),
                    use_foreign_library(Abs, install_handle) )).
