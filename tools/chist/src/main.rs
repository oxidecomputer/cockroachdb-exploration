/*!
 * chist: parse `cockroach workload` histogram files.
 * Reference:
 * https://github.com/cockroachdb/cockroach/blob/master/pkg/workload/histogram/histogram.go
 */

use anyhow::Context;
use chrono::DateTime;
use chrono::SecondsFormat;
use chrono::Utc;
use hdrhistogram::Histogram;
use hdrhistogram::HistogramSnapshot;
use serde::Deserialize;
use std::collections::BTreeSet;
use std::convert::TryInto;
use std::env;
use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use std::process;

#[macro_use]
extern crate anyhow;

const USAGE_MESSAGE: &str = "\
usage: chist summarize FILE...
       chist print FILE...

All input files are histogram files from `cockroachdb workload`.";

fn usage() -> ! {
    eprintln!("{}", USAGE_MESSAGE);
    process::exit(2);
}

fn main() -> Result<(), anyhow::Error> {
    let argv = env::args().collect::<Vec<String>>();

    if argv.len() < 3 {
        usage();
    }

    let command = &argv[1];
    let files = &argv[2..];

    if command == "summarize" {
        for filename in files {
            println!("file: {}", filename);
            let records = read_hist_file(Path::new(filename))?;
            do_summarize(records);
            println!("");
        }
        return Ok(());
    }

    if command != "print" {
        usage();
    }

    /*
     * "file_walkers" is a list with one item for each file that we read.  The
     * item is a HistFileWalkState, which refers to the list of histogram
     * records found in that file.
     */
    let mut file_walkers = files
        .iter()
        .map(|filename| {
            Ok(HistFileWalkState {
                label: filename.clone(),
                records: read_hist_file(Path::new(&filename))?,
                ri: 0,
            })
        })
        .collect::<Result<Vec<HistFileWalkState>, anyhow::Error>>()?;

    println!(
        "{:24} {:>5} {:>2} {:>7} {:>7} {:>7} {:>7} {:>7}",
        "TIME",
        "OPNAM",
        "#",
        "OPS/SEC",
        "p50(ms)",
        "p95(ms)",
        "p99(ms)",
        "pMax",
    );

    /*
     * We will iterate through all records in all files as follows: first, we
     * assume that the records for each file are in timestamp order.  There may
     * be multiple records for each timestamp, in which case they must have
     * different "name" fields.  The set of "name" fields must be consistent for
     * the entire file and also across the files.  The order must also be the
     * same for the entire file and across files.  This makes this process much
     * simpler.  It's also straightforward to identify if these assumptions are
     * violated, and we will bail out in that case.
     *
     * Concretely, we'll maintain a few invariants: we maintain in
     * "current_markers" an index into each file's list of records.  At the
     * beginning of each loop iteration, we have processed all records for all
     * timestamps prior to the "current" record in each file.  In each
     * iteration, we will identify the next timestamp to process, identify all
     * records from each file that will be associated with that timestamp, and
     * process them.  That basically means adding the records' histograms
     * together and printing a single summary line.  We process records with
     * different "name" fields separately -- but as mentioned above, we assume
     * that they always appear in the same order in all files.
     */
    loop {
        let maybe_min_time = file_walkers
            .iter()
            .filter_map(|walk| {
                walk.peek_next_time().and_then(|time| Some((walk, time)))
            })
            .min_by(|(_, t1), (_, t2)| t1.cmp(t2));

        if maybe_min_time.is_none() {
            /* There are no records left in any files.  We're done. */
            break;
        }

        /*
         * We're now processing records for time "min_time".  We will select
         * corresponding records from each file.  How do we know which
         * correspond?  We say they correspond if they're closer to "min_time"
         * than they are to "min_time" + elapsed.  This is the "elapsed" of the
         * current record because we assume it's about the same as for
         * subsequent records in general, and we don't know if there's actually
         * a next record here.
         */
        let (min_time, min_next, elapsed, name) = {
            let (min_walk, min_time) = maybe_min_time.unwrap();
            let min_record = min_walk.peek_record();
            let min_next = min_time
                + chrono::Duration::nanoseconds(
                    min_record.elapsed.try_into().unwrap(),
                );
            (
                min_time.clone(),
                min_next,
                min_record.elapsed.clone(),
                min_record.name.clone(),
            )
        };

        let file_snapshots = file_walkers
            .iter_mut()
            .filter_map(|walk| {
                walk.maybe_eat_record_time_name(&min_time, &min_next, &name)
                    .transpose()
            })
            .collect::<Result<Vec<&HistRecord>, anyhow::Error>>()?
            .iter()
            .map(|hist_record| {
                /*
                 * TODO-cleanup this could probably be cleaner and have better
                 * error reporting if we put these steps into the deserialize
                 * stage.
                 */
                let snapshot =
                    HistogramSnapshot::from(hist_record.hist.clone());
                Histogram::new_from_snapshot(&snapshot)
                    .with_context(|| "loading histogram")
            })
            .collect::<Result<Vec<Histogram<u64>>, anyhow::Error>>()?;

        let empty = Histogram::new_from(file_snapshots.first().unwrap());
        let summary = file_snapshots
            .iter()
            .fold(Ok(empty), |summary, hist| {
                summary.and_then(|mut s| s.add(hist).map(|_| s)) // XXX gross
            })
            .with_context(|| "adding histograms")?;

        let throughput = summary.len() as f64 / (elapsed as f64 / 1000000000.);
        let p50 = summary.value_at_quantile(0.5) as f64 / 1000000.;
        let p95 = summary.value_at_quantile(0.95) as f64 / 1000000.;
        let p99 = summary.value_at_quantile(0.99) as f64 / 1000000.;
        let pmax = summary.max() as f64 / 1000000.;

        println!(
            "{:24} {:>5} {:2} {:7.1} {:7.1} {:7.1} {:7.1} {:7.1}",
            min_time.to_rfc3339_opts(SecondsFormat::Millis, true),
            name,
            file_snapshots.len(),
            throughput,
            p50,
            p95,
            p99,
            pmax,
        );
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
    println!("total records: {}", records.len());

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

    println!("found distinct names: {}", &names.join(", "));

    let mut which = 0;
    let mut current_timestamp = None;
    for rec in &records {
        let whichname = which % names.len();
        if whichname == 0 {
            current_timestamp = Some(rec.now);
        } else if current_timestamp.unwrap() != rec.now {
            println!(
                "warning: record {}: expected timestamp {}, found {}",
                which + 1,
                current_timestamp.unwrap(),
                rec.now
            );
        }

        let expected = names[which % names.len()];
        which += 1;
        if expected != rec.name {
            println!(
                "warning: record {}: expected record with name \"{}\", \
                found \"{}\"",
                which + 1,
                expected,
                rec.name
            );
        }
    }

    println!("initial timestamp: {}", records[0].now.to_rfc3339());

    if records.len() > names.len() {
        let next_timestamp = records[names.len()].now;
        let next_duration = next_timestamp - records[0].now;

        let last_timestamp = records[records.len() - 1].now;
        let last_duration = last_timestamp - records[0].now;

        let ntimestamps = records.len() / names.len();
        println!("expected distinct timestamps:     {}", ntimestamps);
        println!(
            "expected time between timestamps: {} ms",
            last_duration.num_milliseconds() / (ntimestamps as i64)
        );

        println!(
            "second  timestamp: {} ({} ms later)",
            next_timestamp.to_rfc3339(),
            next_duration.num_milliseconds()
        );

        println!(
            "final   timestamp: {} ({} ms since start)",
            last_timestamp.to_rfc3339(),
            last_duration.num_milliseconds()
        );
    }
}

struct HistFileWalkState {
    label: String,
    records: Vec<HistRecord>,
    ri: usize,
}

impl HistFileWalkState {
    fn peek_next_time(&self) -> Option<DateTime<Utc>> {
        self.records.get(self.ri).map(|r| r.now)
    }

    fn peek_record(&self) -> &HistRecord {
        &self.records[self.ri]
    }

    fn maybe_eat_record_time_name(
        &mut self,
        t1: &DateTime<Utc>,
        t2: &DateTime<Utc>,
        name: &str,
    ) -> Result<Option<&HistRecord>, anyhow::Error> {
        if self.ri >= self.records.len() {
            return Ok(None);
        }

        let next = &self.records[self.ri];
        let d1 = (next.now - *t1).num_milliseconds().abs();
        let d2 = (next.now - *t2).num_milliseconds().abs();
        if d1 < d2 {
            if next.name != name {
                return Err(anyhow!(
                    "{}: record {}: expected name \"{}\", found \"{}\"",
                    self.label,
                    self.ri + 1,
                    name,
                    next.name
                ));
            }
        }

        self.ri += 1;
        Ok(Some(next))
    }
}
