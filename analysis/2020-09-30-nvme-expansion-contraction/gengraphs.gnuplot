set terminal png size 1200,600

# Configure an x-axis based on ISO 8061 timestamps.
set xdata time;
set timefmt "%Y-%m-%dT%H:%M:%SZ"
set format x "%H:%M:%SZ"

set xrange ["2020-09-30T19:00:00Z":"2020-10-01T00:30:00Z"]

# Add padding around the graph.
set yrange [0:*]
set offsets graph 0, 0, 0.1, 0

# Draw vertical lines for the expansion and contraction events.
set arrow from "2020-09-30T19:31:00Z", graph 0 to "2020-09-30T19:31:00Z", graph 1 nohead linecolor "sandybrown"
set arrow from "2020-09-30T21:09:00Z", graph 0 to "2020-09-30T21:09:00Z", graph 1 nohead linecolor "sandybrown"
set arrow from "2020-09-30T22:15:00Z", graph 0 to "2020-09-30T22:15:00Z", graph 1 nohead linecolor "sandybrown"

set arrow from "2020-09-30T22:58:00Z", graph 0 to "2020-09-30T22:58:00Z", graph 1 nohead linecolor "dark-red"
set arrow from "2020-09-30T23:26:00Z", graph 0 to "2020-09-30T23:26:00Z", graph 1 nohead linecolor "dark-red"
set arrow from "2020-09-30T23:47:00Z", graph 0 to "2020-09-30T23:47:00Z", graph 1 nohead linecolor "dark-red"

set title "Client-reported query throughput during CockroachDB cluster expansion and contraction"
set ylabel "queries per second"
set output "graph-throughput.png"
plot "plot-data-writes-throughput.out" using 1:2 with lines title "write throughput", \
    "plot-data-reads-throughput.out" using 1:2 with lines title "read throughput"

set logscale y

set title "Client-reported read latency during CockroachDB cluster expansion and contraction"
set ylabel "milliseconds (log scale)"
set output "graph-read-latency.png"
plot "plot-data-reads-p99-latency.out" using 1:2 with points title "p99 latency", \
     "plot-data-reads-pMax-latency.out" using 1:2 with points title "pMax latency"

set title "Client-reported write latency during CockroachDB cluster expansion and contraction"
set ylabel "milliseconds (log scale)"
set output "graph-write-latency.png"
plot "plot-data-writes-p99-latency.out" using 1:2 with points title "p99 latency", \
     "plot-data-writes-pMax-latency.out" using 1:2 with points title "pMax latency"

