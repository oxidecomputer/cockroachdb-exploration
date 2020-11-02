// Copyright 2020 Oxide Computer Company

resource "aws_vpc" "crdb_exploration" {
  cidr_block           = "192.168.0.0/16" // well more than we need
  enable_dns_hostnames = true

  tags = {
    Name    = "crdb_exploration"
    Cluster = "${local.cluster_name}"
  }
}

//
// We'll put all of our instances in one AZ (and so on one subnet) for now.  We
// don't care much which AZ this winds up in, except that the instance types
// that we want are not available in us-west-2d.
//
resource "aws_subnet" "crdb_exploration" {
  vpc_id            = aws_vpc.crdb_exploration.id
  cidr_block        = "192.168.1.0/24" // plenty of addresses
  availability_zone = "us-west-2a"

  tags = {
    Name    = "crdb_exploration"
    Cluster = "${local.cluster_name}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.crdb_exploration.id

  tags = {
    Name    = "crdb_exploration"
    Cluster = "${local.cluster_name}"
  }
}

resource "aws_route" "r" {
  route_table_id         = aws_vpc.crdb_exploration.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}
