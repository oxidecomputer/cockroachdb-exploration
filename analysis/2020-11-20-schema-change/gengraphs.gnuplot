set terminal png size 1200,600

# Configure an x-axis based on ISO 8061 timestamps.
set xdata time;
set timefmt "%Y-%m-%dT%H:%M:%SZ"
set format x "%H:%M:%SZ"

set xrange ["2020-11-20T19:30:00Z":"2020-11-21T00:30:00Z"]

# Add padding around the graph.
set yrange [0:*]
set offsets graph 0, 0, 0.1, 0

# Highlight the regions during schema change events
set obj 1 rectangle behind \
    from first "2020-11-20T19:56:09Z", graph 0 \
    to   first "2020-11-20T19:56:12Z", graph 1 \
    back \
    fillcolor rgb "#eeeeee" \
    fillstyle solid 1.0 noborder

set obj 2 rectangle behind \
    from first "2020-11-20T19:58:22Z", graph 0 \
    to   first "2020-11-20T21:04:02Z", graph 1 \
    back \
    fillcolor rgb "#eeeeee" \
    fillstyle solid 1.0 noborder

set obj 3 rectangle behind \
    from first "2020-11-20T22:04:12Z", graph 0 \
    to   first "2020-11-20T23:03:09Z", graph 1 \
    back \
    fillcolor rgb "#eeeeee" \
    fillstyle solid 1.0 noborder

set obj 4 rectangle behind \
    from first "2020-11-20T23:26:42Z", graph 0 \
    to   first "2020-11-21T00:57:49Z", graph 1 \
    back \
    fillcolor rgb "#eeeeee" \
    fillstyle solid 1.0 noborder

set title "Client-reported query throughput during CockroachDB cluster expansion and contraction (2020-11-02)"
set ylabel "queries per second"
set output "graph-throughput.png"
plot "plot-data-writes-throughput.out" using 1:2 with lines title "write throughput", \
    "plot-data-reads-throughput.out" using 1:2 with lines title "read throughput"

set logscale y

set title "Client-reported read latency during CockroachDB cluster expansion and contraction (2020-11-02)"
set ylabel "milliseconds (log scale)"
set output "graph-read-latency.png"
plot "plot-data-reads-p99-latency.out" using 1:2 with points title "p99 latency", \
     "plot-data-reads-pMax-latency.out" using 1:2 with points title "pMax latency"

set title "Client-reported write latency during CockroachDB cluster expansion and contraction (2020-11-02)"
set ylabel "milliseconds (log scale)"
set output "graph-write-latency.png"
plot "plot-data-writes-p99-latency.out" using 1:2 with points title "p99 latency", \
     "plot-data-writes-pMax-latency.out" using 1:2 with points title "pMax latency"

