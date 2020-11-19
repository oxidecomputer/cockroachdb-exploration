#!/bin/bash

#
# Quick bash script to start a relatively low-level workload against a set of
# CockroachDB nodes.  Modify the list of nodes below when you run this.
#

date="$(date +%FT%TZ)"
for node in 243 232 29; do
	nohup cockroach workload run kv --histograms kv-histograms-$node-$date.out --concurrency 4 --max-rate=333 --display-every=1s --read-percent 80 --tolerate-errors postgresql://root@192.168.1.$node:26257/kv?sslmode=disable > loadgen-summary-$node-$date.out 2>&1 &
done
