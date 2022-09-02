## MPLR'22: Better Understanding the Costs and Benefits of Automatic Memory Management

This repository contains the source code and scripts used to gather data for
the MPLR'22 paper "Better Understanding the Costs and Benefits of Automatic
Memory Management". We describe four different methodologies in our paper, each
having their own implementation.

### Setup
We use `running-ng` as our benchmark runner. We provide a Dockerfile that
compiles and builds our sources and benchmarks.

```console
# Pull docker image
$ sudo docker pull k-sareen/mplr22-gccost
# Launch container
$ sudo docker run -dit --privileged -m 32g --name gccost k-sareen/mplr22-gccost
# Login into the container
$ sudo docker exec -it gccost /bin/bash
```

### Space Overheads of GC
You can run this experiment like so:
```console
$ cd /root/bench/configs/gc-space-overhead/
$ running runbms /root/bench/results gc-space-overhead-mi_128KB.yml -s 1.0 -p gc-space-mi_128
```
It is recommended to provide a descriptive prefix to the run (using the `-p`
flag) as it will aid in differentiating different runs. The output of the run
will be in the folder name printed out by the running script in the
`/root/bench/results` directory. The column we are interested in here is the
"reserved_pages.max" column as it is the high-watermark for the number of pages
allocated. Since the value is the number of pages allocated, we can convert it
to heap size in MB using the following formula:

```python
def heap_size_mb(pages):
    return (pages * 4096.0 / 1024**2)
```

To gather the minimum heap values for the canonical GCs, you can run the
experiment like so:
```console
$ cd /root/bench/configs/gc-space-overhead/
$ running runbms gc-space-overhead_Immix.yml Immix.yml -s 1.0
```
The minheap command will write the minimum heap values it has gathered into the
`Immix.yml` file. Note that certain benchmarks such as `avrora` and `fop` will
not print an "OutOfMemoryError" if the heap size is insufficient to run the
benchmarks. In such cases the minheap script will assume that the benchmark has
crashed and will return a minheap value of infinity. It is recommended to
manually run the minheap algorithm in such cases by starting around where the
minheap run returned infinity.

### Mutator Performance: GC Frequency
You can run this experiment like so:
```console
$ cd /root/bench/configs/gc-frequency/
$ running runbms /root/bench/results gc-frequency-limit_1.yml -s 1.0 -p gc-freq-limit_1
```

The column we are interested in here is the "time.other" column as that is the
mutator execution time (calculated as total time - STW time).

### Mutator Performance: GC Proximity
You can run this experiment like so:
```console
$ cd /root/bench/configs/gc-proximity/
$ running runbms /root/bench/results gc-proximity-zen3-Immix_10.yml -s 1.0 -p gc-proximity-Immix_10
```

Note the resultant csv files from the above run are written to
`/root/bench/gc-proximity`. You should create a new folder specially for a
single run and then move these csv files there as it could cause confusion if
you mix two runs with different configurations. The provided
`bench/generate_graphs.py` script expects name in a particular location and format like so:

```console
$ cd /root/bench/gc-proximity
$ mkdir -p gc-proximity-zen3/zen3-Immix_10
$ mv *.csv -t gc-proximity-zen3/zen3-Immix_10
```

We only provide the scripts for a Zen3 Ryzen 9 5950X system. You may have to
slightly tweak the stress factor values in the configuration script to achieve
the ~10, ~100, and ~1000 GC resolution.

We provide a script (`bench/generate_graphs.py`) that will analyze the csv files
and generate the graphs you see in our paper. You will need to have at least 32
GB of RAM on the machine if you are running this script as the pandas DataFrames
are large. Note you will have to update the `zen3_min` and `skl_min` variables
with the minimum value of the execution time of a group between per each GC. The
script prints out the minimum values for each of the GCs for that resolution.
Hence, you can update these variables by running the script for each of the
three resolutions (i.e. 10, 100, 1000) and then selecting the minimum of these
for each GC.

### Effects of Delayed Reclamation
You can run this experiment like so:
```console
$ cd /root/bench/configs/gc-deferred-free/
$ running runbms /root/bench/results ql-real-mi.yml -s 1.0 -p ql-real-mi
```
The column we are interested in is the "time" column as it represents the
execution time.

Note that we don't provide the SPEC benchmarks and its scripts as you require a
license to use them.
