!(import! &self (library lib_he))

!(test (if-error (catch (import! &self _fixtures/imports/import_error_broken))
                 Error
                 NoError)
       Error)

!(test (if-error (catch (import! &self _fixtures/imports/definitely_missing_import))
                 Error
                 NoError)
       Error)
