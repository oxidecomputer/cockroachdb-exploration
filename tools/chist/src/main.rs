/*!
 * chist: parse `cockroach workload` histogram files.
 * Reference:
 * https://github.com/cockroachdb/cockroach/blob/master/pkg/workload/histogram/histogram.go
 * This appears to be the implementation used to generate these, but we have not
 * verified that.
 */

use anyhow::Context;
use chrono::DateTime;
use chrono::Utc;
use hdrhistogram::Histogram;
use hdrhistogram::HistogramSnapshot;
use serde::Deserialize;
use std::collections::BTreeSet;
use std::env;
use std::fs::File;
use std::io::BufReader;
use std::path::Path;

#[macro_use]
extern crate anyhow;

fn main() -> Result<(), anyhow::Error> {
    let argv = env::args().collect::<Vec<String>>();

    if argv.len() < 2 || argv.len() > 3 {
        return Err(anyhow!("usage: chist [-s | --summarize] FILE"));
    }

    let (summarize, filename) = if argv.len() > 2 {
        // XXX This isn't right.  Bail out if argv[0] _isn't_ one of these
        // things.
        (argv[1] == "-s" || argv[1] == "--summarize", &argv[2])
    } else {
        (false, &argv[1])
    };

    let records = read_hist_file(Path::new(filename))?;
    if summarize {
        do_summarize(records);
    } else {
        let mut line = 0;
        let mut t_elapsed = 0;
        for record in records {
            /* XXX print out just reads for now */

            if record.name != "read" {
                continue;
            }

            t_elapsed += record.elapsed;
            let snapshot = HistogramSnapshot::from(record.hist.clone());
            let histogram = Histogram::new_from_snapshot(&snapshot)
                .with_context(|| "loading histogram")?;
            let throughput =
                histogram.len() as f64 / (record.elapsed as f64 / 1000000000.);
            let p50 = histogram.value_at_quantile(0.5) as f64 / 1000000.;
            let p95 = histogram.value_at_quantile(0.95) as f64 / 1000000.;
            let p99 = histogram.value_at_quantile(0.99) as f64 / 1000000.;
            let pmax = histogram.max() as f64 / 1000000.;

            if line == 0 {
                println!(
                    "{:35} {:>6} {:>7} {:>7} {:>7} {:>7} {:>7}",
                    "TIME",
                    "ELAPSD",
                    "OPS/SEC",
                    "p50(ms)",
                    "p95(ms)",
                    "p99(ms)",
                    "pMax",
                );
            }

            println!(
                "{:35} {:>6.1} {:7.1} {:7.1} {:7.1} {:7.1} {:7.1}",
                record.now.to_rfc3339(),
                t_elapsed as f64 / 1000000000.,
                throughput,
                p50,
                p95,
                p99,
                pmax,
            );

            line += 1;
        }
    }

    Ok(())
}

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
#[allow(unused)]
struct HistRecord {
    name: String,
    elapsed: u64,
    now: DateTime<Utc>,
    hist: HistSnapshot,
}

#[derive(Deserialize, Clone)]
#[serde(rename_all = "PascalCase")]
#[allow(unused)]
struct HistSnapshot {
    lowest_trackable_value: u64,
    highest_trackable_value: u64,
    significant_figures: u8,
    counts: Vec<u64>,
}

impl From<HistSnapshot> for HistogramSnapshot<u64> {
    fn from(source: HistSnapshot) -> HistogramSnapshot<u64> {
        HistogramSnapshot {
            lowest_trackable_value: source.lowest_trackable_value,
            highest_trackable_value: source.highest_trackable_value,
            significant_figures: source.significant_figures,
            counts: source.counts,
        }
    }
}

fn read_hist_file(filename: &Path) -> Result<Vec<HistRecord>, anyhow::Error> {
    let reader = File::open(filename)
        .with_context(|| format!("open \"{}\"", filename.display()))?;
    let bufreader = BufReader::new(reader);
    let deserializer = serde_json::Deserializer::from_reader(bufreader);
    let stream_deserializer = deserializer.into_iter();
    stream_deserializer
        .collect::<Result<Vec<HistRecord>, serde_json::Error>>()
        .with_context(|| "deserializing records")
}

fn do_summarize(records: Vec<HistRecord>) {
    eprintln!("total records: {}", records.len());

    if records.len() == 0 {
        return;
    }

    /*
     * Figure out how many different names there are and make sure they're
     * consistent throughout the stream.  This isn't strictly required, but it's
     * a useful sanity check about how we expect the data to look.
     */
    let mut set = BTreeSet::new();
    let mut names = Vec::new();
    for rec in &records {
        if set.contains(rec.name.as_str()) {
            break;
        }

        names.push(rec.name.as_str());
        set.insert(rec.name.as_str());
    }

    eprintln!("found distinct names: {}", &names.join(", "));

    let mut which = 0;
    let mut current_timestamp = None;
    for rec in &records {
        let whichname = which % names.len();
        if whichname == 0 {
            current_timestamp = Some(rec.now);
        } else if current_timestamp.unwrap() != rec.now {
            eprintln!(
                "warning: record {}: expected timestamp {}, found {}",
                which + 1,
                current_timestamp.unwrap(),
                rec.now
            );
        }

        let expected = names[which % names.len()];
        which += 1;
        if expected != rec.name {
            // XXX record number
            eprintln!(
                "warning: record {}: expected record with name \"{}\", \
                found \"{}\"",
                which + 1,
                expected,
                rec.name
            );
        }
    }

    eprintln!("initial timestamp: {}", records[0].now.to_rfc3339());

    if records.len() > names.len() {
        let next_timestamp = records[names.len()].now;
        let next_duration = next_timestamp - records[0].now;

        let last_timestamp = records[records.len() - 1].now;
        let last_duration = last_timestamp - records[0].now;

        let ntimestamps = records.len() / names.len();
        eprintln!("expected distinct timestamps:     {}", ntimestamps);
        eprintln!(
            "expected time between timestamps: {} ms",
            last_duration.num_milliseconds() / (ntimestamps as i64)
        );

        eprintln!(
            "second  timestamp: {} ({} ms later)",
            next_timestamp.to_rfc3339(),
            next_duration.num_milliseconds()
        );

        eprintln!(
            "final   timestamp: {} ({} ms since start)",
            last_timestamp.to_rfc3339(),
            last_duration.num_milliseconds()
        );
    }
}
