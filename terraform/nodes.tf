// Copyright 2020 Oxide Computer Company

locals {
  // Instance types used for each component.
  db_instance_type      = "c4.large"
  loadgen_instance_type = "c4.large"
  mon_instance_type     = "t2.medium"

  // Count of cluster nodes to create.
  ndbs = 3

  // This key should be imported into AWS and loaded into your SSH agent.
  ssh_key_name = "dap-terraform"
}

// Grab the latest OmniOS image.
data "aws_ami" "image" {
  owners      = ["313551840421"]
  most_recent = true

  filter {
    name   = "name"
    values = ["*OmniOS*"]
  }
}

// CockroachDB cluster nodes
resource "aws_instance" "db" {
  count = local.ndbs

  ami                         = data.aws_ami.image.id
  instance_type               = local.db_instance_type
  key_name                    = local.ssh_key_name
  subnet_id                   = aws_subnet.crdb_exploration.id
  vpc_security_group_ids      = [aws_security_group.crdb_exploration.id]
  associate_public_ip_address = true

  tags = {
    Project = "crdb_exploration"
    Name    = "crdb_exploration_db_${count.index}"
  }

  connection {
    type = "ssh"
    user = "root"
    host = self.public_ip
  }

  //
  // We use a sequence of provisioners to set up the VM the way we want it.
  //
  provisioner "file" {
    source      = "../vminit/vminit.sh"
    destination = "/var/tmp/vminit.sh"
  }

  provisioner "file" {
    source      = "../vminit/vminit.tar.gz"
    destination = "/var/tmp/vminit.tar.gz"
  }

  provisioner "remote-exec" {
    inline = [
      "bash -x /var/tmp/vminit.sh \"${self.private_ip}\"",
    ]
  }
}

//
// We use a null resource to reconfigure the cluster (specifically, the
// "--join" argument used when starting CockroachDB) when any of the set of
// private IPs changes.  This implementation restarts all of the cluster
// instances, which is definitely not what we want in production, but should be
// fine for our testing.
//
resource "null_resource" "cluster_config" {
  count = local.ndbs

  triggers = {
    my_id       = aws_instance.db[count.index].id
    cluster_ips = "${join(",", aws_instance.db.*.private_ip)}"
  }

  connection {
    type = "ssh"
    user = "root"
    host = aws_instance.db[count.index].public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "svccfg -s cockroachdb setprop config/other_internal_ips = \"${join(",", aws_instance.db.*.private_ip)}\"",
      "svcadm refresh cockroachdb:default",
      "svcadm disable -st cockroachdb:default",
      "svcadm enable -s cockroachdb:default",
    ]
  }
}

// Load generators
resource "aws_instance" "loadgen" {
  // Disable for now, while we're still testing the cluster.
  count = 2

  ami                         = data.aws_ami.image.id
  instance_type               = local.loadgen_instance_type
  key_name                    = local.ssh_key_name
  subnet_id                   = aws_subnet.crdb_exploration.id
  vpc_security_group_ids      = [aws_security_group.crdb_exploration.id]
  associate_public_ip_address = true

  tags = {
    Project = "crdb_exploration"
    Name    = "crdb_exploration_loadgen_${count.index}"
  }

  connection {
    type = "ssh"
    user = "root"
    host = self.public_ip
  }

  //
  // We set up load generators exactly the same as regular database nodes except
  // that we don't configure or enable the CockroachDB service.  That happens as
  // part of a separate null resource for the database instances, so this part
  // looks the same as for the database instances.
  //
  provisioner "file" {
    source      = "../vminit/vminit.sh"
    destination = "/var/tmp/vminit.sh"
  }

  provisioner "file" {
    source      = "../vminit/vminit.tar.gz"
    destination = "/var/tmp/vminit.tar.gz"
  }

  provisioner "remote-exec" {
    inline = [
      "bash -x /var/tmp/vminit.sh \"${self.private_ip}\"",
    ]
  }
}

// Monitoring VM (for Prometheus and Grafana)
resource "aws_instance" "mon" {
  // Disable for now, while we're still testing the cluster.
  count = 0

  ami                         = data.aws_ami.image.id
  instance_type               = local.mon_instance_type
  key_name                    = local.ssh_key_name
  subnet_id                   = aws_subnet.crdb_exploration.id
  vpc_security_group_ids      = [aws_security_group.crdb_exploration.id]
  associate_public_ip_address = true

  tags = {
    Project = "crdb_exploration"
    Name    = "crdb_exploration_mon_${count.index}"
  }
}

resource "aws_security_group" "crdb_exploration" {
  name   = "crdb_exploration"
  vpc_id = aws_vpc.crdb_exploration.id

  tags = {
    Name = "crdb_exploration"
  }
}

// Allow inbound ssh connections.
resource "aws_security_group_rule" "crdb_exploration_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.crdb_exploration.id
}

// Allow any inbound connections from this security group.
resource "aws_security_group_rule" "crdb_exploration_local_in" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65536
  protocol                 = "all"
  security_group_id        = aws_security_group.crdb_exploration.id
  source_security_group_id = aws_security_group.crdb_exploration.id
}

// Allow all outbound connections.
resource "aws_security_group_rule" "crdb_exploration_out" {
  type              = "egress"
  from_port         = 0
  to_port           = 65536
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.crdb_exploration.id
}
