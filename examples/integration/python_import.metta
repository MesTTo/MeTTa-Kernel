!(import! &self "_fixtures/python_import_file.py")

!(test (repr (py-call (python_import_file.greet "MeTTa User"))) "Hello, MeTTa User from Python!")
!(test (py-call (python_import_file.add 10 20)) 30)
