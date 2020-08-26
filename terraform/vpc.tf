// Copyright 2020 Oxide Computer Company

resource "aws_vpc" "crdb_exploration" {
  cidr_block           = "192.168.0.0/16" // well more than we need
  enable_dns_hostnames = true

  tags = {
    Name = "crdb_exploration"
  }
}

// We don't actually care about the specific AZ, we just want a single subnet
// so that all our instances are located within the same AZ.
resource "aws_subnet" "crdb_exploration" {
  vpc_id     = aws_vpc.crdb_exploration.id
  cidr_block = "192.168.1.0/24" // plenty of addresses

  tags = {
    Name = "crdb_exploration"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.crdb_exploration.id

  tags = {
    Name = "crdb_exploration"
  }
}

resource "aws_route" "r" {
  route_table_id         = aws_vpc.crdb_exploration.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}
