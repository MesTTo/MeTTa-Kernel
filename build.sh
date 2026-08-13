# Purpose: build the optional native backends. mork_ffi ships in this
#   tree; its MORK and PathMap path dependencies live beside the
#   repository and are cloned at the validated revisions when absent.
#   faiss_ffi is cloned and built from upstream.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

if [ ! -d ../MORK ]; then
  git clone https://github.com/trueagi-io/MORK ../MORK
  git -C ../MORK checkout dd224fd7ced92ca9cfdacd399398dabb609e8faa
fi
if [ ! -d ../PathMap ]; then
  git clone https://github.com/Adam-Vandervorst/PathMap ../PathMap
  git -C ../PathMap checkout 4c84a8b40c7b6a7ecb54e009a70f0c5abbc1b60f
fi

cd ./mork_ffi
sh build.sh

cd ..

git clone https://github.com/patham9/faiss_ffi
cd ./faiss_ffi
git pull
sh build.sh
