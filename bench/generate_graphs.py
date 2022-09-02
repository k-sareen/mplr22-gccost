#!/usr/bin/env python3

import sys
import dask
import glob
import numpy as np
import pandas as pd
import seaborn as sns
import matplotlib as mpl
import dask.dataframe as dd
import matplotlib.pyplot as plt
from pathlib import Path

sns.set(style='whitegrid',)
pd.options.mode.chained_assignment = None  # default='warn'

zen3_base = "zen3"
skl_base = "skylake"

# [Immix, MarkSweep, NonMovingImmix, SemiSpace, tc-MarkSweep]
# Immix, NonMovingImmix, SemiSpace from N = 1000 GCs; Marksweep and tc-MarkSweep from 10 GCs
zen3_min = [0.06545829889214166, 5.7467597723470565, 0.07569286578841396, 0.060541337968283156, 6.391436732804811]
# All are from N = 1000 GCs
skl_min = [0.07866396001767174, 0.25050360933701654, 0.08920938524409101, 0.06599718138635736, 0.2603449243093923]


def import_log_files(base_name, num_gc):
    log_files = []
    for uarch_dir in glob.glob("*-" + base_name):
        print(uarch_dir)
        for log_dir in glob.glob(uarch_dir + "/*_" + str(num_gc)):
            gclog_files = [log for log in glob.glob(log_dir + "/*-gclog.csv")]
            querylog_files_all = [log for log in glob.glob(log_dir + "/*-querylog.csv")]

            i = 0
            querylog_files = []
            for log in querylog_files_all:
                if i % 5 == 4:
                    querylog_files.append(log)
                i += 1

            assert len(querylog_files) == len(gclog_files)
            log_files.append((log_dir, gclog_files, querylog_files))
    return log_files


def create_dataframes(logs):
    dfs = []
    for log in logs:
        gc_logs = log[1]
        query_logs = log[2]

        gc_df = dd.concat([dd.read_csv(f, header=None) for f in gc_logs], ignore_index=True).compute()
        gc_df.columns = ["gcnum", "start", "time"]
        gc_df["end"] = gc_df["start"] + gc_df["time"]

        gc_df.reset_index(drop=True, inplace=True)

        # Add dummy value for last GC in case we wrap around
        tmp = gc_df.iloc[-1:].copy()
        tmp["gcnum"] += 1
        tmp["start"] += 1000000000000000000
        tmp["end"] += 1000000000000000000
        gc_df = pd.concat([gc_df, tmp], ignore_index=True)

        query_df = dd.concat([dd.read_csv(f, header=None) for f in query_logs], ignore_index=True).compute()
        query_df.columns = ["query", "start", "time"]
        query_df["end"] = query_df["start"] + query_df["time"]
        query_df.reset_index(drop=True, inplace=True)

        dfs.append((gc_df, query_df))
    return dfs


def normalize_min_column(df, column):
    return (df[column] / df[column].min())


def closest_gc_time_vectorized(query_start, gc_df):
    return gc_df["end"].iloc[(np.searchsorted(gc_df["end"].values, query_start) - 1)]


def interrupted_by_gc_vectorized(query_start, query_end, gc_df):
    return np.where(gc_df["end"].iloc[(np.searchsorted(gc_df["end"].values, query_start))] < query_end, 1, 0)


def normalize_query_work(id, csv_file, query_df, gc_df):
    print(f"Start {csv_file}")
    query_df_tmp = query_df
    query_df_tmp["timenorm"] = normalize_min_column(query_df_tmp, "time")

    gctime_arr = closest_gc_time_vectorized(query_df_tmp["start"].values, gc_df)
    gctime_df = pd.DataFrame(gctime_arr)
    gctime_df.index = query_df_tmp.index
    assert len(query_df) == len(gctime_df)

    gcbtwn_arr = interrupted_by_gc_vectorized(query_df_tmp["start"].values, query_df_tmp["end"].values, gc_df)
    gcbtwn_df = pd.DataFrame(gcbtwn_arr)
    gcbtwn_df.index = query_df_tmp.index
    assert len(query_df) == len(gcbtwn_df)

    query_df_tmp["gctime"] = gctime_df
    query_df_tmp["gcinbtwn"] = gcbtwn_df
    query_df_tmp["gcdiff"] = (query_df_tmp["start"] - query_df_tmp["gctime"]) / (10**6)   # gcdiff is in ms
    print(f"Done {csv_file}")

    # query_df_tmp.to_csv(csv_file + ".csv")
    # print(f"Written {csv_file}.csv")

    return query_df_tmp


def plot_execution_time_graph(df, base, ymin, ymax):
    # ["SemiSpace", "Immix", "NonMovingImmix", "mi-MarkSweep", "tc-MarkSweep"]
    colours = ["#e6194B", "#279f27", "#42d142", "#5d9ef6", "#c9defc"]
    mpl.rcParams['pdf.fonttype'] = 42
    mpl.rcParams['ps.fonttype'] = 42
    mpl.rc('font',family='Linux Biolinum')

    # plt.rcParams['font.family'] = 'sans-serif'
    # plt.rcParams['font.sans-serif'] = 'Linux Biolinum'

    xticks = ["0", "0", "20", "40", "60", "80", "100"]
    fig, ax = plt.subplots(1,1,figsize=(16,12))
    sns.lineplot(data=df, x="id", y="mean_time", hue="GC", palette=colours)
    sns.despine()
    ax.set_xlabel("Percentile Distance from GC", fontsize=26, labelpad=12)
    ax.set_ylabel("Normalized Mean Execution Time", fontsize=26, labelpad=12)
    ax.set_xticklabels(xticks, fontsize=22)
    ax = plt.gca()
    ax.set_ylim([ymin, ymax])
    plt.yticks(fontsize=20)
    leg = plt.legend(fontsize=26)

    # change the line width for the legend
    for line in leg.get_lines():
        line.set_linewidth(5.0)

    plt.savefig(f"graphs/{base}.pdf")
    print(f"Written graphs/{base}.pdf")


if __name__ == "__main__":
    zen3 = False
    skl = False
    uarch = sys.argv[1]
    num_gc = int(sys.argv[2])

    if uarch == "both":
        zen3 = True
        skl = True
        uarch = "zen3 and skl"
    elif uarch == "zen3":
        zen3 = True
    elif uarch == "skl":
        skl = True
    else:
        print("Please select one of \"zen3\", \"skl\", or \"both\"")
        raise ValueError()
    print(f"Generating graphs for {uarch}")

    # Ryzen 9 5950X
    zen3_logs = []
    if zen3:
        zen3_logs = import_log_files(zen3_base, num_gc)
        zen3_logs = sorted(zen3_logs, key=lambda x: x[0])

        assert("Immix" in zen3_logs[0][0])
        assert("MarkSweep" in zen3_logs[1][0])
        assert("NonMovingImmix" in zen3_logs[2][0])
        assert("SemiSpace" in zen3_logs[3][0])
        assert("tc-MarkSweep" in zen3_logs[4][0])

    # Skylake i7 6700
    skl_logs = []
    if skl:
        skl_logs = import_log_files(skl_base, num_gc)
        skl_logs = sorted(skl_logs, key=lambda x: x[0])

        assert("Immix" in skl_logs[0][0])
        assert("MarkSweep" in skl_logs[1][0])
        assert("NonMovingImmix" in skl_logs[2][0])
        assert("SemiSpace" in skl_logs[3][0])
        assert("tc-MarkSweep" in skl_logs[4][0])

    print("Imported files")

    if zen3:
        zen3_dfs = create_dataframes(zen3_logs)

        gc_df_ix_zen3 = zen3_dfs[0][0]
        query_df_ix_zen3 = zen3_dfs[0][1]

        gc_df_mi_zen3 = zen3_dfs[1][0]
        query_df_mi_zen3 = zen3_dfs[1][1]

        gc_df_nix_zen3 = zen3_dfs[2][0]
        query_df_nix_zen3 = zen3_dfs[2][1]

        gc_df_ss_zen3 = zen3_dfs[3][0]
        query_df_ss_zen3 = zen3_dfs[3][1]

        gc_df_tc_zen3 = zen3_dfs[4][0]
        query_df_tc_zen3 = zen3_dfs[4][1]

        print("Created dataframes")

        query_df_norm_ix = normalize_query_work(0, zen3_base + "-" + str(num_gc) + "_Immix", query_df_ix_zen3, gc_df_ix_zen3)
        query_df_norm_mi = normalize_query_work(0, zen3_base + "-" + str(num_gc) + "_MarkSweep", query_df_mi_zen3, gc_df_mi_zen3)
        query_df_norm_nix = normalize_query_work(0, zen3_base + "-" + str(num_gc) + "_NonMovingImmix", query_df_nix_zen3, gc_df_nix_zen3)
        query_df_norm_ss = normalize_query_work(0, zen3_base + "-" + str(num_gc) + "_SemiSpace", query_df_ss_zen3, gc_df_ss_zen3)
        query_df_norm_tc = normalize_query_work(0, zen3_base + "-" + str(num_gc) + "_tc-MarkSweep", query_df_tc_zen3, gc_df_tc_zen3)

        del zen3_dfs
        del gc_df_ix_zen3
        del query_df_ix_zen3
        del gc_df_mi_zen3
        del query_df_mi_zen3
        del gc_df_nix_zen3
        del query_df_nix_zen3
        del gc_df_ss_zen3
        del query_df_ss_zen3
        del gc_df_tc_zen3
        del query_df_tc_zen3

        # Remove executions that don't have a prior GC (negative value means it wrapped around to the end of the numpy array)
        query_df_norm_ix = query_df_norm_ix[query_df_norm_ix["gcdiff"] > 0]
        query_df_norm_mi = query_df_norm_mi[query_df_norm_mi["gcdiff"] > 0]
        query_df_norm_nix = query_df_norm_nix[query_df_norm_nix["gcdiff"] > 0]
        query_df_norm_ss = query_df_norm_ss[query_df_norm_ss["gcdiff"] > 0]
        query_df_norm_tc = query_df_norm_tc[query_df_norm_tc["gcdiff"] > 0]

        query_df_norm_ix = query_df_norm_ix.sort_values("gcdiff")
        query_df_norm_mi = query_df_norm_mi.sort_values("gcdiff")
        query_df_norm_nix = query_df_norm_nix.sort_values("gcdiff")
        query_df_norm_ss = query_df_norm_ss.sort_values("gcdiff")
        query_df_norm_tc = query_df_norm_tc.sort_values("gcdiff")

        query_df_norm_ix["time_ms"] = query_df_norm_ix["time"] / (10**6)
        query_df_norm_mi["time_ms"] = query_df_norm_mi["time"] / (10**6)
        query_df_norm_nix["time_ms"] = query_df_norm_nix["time"] / (10**6)
        query_df_norm_ss["time_ms"] = query_df_norm_ss["time"] / (10**6)
        query_df_norm_tc["time_ms"] = query_df_norm_tc["time"] / (10**6)

        query_df_clean_ix = query_df_norm_ix[query_df_norm_ix["gcinbtwn"] == 0]
        query_df_clean_mi = query_df_norm_mi[query_df_norm_mi["gcinbtwn"] == 0]
        query_df_clean_nix = query_df_norm_nix[query_df_norm_nix["gcinbtwn"] == 0]
        query_df_clean_ss = query_df_norm_ss[query_df_norm_ss["gcinbtwn"] == 0]
        query_df_clean_tc = query_df_norm_tc[query_df_norm_tc["gcinbtwn"] == 0]

        print(len(query_df_norm_ix) - len(query_df_clean_ix))
        print(len(query_df_norm_mi) - len(query_df_clean_mi))
        print(len(query_df_norm_nix) - len(query_df_clean_nix))
        print(len(query_df_norm_ss) - len(query_df_clean_ss))
        print(len(query_df_norm_tc) - len(query_df_clean_tc))

        N = 1000
        query_norm_ix_split = np.array_split(query_df_clean_ix, N)
        query_norm_mi_split = np.array_split(query_df_clean_mi, N)
        query_norm_nix_split = np.array_split(query_df_clean_nix, N)
        query_norm_ss_split = np.array_split(query_df_clean_ss, N)
        query_norm_tc_split = np.array_split(query_df_clean_tc, N)
        print(len(query_norm_ix_split[0]))

        ix_split_mean = [arr["time_ms"].mean() for arr in query_norm_ix_split]
        # ix_split_std = [arr["time_ms"].std() for arr in query_norm_ix_split]

        mi_split_mean = [arr["time_ms"].mean() for arr in query_norm_mi_split]
        # mi_split_std = [arr["time_ms"].std() for arr in query_norm_mi_split]

        nix_split_mean = [arr["time_ms"].mean() for arr in query_norm_nix_split]
        # nix_split_std = [arr["time_ms"].std() for arr in query_norm_nix_split]

        ss_split_mean = [arr["time_ms"].mean() for arr in query_norm_ss_split]
        # ss_split_std = [arr["time_ms"].std() for arr in query_norm_ss_split]

        tc_split_mean = [arr["time_ms"].mean() for arr in query_norm_tc_split]
        # tc_split_std = [arr["time_ms"].std() for arr in query_norm_tc_split]

        del query_df_norm_ix
        del query_df_norm_mi
        del query_df_norm_nix
        del query_df_norm_ss
        del query_df_norm_tc

        del query_df_clean_ix
        del query_df_clean_mi
        del query_df_clean_nix
        del query_df_clean_ss
        del query_df_clean_tc

        mins = []
        mins.append(np.array(ix_split_mean).min())
        mins.append(np.array(mi_split_mean).min())
        mins.append(np.array(nix_split_mean).min())
        mins.append(np.array(ss_split_mean).min())
        mins.append(np.array(tc_split_mean).min())

        print(mins)
        # print(np.array(mins).min())

        ix_split_mean = np.array(ix_split_mean) / zen3_min[0]
        # ix_split_std = np.array(ix_split_std) / np.array(ix_split_std).min()

        mi_split_mean = np.array(mi_split_mean) / zen3_min[1]
        # mi_split_std = np.array(mi_split_std) / np.array(mi_split_std).min()

        nix_split_mean = np.array(nix_split_mean) / zen3_min[2]
        # nix_split_std = np.array(nix_split_std) / np.array(nix_split_std).min()

        ss_split_mean = np.array(ss_split_mean) / zen3_min[3]
        # ss_split_std = np.array(ss_split_std) / np.array(ss_split_std).min()

        tc_split_mean = np.array(tc_split_mean) / zen3_min[4]
        # tc_split_std = np.array(tc_split_std) / np.array(tc_split_std).min()

        # assert len(nix_split_mean) == len(nix_split_std)

        ss_dict = { "id": range(0, N), "mean_time": ss_split_mean, "GC": ["semi-space"]*N }
        ix_dict = { "id": range(0, N), "mean_time": ix_split_mean, "GC": ["immix"]*N }
        nix_dict = { "id": range(0, N), "mean_time": nix_split_mean, "GC": ["immix, non-moving"]*N }
        mi_dict = { "id": range(0, N), "mean_time": mi_split_mean, "GC": ["mark-sweep, mi"]*N }
        tc_dict = { "id": range(0, N), "mean_time": tc_split_mean, "GC": ["mark-sweep, tc"]*N }

        percentile_graphs = pd.concat([
                pd.DataFrame.from_dict(ss_dict),
                pd.DataFrame.from_dict(ix_dict),
                pd.DataFrame.from_dict(nix_dict),
                pd.DataFrame.from_dict(mi_dict),
                pd.DataFrame.from_dict(tc_dict),
            ], ignore_index=True)

        plot_execution_time_graph(percentile_graphs, f"Zen3_N{num_gc}", 1.0, 2.2)

    if skl:
        skl_dfs = create_dataframes(skl_logs)

        gc_df_ix_skl = skl_dfs[0][0]
        query_df_ix_skl = skl_dfs[0][1]

        gc_df_mi_skl = skl_dfs[1][0]
        query_df_mi_skl = skl_dfs[1][1]

        gc_df_nix_skl = skl_dfs[2][0]
        query_df_nix_skl = skl_dfs[2][1]

        gc_df_ss_skl = skl_dfs[3][0]
        query_df_ss_skl = skl_dfs[3][1]

        gc_df_tc_skl = skl_dfs[4][0]
        query_df_tc_skl = skl_dfs[4][1]

        print("Created dataframes")

        query_df_norm_ix = normalize_query_work(0, skl_base + "-" + str(num_gc) + "_Immix", query_df_ix_skl, gc_df_ix_skl)
        query_df_norm_mi = normalize_query_work(0, skl_base + "-" + str(num_gc) + "_MarkSweep", query_df_mi_skl, gc_df_mi_skl)
        query_df_norm_nix = normalize_query_work(0, skl_base + "-" + str(num_gc) + "_NonMovingImmix", query_df_nix_skl, gc_df_nix_skl)
        query_df_norm_ss = normalize_query_work(0, skl_base + "-" + str(num_gc) + "_SemiSpace", query_df_ss_skl, gc_df_ss_skl)
        query_df_norm_tc = normalize_query_work(0, skl_base + "-" + str(num_gc) + "_tc-MarkSweep", query_df_tc_skl, gc_df_tc_skl)

        del skl_dfs
        del gc_df_ix_skl
        del query_df_ix_skl
        del gc_df_mi_skl
        del query_df_mi_skl
        del gc_df_nix_skl
        del query_df_nix_skl
        del gc_df_ss_skl
        del query_df_ss_skl
        del gc_df_tc_skl
        del query_df_tc_skl

        # Remove executions that don't have a prior GC (negative value means it wrapped around to the end of the numpy array)
        query_df_norm_ix = query_df_norm_ix[query_df_norm_ix["gcdiff"] > 0]
        query_df_norm_mi = query_df_norm_mi[query_df_norm_mi["gcdiff"] > 0]
        query_df_norm_nix = query_df_norm_nix[query_df_norm_nix["gcdiff"] > 0]
        query_df_norm_ss = query_df_norm_ss[query_df_norm_ss["gcdiff"] > 0]
        query_df_norm_tc = query_df_norm_tc[query_df_norm_tc["gcdiff"] > 0]

        query_df_norm_ix = query_df_norm_ix.sort_values("gcdiff")
        query_df_norm_mi = query_df_norm_mi.sort_values("gcdiff")
        query_df_norm_nix = query_df_norm_nix.sort_values("gcdiff")
        query_df_norm_ss = query_df_norm_ss.sort_values("gcdiff")
        query_df_norm_tc = query_df_norm_tc.sort_values("gcdiff")

        query_df_norm_ix["time_ms"] = query_df_norm_ix["time"] / (10**6)
        query_df_norm_mi["time_ms"] = query_df_norm_mi["time"] / (10**6)
        query_df_norm_nix["time_ms"] = query_df_norm_nix["time"] / (10**6)
        query_df_norm_ss["time_ms"] = query_df_norm_ss["time"] / (10**6)
        query_df_norm_tc["time_ms"] = query_df_norm_tc["time"] / (10**6)

        query_df_clean_ix = query_df_norm_ix[query_df_norm_ix["gcinbtwn"] == 0]
        query_df_clean_mi = query_df_norm_mi[query_df_norm_mi["gcinbtwn"] == 0]
        query_df_clean_nix = query_df_norm_nix[query_df_norm_nix["gcinbtwn"] == 0]
        query_df_clean_ss = query_df_norm_ss[query_df_norm_ss["gcinbtwn"] == 0]
        query_df_clean_tc = query_df_norm_tc[query_df_norm_tc["gcinbtwn"] == 0]

        print(len(query_df_norm_ix) - len(query_df_clean_ix))
        print(len(query_df_norm_mi) - len(query_df_clean_mi))
        print(len(query_df_norm_nix) - len(query_df_clean_nix))
        print(len(query_df_norm_ss) - len(query_df_clean_ss))
        print(len(query_df_norm_tc) - len(query_df_clean_tc))

        N = 1000
        query_norm_ix_split = np.array_split(query_df_clean_ix, N)
        query_norm_mi_split = np.array_split(query_df_clean_mi, N)
        query_norm_nix_split = np.array_split(query_df_clean_nix, N)
        query_norm_ss_split = np.array_split(query_df_clean_ss, N)
        query_norm_tc_split = np.array_split(query_df_clean_tc, N)
        print(len(query_norm_ix_split[0]))

        ix_split_mean = [arr["time_ms"].mean() for arr in query_norm_ix_split]
        # ix_split_std = [arr["time_ms"].std() for arr in query_norm_ix_split]

        mi_split_mean = [arr["time_ms"].mean() for arr in query_norm_mi_split]
        # mi_split_std = [arr["time_ms"].std() for arr in query_norm_mi_split]

        nix_split_mean = [arr["time_ms"].mean() for arr in query_norm_nix_split]
        # nix_split_std = [arr["time_ms"].std() for arr in query_norm_nix_split]

        ss_split_mean = [arr["time_ms"].mean() for arr in query_norm_ss_split]
        # ss_split_std = [arr["time_ms"].std() for arr in query_norm_ss_split]

        tc_split_mean = [arr["time_ms"].mean() for arr in query_norm_tc_split]
        # tc_split_std = [arr["time_ms"].std() for arr in query_norm_tc_split]

        del query_df_norm_ix
        del query_df_norm_mi
        del query_df_norm_nix
        del query_df_norm_ss
        del query_df_norm_tc

        del query_df_clean_ix
        del query_df_clean_mi
        del query_df_clean_nix
        del query_df_clean_ss
        del query_df_clean_tc

        mins = []
        mins.append(np.array(ix_split_mean).min())
        mins.append(np.array(mi_split_mean).min())
        mins.append(np.array(nix_split_mean).min())
        mins.append(np.array(ss_split_mean).min())
        mins.append(np.array(tc_split_mean).min())

        print(mins)
        # print(np.array(mins).min())

        ix_split_mean = np.array(ix_split_mean) / skl_min[0]
        # ix_split_std = np.array(ix_split_std) / np.array(ix_split_std).min()

        mi_split_mean = np.array(mi_split_mean) / skl_min[1]
        # mi_split_std = np.array(mi_split_std) / np.array(mi_split_std).min()

        nix_split_mean = np.array(nix_split_mean) / skl_min[2]
        # nix_split_std = np.array(nix_split_std) / np.array(nix_split_std).min()

        ss_split_mean = np.array(ss_split_mean) / skl_min[3]
        # ss_split_std = np.array(ss_split_std) / np.array(ss_split_std).min()

        tc_split_mean = np.array(tc_split_mean) / skl_min[4]
        # tc_split_std = np.array(tc_split_std) / np.array(tc_split_std).min()

        # assert len(nix_split_mean) == len(nix_split_std)

        ss_dict = { "id": range(0, N), "mean_time": ss_split_mean, "GC": ["semi-space"]*N }
        ix_dict = { "id": range(0, N), "mean_time": ix_split_mean, "GC": ["immix"]*N }
        nix_dict = { "id": range(0, N), "mean_time": nix_split_mean, "GC": ["immix, non-moving"]*N }
        mi_dict = { "id": range(0, N), "mean_time": mi_split_mean, "GC": ["mark-sweep, mi"]*N }
        tc_dict = { "id": range(0, N), "mean_time": tc_split_mean, "GC": ["mark-sweep, tc"]*N }

        percentile_graphs = pd.concat([
                pd.DataFrame.from_dict(ss_dict),
                pd.DataFrame.from_dict(ix_dict),
                pd.DataFrame.from_dict(nix_dict),
                pd.DataFrame.from_dict(mi_dict),
                pd.DataFrame.from_dict(tc_dict),
            ], ignore_index=True)

        plot_execution_time_graph(percentile_graphs, f"Skylake_N{num_gc}", 1.0, 3.0)


    print("Finish normalizing queries")
