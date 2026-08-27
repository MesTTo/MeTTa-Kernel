;Simple import without build step. The repository is built locally first,
;so the suite acquires a real git checkout without reaching a network:
;every push used to clone github here, and repos/ is gitignored, so the
;clone happened every run.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file "./examples/ch20-extending-the-engine/20-04-modules-and-the-catalog/_fixtures/git_fixture.pl"
                                    (git_fixture_url))

!(git-import! (git_fixture_url "./repos"))

!(import! &self (library metta_fixture_lib fixture))

!(test (fixture-answer 14) 42)
