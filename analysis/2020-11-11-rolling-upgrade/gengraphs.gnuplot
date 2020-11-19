set terminal png size 1200,600

# Configure an x-axis based on ISO 8061 timestamps.
set xdata time;
set timefmt "%Y-%m-%dT%H:%M:%SZ"
set format x "%H:%M:%SZ"

set xrange ["2020-11-10T23:00:00Z":"2020-11-10T23:30:00Z"]

# Add padding around the graph.
set yrange [0:*]
set offsets graph 0, 0, 0.3, 0

set title "Client-reported query throughput during CockroachDB rolling upgrade (2020-11-11)"
set yrange [0:400]
set ylabel "queries per second"
set output "graph-throughput.png"
plot "plot-n1-throughput.out" using 1:($2+$3) with lines title "reads + writes for n1", \
     "plot-n2-throughput.out" using 1:($2+$3) with lines title "reads + writes for n2", \
     "plot-n3-throughput.out" using 1:($2+$3) with lines title "reads + writes for n3"

set title "Client-reported query throughput during CockroachDB rolling upgrade (2020-11-11)"
set ylabel "queries per second"
set output "graph-throughput-bytype.png"
plot "plot-n1-read-throughput.out" using 1:2 with lines title "reads from n1", \
    "plot-n1-write-throughput.out" using 1:2 with lines title "writes to n1", \
    "plot-n2-read-throughput.out" using 1:2 with lines title "reads from n2", \
    "plot-n2-write-throughput.out" using 1:2 with lines title "writes to n2", \
    "plot-n3-read-throughput.out" using 1:2 with lines title "reads from n3", \
    "plot-n3-write-throughput.out" using 1:2 with lines title "writes to n3"

set title "Client-reported query throughput during CockroachDB rolling upgrade, n1 only (2020-11-11)"
set ylabel "queries per second"
set output "graph-throughput-n1.png"
plot "plot-n1-read-throughput.out" using 1:2 with lines title "reads from n1", \
    "plot-n1-write-throughput.out" using 1:2 with lines title "writes to n1"

set title "Client-reported query throughput during CockroachDB rolling upgrade, n2 only (2020-11-11)"
set ylabel "queries per second"
set output "graph-throughput-n2.png"
plot "plot-n2-read-throughput.out" using 1:2 with lines title "reads from n2", \
    "plot-n2-write-throughput.out" using 1:2 with lines title "writes to n2"

set title "Client-reported query throughput during CockroachDB rolling upgrade, n3 only (2020-11-11)"
set ylabel "queries per second"
set output "graph-throughput-n3.png"
plot "plot-n3-read-throughput.out" using 1:2 with lines title "reads from n3", \
    "plot-n3-write-throughput.out" using 1:2 with lines title "writes to n3"

set yrange [0:*]
set logscale y

set title "Client-reported latency during CockroachDB rolling upgrade, n1 only (2020-11-11)"
set ylabel "milliseconds (log scale)"
set output "graph-latency-n1-pMax.png"
plot \
     "plot-n1-read-pMax.out" using 1:2 with points title "read pMax", \
     "plot-n1-write-pMax.out" using 1:2 with points title "write pMax"

set title "Client-reported latency during CockroachDB rolling upgrade, n2 only (2020-11-11)"
set ylabel "milliseconds (log scale)"
set output "graph-latency-n2-pMax.png"
plot \
     "plot-n2-read-pMax.out" using 1:2 with points title "read pMax", \
     "plot-n2-write-pMax.out" using 1:2 with points title "write pMax"

set title "Client-reported latency during CockroachDB rolling upgrade, n3 only (2020-11-11)"
set ylabel "milliseconds (log scale)"
set output "graph-latency-n3-pMax.png"
plot \
     "plot-n3-read-pMax.out" using 1:2 with points title "read pMax", \
     "plot-n3-write-pMax.out" using 1:2 with points title "write pMax"

set title "Client-reported latency during CockroachDB rolling upgrade, n1 only (2020-11-11)"
set ylabel "milliseconds (log scale)"
set output "graph-latency-n1-p99.png"
plot \
     "plot-n1-read-p99.out" using 1:2 with points title "read p99", \
     "plot-n1-write-p99.out" using 1:2 with points title "write p99"

set title "Client-reported latency during CockroachDB rolling upgrade, n2 only (2020-11-11)"
set ylabel "milliseconds (log scale)"
set output "graph-latency-n2-p99.png"
plot \
     "plot-n2-read-p99.out" using 1:2 with points title "read p99", \
     "plot-n2-write-p99.out" using 1:2 with points title "write p99"

set title "Client-reported latency during CockroachDB rolling upgrade, n3 only (2020-11-11)"
set ylabel "milliseconds (log scale)"
set output "graph-latency-n3-p99.png"
plot \
     "plot-n3-read-p99.out" using 1:2 with points title "read p99", \
     "plot-n3-write-p99.out" using 1:2 with points title "write p99"
