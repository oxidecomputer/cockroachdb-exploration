/*!
 * fetcher BUCKET KEY: fetches the contents of the given S3 bucket and key to a
 * local path.  This is pretty specific to the VM setup process for
 * cockroachdb_exploration.
 */

use anyhow::Context;
use rusoto_core::HttpClient;
use rusoto_core::Region;
use rusoto_credential::InstanceMetadataProvider;
use rusoto_s3::GetObjectRequest;
use rusoto_s3::S3Client;
use rusoto_s3::S3;

#[macro_use]
extern crate anyhow;

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    let _ = env_logger::try_init();

    let args = std::env::args().collect::<Vec<String>>();
    if args.len() != 3 {
        return Err(anyhow!("usage: {} S3_BUCKET S3_KEY", args[0]));
    }

    let bucket = args[1].clone();
    let key = args[2].clone();
    let region = Region::UsWest2;
    let provider = InstanceMetadataProvider::new();
    let http_client =
        HttpClient::new().with_context(|| "creating HTTP client")?;
    let s3 = S3Client::new_with(http_client, provider, region);

    let object_output = s3
        .get_object(GetObjectRequest {
            bucket,
            key,
            ..Default::default()
        })
        .await
        .with_context(|| "fetching object")?;

    let body = object_output
        .body
        .ok_or_else(|| anyhow!("object missing body"))?;
    let mut outfile = tokio::io::stdout();
    tokio::io::copy(&mut body.into_async_read(), &mut outfile)
        .await
        .with_context(|| "copying to stdout")?;

    Ok(())
}
