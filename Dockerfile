FROM ubuntu:18.04

ENV HOME /root
WORKDIR /root

# Install libraries
RUN apt-get update && apt-get upgrade -y
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install -y wget curl python3 build-essential
RUN apt-get install -y openjdk-11-jdk
RUN apt-get install -y autoconf libx11-dev libxext-dev libxrender-dev libxrandr-dev libxtst-dev libxt-dev libcups2-dev libfontconfig1-dev libasound2-dev
RUN apt-get install -y clang git zip libpfm4 libpfm4-dev gcc-multilib g++-multilib python3-pip
RUN apt-get install -y vim tmux
RUN apt-get install -y libgmp-dev ghostscript ninja

# Install rust
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install running-ng
RUN pip3 install running-ng
RUN pip3 install numpy seaborn pandas matplotlib

# DaCapo Chopin benchmark
RUN mkdir -p /root/dacapo/dacapo-evaluation-git-f480064 /root/dacapo/dacapo-evaluation-git-6804496f
RUN cd /root/dacapo
RUN wget "https://cloudstor.aarnet.edu.au/plus/s/Ik3qCiTX8FZlNIL"
RUN wget "https://cloudstor.aarnet.edu.au/plus/s/TMDilWlR5Xe1cg3"

RUN cd /root/dacapo/dacapo-evaluation-git-f480064
RUN wget "https://cloudstor.aarnet.edu.au/plus/s/1RXUzrh3EENq4Sq"
RUN unzip dacapo-evaluation-git-f480064.zip

RUN cd /root/dacapo/dacapo-evaluation-git-6804496f
RUN wget "https://cloudstor.aarnet.edu.au/plus/s/X7ybA15mrycoSAy"
RUN unzip dacapo-evaluation-git-6804496f.zip

# RUN mkdir -p /root/dacapo/dacapo-evaluation-git-f480064 /root/dacapo/dacapo-evaluation-git-6804496f
# COPY ./dacapo-evaluation-git-f480064.jar  /root/dacapo/
# COPY ./dacapo-evaluation-git-f480064.zip  /root/dacapo/dacapo-evaluation-git-f480064/
# RUN cd /root/dacapo/dacapo-evaluation-git-f480064 && unzip dacapo-evaluation-git-f480064.zip
#
# COPY ./dacapo-evaluation-git-6804496f.jar  /root/dacapo/
# COPY ./dacapo-evaluation-git-6804496f.zip  /root/dacapo/dacapo-evaluation-git-6804496f/
# RUN cd /root/dacapo/dacapo-evaluation-git-6804496f && unzip dacapo-evaluation-git-6804496f.zip

# C benchmarks. Note we don't provide the SPEC benchmarks as you require a license to run them
COPY ./ql-benchmarks /root/
RUN cd /root/ql-benchmarks
RUN git clone https://github.com/daanx/mimalloc-bench
RUN git checkout 5126dc8d19d35364513ad5fde8fa964eb722fbdd
RUN pushd mimalloc-bench
# Z3 build
RUN git clone https://github.com/Z3Prover/z3
RUN popd z3
RUN git checkout 545341e69999ceca585f3dacc08d5c6b6f096edc
RUN mkdir build
RUN cd build
RUN cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release ../
RUN make -j2
RUN cd .. && cp z3 /root/ql-benchmarks
RUN popd
# mimalloc benchmarks
RUN ./build-bench-env.sh bench redis lean
RUN cd out/bench
RUN cp alloc-test barnes cache-scratch cfrac espresso glibc-simple glibc-thread larson sh6bench sh8bench xmalloc-test -t /root/ql-benchmarks
RUN popd

# Copy and build probes
COPY ./probes.zip /root/
RUN cd /root && unzip probes.zip
RUN cd probes && make all JDK=/usr/lib/jvm/java-11-openjdk-amd64 CFLAGS=-Wno-error=stringop-overflow JAVAC=/usr/lib/jvm/java-11-openjdk-amd64/bin/javac

RUN cd /root
RUN git clone -b jdk-11.0.15+8-mmtk https://github.com/mmtk/openjdk.git
RUN cd /root/openjdk && git checkout ca90b43f0f5
RUN sh configure --disable-warnings-as-errors --with-debug-level=release

COPY ./bench /root/
RUN mkdir -p /root/bench/build

# 1. GC space overhead
RUN mkdir -p /root/gc-space-overhead && cd /root/gc-space-overhead
RUN git clone -b mplr22-gc-space-overhead-tc https://github.com/k-sareen/mmtk-core.git
RUN git clone -b mplr22-gc-space-overhead-mmtk https://github.com/k-sareen/mmtk-openjdk.git

# Build images
RUN pushd /root/openjdk
# Normal image
RUN make CONF=linux-x86_64-normal-server-release clean
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-space-overhead-core_f6986e5d-jdk_1b1ccdc-vm_ca90b43f0f5
# mimalloc image
RUN pushd /root/gc-proximity/mmtk-openjdk
RUN git checkout mplr22-gc-space-overhead-mi-new
RUN popd
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-space-overhead-core_f6986e5d-jdk_b6ad64c-vm_ca90b43f0f5-mi-analysis-mark_header
# TCMalloc image
RUN pushd /root/gc-proximity/mmtk-openjdk
RUN git checkout mplr22-gc-space-overhead-tc
RUN popd
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-space-overhead-core_f6986e5d-jdk_f5bfd51-vm_ca90b43f0f5-tc-analysis-mark_header
RUN popd

# 2. GC frequency
RUN mkdir -p /root/gc-frequency && cd /root/gc-frequency
RUN git clone -b mplr22-gc-frequency-tc https://github.com/k-sareen/mmtk-core.git
RUN git clone -b mplr22-gc-proximity https://github.com/k-sareen/mmtk-openjdk.git

# Build image
RUN pushd /root/openjdk
# mimalloc image
RUN make CONF=linux-x86_64-normal-server-release clean
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-frequency-core_ae0b122e-jdk_97f12c2-vm_ca90b43f0f5-mi
RUN popd

# 3. GC proximity
RUN mkdir -p /root/gc-proximity && cd /root/gc-proximity
RUN git clone -b mplr22-gc-proximity-tc https://github.com/k-sareen/mmtk-core.git
RUN git clone -b mplr22-gc-proximity https://github.com/k-sareen/mmtk-openjdk.git

# Build images
RUN pushd /root/openjdk
# Normal image
RUN make CONF=linux-x86_64-normal-server-release clean
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-proximity-core_f28eeb5d-jdk_97f12c2-vm_ca90b43f0f5-mi
# TCMalloc image
RUN pushd /root/gc-proximity/mmtk-openjdk
RUN git checkout mplr22-gc-proximity-tc
RUN popd
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-proximity-core_f28eeb5d-jdk_2385235-vm_ca90b43f0f5-tc
# Non-moving immix image
RUN pushd /root/gc-proximity/mmtk-openjdk
RUN git checkout mplr22-gc-proximity
RUN popd
RUN pushd /root/gc-proximity/mmtk-core
RUN sed -i "s/pub const DEFRAG: bool = true/pub const DEFRAG: bool = false/" src/policy/immix/mod.rs
RUN popd
RUN make CONF=linux-x86_64-normal-server-release THIRD_PARTY_HEAP=$PWD/../mmtk-openjdk/openjdk images
RUN cp -r ./build/linux-x86_64-normal-server-release /root/bench/build/jdk11-gc-proximity-core_f28eeb5d-jdk_97f12c2-vm_ca90b43f0f5-mi-no_defrag
RUN popd

# 4. GC delayed reclamation
RUN mkdir -p /root/gc-deferred-free && cd /root/gc-deferred-free
RUN git clone -b mplr22-deferred-free https://github.com/k-sareen/deferred-free.git
# Have to use clang-14 for building TCMalloc
RUN wget "https://github.com/llvm/llvm-project/releases/download/llvmorg-14.0.0/clang+llvm-14.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz"
RUN tar xvf clang+llvm-14.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz
RUN mv clang+llvm-14.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz clang-14
# Build allocators
RUN pushd deferred-free
RUN CC=/root/gc-deferred-free/clang-14/bin/clang-14 make
RUN popd
# mimalloc
RUN git clone https://github.com/microsoft/mimalloc
RUN pushd mimalloc
RUN git checkout v2.0.6
RUN mkdir -p out/release
RUN cd out/release
RUN CC=/root/gc-deferred-free/clang-14/bin/clang-14 cmake ../..
RUN make
RUN popd
# TCMalloc
RUN git clone https://github.com/google/tcmalloc
RUN pushd tcmalloc
RUN git checkout 8e5dca55b7d9f0cdf6291389b3cb32bdb5330b82
RUN popd
# snmalloc
RUN git clone https://github.com/microsoft/snmalloc
RUN pushd snmalloc
RUN git checkout 0.6.0
RUN mkdir build
RUN cd build
RUN CC=/root/gc-deferred-free/clang-14/bin/clang-14 cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release
RUN ninja
RUN popd

CMD ["bash", "--login"]
