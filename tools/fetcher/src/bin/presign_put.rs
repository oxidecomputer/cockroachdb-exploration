/*!
 * presign_put BUCKET KEY: generates a presigned PUT URL for the given S3
 * bucket and key.
 */

use anyhow::Context;
use rusoto_core::Region;
use rusoto_credential::DefaultCredentialsProvider;
use rusoto_credential::ProvideAwsCredentials;
use rusoto_s3::util::PreSignedRequest;
use rusoto_s3::util::PreSignedRequestOption;
use rusoto_s3::PutObjectRequest;
use std::time::Duration;

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
    let provider = DefaultCredentialsProvider::new().with_context(|| "cred provider")?;

    let put_request = PutObjectRequest {
        bucket,
        key,
        ..Default::default()
    };

    let creds = provider
        .credentials()
        .await
        .with_context(|| "credentials")?;
    let opts = PreSignedRequestOption {
        expires_in: Duration::from_secs(3600),
    };
    let presigned = put_request.get_presigned_url(&region, &creds, &opts);
    eprintln!("{}", presigned);

    Ok(())
}
