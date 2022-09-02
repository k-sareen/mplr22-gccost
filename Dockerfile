FROM ubuntu:18.04

ENV HOME /root
WORKDIR /root
SHELL ["/bin/bash", "-c"]

# Install libraries
RUN apt-get update && apt-get upgrade -y
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install -y wget curl python3 build-essential
RUN apt-get install -y openjdk-11-jdk
RUN apt-get install -y autoconf libx11-dev libxext-dev libxrender-dev libxrandr-dev libxtst-dev libxt-dev libcups2-dev libfontconfig1-dev libasound2-dev
RUN apt-get install -y clang git zip libpfm4 libpfm4-dev gcc-multilib g++-multilib python3-pip
RUN apt-get install -y vim tmux time
RUN apt-get install -y libgmp-dev ghostscript ninja-build
RUN apt-get install -y cmake dos2unix bsdmainutils libtool

# Install rust
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN rustup install 1.59
RUN rustup default 1.59

# Install running-ng
RUN pip3 install running-ng
RUN pip3 install numpy seaborn pandas matplotlib

# DaCapo Chopin benchmark
RUN mkdir -p /root/dacapo/dacapo-evaluation-git-f480064 /root/dacapo/dacapo-evaluation-git-6804496f
WORKDIR /root/dacapo
RUN wget -O /root/dacapo/dacapo-evaluation-git-6804496f.jar "https://cloudstor.aarnet.edu.au/plus/s/TMDilWlR5Xe1cg3/download"
RUN wget -O /root/dacapo/dacapo-evaluation-git-f480064.jar  "https://cloudstor.aarnet.edu.au/plus/s/Ik3qCiTX8FZlNIL/download"

WORKDIR /root/dacapo/dacapo-evaluation-git-6804496f
RUN wget -O dacapo-evaluation-git-6804496f.zip "https://cloudstor.aarnet.edu.au/plus/s/X7ybA15mrycoSAy/download"
RUN unzip dacapo-evaluation-git-6804496f.zip
RUN mv dacapo-evaluation-git-6804496f/* .

WORKDIR /root/dacapo/dacapo-evaluation-git-f480064
RUN wget -O dacapo-evaluation-git-f480064.zip  "https://cloudstor.aarnet.edu.au/plus/s/1RXUzrh3EENq4Sq/download"
RUN unzip dacapo-evaluation-git-f480064.zip
RUN mv usr/share/benchmarks/dacapo/dacapo-evaluation-git-f480064/* .

# C benchmarks. Note we don't provide the SPEC benchmarks as you require a license to run them
COPY ./ql-benchmarks /root/ql-benchmarks
WORKDIR /root/ql-benchmarks
RUN mkdir -p allocators
RUN git clone https://github.com/daanx/mimalloc-bench
WORKDIR ./mimalloc-bench
RUN git checkout 5126dc8d19d35364513ad5fde8fa964eb722fbdd
# Z3 build
RUN git clone https://github.com/Z3Prover/z3
WORKDIR ./z3
RUN git checkout 545341e69999ceca585f3dacc08d5c6b6f096edc
RUN mkdir build
WORKDIR build
RUN cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release ../
RUN make -j2
RUN cp z3 /root/ql-benchmarks
WORKDIR /root/ql-benchmarks/mimalloc-bench
# mimalloc benchmarks
RUN tac build-bench-env.sh | sed "1,13d" | tac | tee build.sh
RUN chmod +x build.sh
RUN ./build.sh bench redis lean
WORKDIR out/bench
RUN cp alloc-test barnes cache-scratch cfrac espresso glibc-simple glibc-thread larson sh6bench sh8bench xmalloc-test -t /root/ql-benchmarks

# Copy and build probes
COPY ./probes.zip /root/
RUN cd /root && unzip probes.zip
RUN cd /root/probes && make all JDK=/usr/lib/jvm/java-11-openjdk-amd64 CFLAGS=-Wno-error=stringop-overflow JAVAC=/usr/lib/jvm/java-11-openjdk-amd64/bin/javac

WORKDIR /root
RUN git clone -b jdk-11.0.15+8-mmtk https://github.com/mmtk/openjdk.git
WORKDIR /root/openjdk
RUN git checkout ca90b43f0f5
RUN sh configure --disable-warnings-as-errors --with-debug-level=release

COPY ./bench /root/bench
RUN mkdir -p /root/bench/build
RUN mkdir -p /root/bench/results
RUN mkdir -p /root/bench/gc-proximity

# 1. GC space overhead
RUN mkdir -p /root/gc-space-overhead
WORKDIR /root/gc-space-overhead
RUN git clone -b mplr22-gc-space-overhead-tc https://github.com/k-sareen/mmtk-core.git
RUN git clone -b mplr22-gc-space-overhead-mmtk https://github.com/k-sareen/mmtk-openjdk.git

# Build images
WORKDIR /root/openjdk
# Normal image
RUN make CONF=linux-x86_64-normal-server-release clean
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../gc-space-overhead/mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-space-overhead-core_f6986e5d-jdk_1b1ccdc-vm_ca90b43f0f5
# mimalloc image
WORKDIR /root/gc-space-overhead/mmtk-openjdk
RUN git checkout mplr22-gc-space-overhead-mi-new
WORKDIR /root/openjdk
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../gc-space-overhead/mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-space-overhead-core_f6986e5d-jdk_b6ad64c-vm_ca90b43f0f5-mi-analysis-mark_header
# TCMalloc image
WORKDIR /root/gc-space-overhead/mmtk-openjdk
RUN git checkout mplr22-gc-space-overhead-tc
WORKDIR /root/openjdk
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../gc-space-overhead/mmtk-openjdk/openjdk
RUN cp $(find /root/gc-space-overhead -name libtcmalloc.so.4) /usr/lib/x86_64-linux-gnu/
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../gc-space-overhead/mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-space-overhead-core_f6986e5d-jdk_f5bfd51-vm_ca90b43f0f5-tc-analysis-mark_header

# 2. GC frequency
RUN mkdir -p /root/gc-frequency
WORKDIR /root/gc-frequency
RUN git clone -b mplr22-gc-frequency-tc https://github.com/k-sareen/mmtk-core.git
RUN git clone -b mplr22-gc-proximity https://github.com/k-sareen/mmtk-openjdk.git

# Build image
WORKDIR /root/openjdk
# mimalloc image
RUN make CONF=linux-x86_64-normal-server-release clean
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../gc-frequency/mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-frequency-core_ae0b122e-jdk_97f12c2-vm_ca90b43f0f5-mi

# 3. GC proximity
RUN mkdir -p /root/gc-proximity
WORKDIR /root/gc-proximity
RUN git clone -b mplr22-gc-proximity-tc https://github.com/k-sareen/mmtk-core.git
RUN git clone -b mplr22-gc-proximity https://github.com/k-sareen/mmtk-openjdk.git

# Build images
WORKDIR /root/openjdk
# Normal image
RUN make CONF=linux-x86_64-normal-server-release clean
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../gc-proximity/mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-proximity-core_f28eeb5d-jdk_97f12c2-vm_ca90b43f0f5-mi
# TCMalloc image
WORKDIR /root/gc-proximity/mmtk-openjdk
RUN git checkout mplr22-gc-proximity-tc
WORKDIR /root/openjdk
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../gc-proximity/mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-proximity-core_f28eeb5d-jdk_2385235-vm_ca90b43f0f5-tc
# Non-moving immix image
WORKDIR /root/gc-proximity/mmtk-openjdk
RUN git checkout mplr22-gc-proximity
WORKDIR /root/gc-proximity/mmtk-core
RUN sed -i "s/pub const DEFRAG: bool = true/pub const DEFRAG: bool = false/" src/policy/immix/mod.rs
WORKDIR /root/openjdk
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../gc-proximity/mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-proximity-core_f28eeb5d-jdk_97f12c2-vm_ca90b43f0f5-mi-no_defrag

# 4. GC delayed reclamation
# Have to use clang-14 for building TCMalloc
RUN mkdir -p /root/gc-deferred-free
WORKDIR /root/gc-deferred-free
RUN wget "https://github.com/llvm/llvm-project/releases/download/llvmorg-14.0.0/clang+llvm-14.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz"
RUN tar xvf clang+llvm-14.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz
RUN mv clang+llvm-14.0.0-x86_64-linux-gnu-ubuntu-18.04 clang-14
# Build allocators
RUN git clone -b mplr22-deferred-free https://github.com/k-sareen/deferred-free.git
WORKDIR ./deferred-free
RUN CC=/root/gc-deferred-free/clang-14/bin/clang make
RUN cp out/libql.so /root/ql-benchmarks/allocators
WORKDIR /root/gc-deferred-free
# mimalloc
RUN git clone https://github.com/microsoft/mimalloc
WORKDIR ./mimalloc
RUN git checkout v2.0.6
RUN mkdir -p out/release
WORKDIR out/release
# Need to install more recent cmake
RUN wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null
RUN echo 'deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ bionic main' | tee /etc/apt/sources.list.d/kitware.list >/dev/null
RUN apt-get update
RUN rm /usr/share/keyrings/kitware-archive-keyring.gpg
RUN apt-get install -y kitware-archive-keyring
RUN apt-get install -y cmake
RUN CC=/root/gc-deferred-free/clang-14/bin/clang CXX=/root/gc-deferred-free/clang-14/bin/clang++ cmake ../..
RUN make
RUN cp libmimalloc.so /root/ql-benchmarks/allocators
# TCMalloc
WORKDIR /root/gc-deferred-free
RUN git clone https://github.com/google/tcmalloc
WORKDIR ./tcmalloc
RUN git checkout 8bc4d12797b31e48f1cfa15beab4c9933166286d
RUN wget "https://github.com/bazelbuild/bazel/releases/download/5.1.1/bazel-5.1.1-linux-x86_64"
RUN chmod +x ./bazel-5.1.1-linux-x86_64
RUN mv bazel-5.1.1-linux-x86_64 bazel
# From mimalloc-bench build-bench-env.sh
RUN apt-get install -y gawk
RUN sed -i '/linkstatic/d' tcmalloc/BUILD
RUN sed -i '/linkstatic/d' tcmalloc/internal/BUILD
RUN sed -i '/linkstatic/d' tcmalloc/testing/BUILD
RUN sed -i '/linkstatic/d' tcmalloc/variants.bzl
RUN gawk -i inplace '(f && g) {$0="linkshared = True, )"; f=0; g=0} /This library provides tcmalloc always/{f=1} /alwayslink/{g=1} 1' tcmalloc/BUILD
RUN gawk -i inplace 'f{$0="cc_binary("; f=0} /This library provides tcmalloc always/{f=1} 1' tcmalloc/BUILD
RUN gawk -i inplace '/alwayslink/ && !f{f=1; next} 1' tcmalloc/BUILD
RUN CC=/root/gc-deferred-free/clang-14/bin/clang CXX=/root/gc-deferred-free/clang-14/bin/clang++ ./bazel build -c opt tcmalloc
RUN cp -L bazel-bin/tcmalloc/libtcmalloc.so /root/ql-benchmarks/allocators
# snmalloc
WORKDIR /root/gc-deferred-free
RUN git clone https://github.com/microsoft/snmalloc
WORKDIR ./snmalloc
RUN git checkout 0.6.0
RUN mkdir build
WORKDIR build
RUN CC=/root/gc-deferred-free/clang-14/bin/clang CXX=/root/gc-deferred-free/clang-14/bin/clang++ cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release
RUN ninja
RUN cp libsnmallocshim.so /root/ql-benchmarks/allocators

WORKDIR /root

CMD ["bash", "--login"]
