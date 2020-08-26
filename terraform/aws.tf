// Copyright 2020 Oxide Computer Company

terraform {
  backend "s3" {
    bucket = "oxide-terraform-backend"
    key    = "crdb-exploration"
    region = "us-west-2"
  }
}

provider "aws" {
  version = "~> 2.0"
  region  = "us-west-2"
}

provider "null" {
  version = "2.1.2"
}
