#!/usr/bin/env bash
set -e

realcd() {
    builtin cd "$1"
}

root="$(realcd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec 5> "$root/bootstrap.log"
run() {
    echo "====== Exec \"$*\"" >&5
    set +e
    out=`"$@" 2>&1`
    ret=$?
    set -e
    echo "$out" >&5
    if [ $ret -ne 0 ]; then
        echo "Error during command $*:"
        echo "$out"
        echo
        echo "See bootstrap.log for full installation log"
        exit 1
    fi
    echo "====== Done" >&5
}


if [[ "$OSTYPE" == "linux-gnu" ]]; then
    DEPS="build-essential wget git cmake ninja-build python3 virtualenv libtinfo-dev zlib1g-dev"
    echo "[+] Installing dependencies: $DEPS"
    run sudo apt-get install --assume-yes $DEPS
    jobs=`nproc`
    [ "$jobs" -eq 0 ] && jobs=1
elif [[ "$OSTYPE" == "darwin"* ]]; then
    if ! [ -x "$(command -v brew)" ]; then
        # Install xcode cli: xcode-select --install
        echo "[+] Installing homebrew"
        /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    fi
    DEPS="wget git cmake ninja python3"
    echo "[+] Installing dependencies: $DEPS"
    brew install $DEPS || true
    pip3 install virtualenv || true
    jobs=`sysctl -n hw.ncpu`
    [ "$jobs" -eq 0 ] && jobs=1
fi


pathsrc="$root/lib/src"
pathbuild="$root/lib/build"
pathinstall="$root/lib/install"

versionllvm=5.0.0
llvm=llvm-$versionllvm
cfe=cfe-$versionllvm
versionllvmlite=0.21.0.dev
commitllvmlite=4570b71
llvmlite=llvmlite-$versionllvmlite
frontend=frontend
optalias=myopt

bindisturl="http://koenk.net/"
llvmbindist="bindist-${llvm}-${OSTYPE}.tar.gz"

mkdir -p "$pathsrc" "$pathbuild" "$pathinstall"

# get LLVM core
echo "[+] Downloading LLVM core"
if [ ! -d "$pathsrc/$llvm" ]; then
    realcd "$pathsrc"
    run wget http://releases.llvm.org/$versionllvm/$llvm.src.tar.xz
    run tar -xf $llvm.src.tar.xz
    run mv $llvm.src $llvm
    run rm $llvm.src.tar.xz
fi

# get Clang
echo "[+] Downloading Clang"
if [ ! -d "$pathsrc/$llvm/tools/clang" ]; then
    realcd "$pathsrc"
    run wget http://releases.llvm.org/$versionllvm/$cfe.src.tar.xz
    run tar -xf $cfe.src.tar.xz
    run mv $cfe.src $llvm/tools/clang
    run rm $cfe.src.tar.xz
fi

# get llvmlite
echo "[+] Downloading llvmlite"
if [ ! -d "$pathsrc/$llvmlite" ]; then
    realcd "$pathsrc"
    run git clone https://github.com/numba/llvmlite.git $llvmlite
    realcd "$llvmlite"
    run git checkout --detach $commitllvmlite
    run patch -p1 < "$root/support/${llvmlite}-spaces.patch"
fi

# build & install LLVM
echo "[+] Installing LLVM"
if [[ "$OSTYPE" == "linux-gnu" ]]; then
    # Try using the prebuilt LLVM which saves 1-2 hours of compiling

    if [ ! -f "$pathinstall/bin/clang" ]; then
        realcd "$pathinstall"
        if [ ! -f "$pathinstall/$llvmbindist" ]; then
            echo "[+] Fetching LLVM bindist"
            run wget "$bindisturl/$llvmbindist"
        fi
        echo "[+] Unpacking LLVM bindist"
        run tar xf "$llvmbindist"

        # Test to see if the clang is compatible with this system
        if ! echo "" | bin/clang -xc -S -o- - 2>&5 >/dev/null; then
            echo "[+] LLVM bindist not compatible with this system, removing "
            echo "    and falling back to building LLVM"
            realcd ..
            rm -rf "$pathinstall"
            mkdir -p "$pathinstall"
        fi
    fi
fi

if [ ! -f "$pathinstall/bin/clang" ]; then
    echo "[+] Building LLVM (takes a long time and a lot of system resources)"
    if [ ! -d $pathbuild/$llvm ]; then
        mkdir -p "$pathbuild/$llvm"
        realcd "$pathbuild/$llvm"
        if [[ "$OSTYPE" == "darwin"* ]]; then
        mkdir -p "$pathinstall/include"
        ln -s "$(dirname "$(xcrun -find clang)")/../include/c++" "$pathinstall/include/c++"
        fi
        [ -f rules.ninja ] || run cmake -G Ninja \
            -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=On \
            -DCMAKE_INSTALL_PREFIX="$pathinstall" "$pathsrc/$llvm"
        cmake --build .
    fi
    echo "[+] Installing LLVM"
    realcd "$pathbuild/$llvm"
    run cmake --build . --target install

    # install FileCheck binary from LLVM - it's normally only used internally
    echo "[+] Installing FileCheck"
    if [ ! -f "$pathinstall/bin/FileCheck" ]; then
        cp "$pathbuild/$llvm/bin/FileCheck" "$pathinstall/bin/FileCheck"
    fi
fi

# create python3 virtualenv
echo "[+] Creating virtualenv"
if [ ! -f "$pathinstall/bin/python" ]; then
    run virtualenv --python="$(which python3)" --prompt="(coco) " --no-wheel \
        "$pathinstall"

    # patch pip to fix shebang without spaces issue
    realcd "$pathinstall/bin"
    for pip in pip pip3 pip3.5
    do
        mv $pip $pip.old
        echo "#!/usr/bin/env bash" > $pip
        echo "exec \"$pathinstall/bin/python3\" \"$pathinstall/bin/$pip.old\" \"\$@\"" >> $pip
        run chmod +x $pip
    done
fi

# load virtualenv to have python/pip available below
source "$pathinstall/bin/activate"

# install PLY
echo "[+] Installing PLY"
if ! python -c "import ply" 2>/dev/null; then
    run pip install ply
fi

# install termcolor
echo "[+] Installing termcolor"
if ! python -c "import termcolor" 2>/dev/null; then
    run pip install termcolor
fi

# build & install llvmlite
echo "[+] Building and installing llvmlite"
if ! python -c "import llvmlite" 2>/dev/null; then
    realcd "$pathsrc/$llvmlite"
    run python setup.py build
    run python runtests.py
    run python setup.py install
fi

# install our frontend as a binary
echo "[+] Installing frontend"
if [ ! -f "$pathinstall/bin/$frontend" ]; then
    cat <<- EOF > "$pathinstall/bin/$frontend"
#!/usr/bin/env bash
exec "$pathinstall/bin/python" "$root/frontend/main.py" "\$@"
EOF
    run chmod +x "$pathinstall/bin/$frontend"
fi

# install an alias to opt
echo "[+] Installing opt alias"
if [ ! -f "$pathinstall/bin/$optalias" ]; then
    cat <<- EOF > "$pathinstall/bin/$optalias"
#!/usr/bin/env bash
exec "$pathinstall/bin/opt" -load "$root/llvm-passes/obj/libllvm-passes.so" -S "\$@"
EOF
    run chmod +x "$pathinstall/bin/$optalias"
fi

# touch stamp for build script
touch "$root/lib/.bootstrapped"

echo "All done! Source the virtualenv script to use the installed tools:"
echo "  $ source \"$root/shrc\""
echo "To get out of the virtualenv, run:"
echo "  $ deactivate"
