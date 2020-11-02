// Copyright 2020 Oxide Computer Company

locals {
  cluster_name = "main" // "big" cluster, round 3 of testing

  // Instance types used for each component.
  db_instance_type      = "m4.large"
  dbnvme_instance_type  = "i3.large"
  loadgen_instance_type = "c4.large"
  mon_instance_type     = "t2.medium"

  // Count of cluster nodes to create.
  ndbs = 0
  // Count of NVME cluster nodes to create.
  ndbs_nvme = 3

  // This key should be imported into AWS and loaded into your SSH agent.
  ssh_key_name = "dap-terraform"

  // This is the S3 bucket containing VM provisioning assets.
  s3_asset_bucket = "oxide-cockroachdb-exploration-test"

  // AMI to use for all VMs except the NVME DB nodes.
  ami = "ami-0bc33ade03d07d4d3"
  // AMI to use for the NVME DB nodes.
  nvme_ami = "ami-0bc33ade03d07d4d3"
}

// CockroachDB cluster nodes
resource "aws_instance" "db" {
  count = local.ndbs

  // ami                         = data.aws_ami.image.id
  ami                         = local.ami
  instance_type               = local.db_instance_type
  key_name                    = local.ssh_key_name
  subnet_id                   = aws_subnet.crdb_exploration.id
  vpc_security_group_ids      = [aws_security_group.crdb_exploration.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.primary.id

  ebs_block_device {
    device_name = "sdf"
    volume_size = 60
    volume_type = "io1"
    iops        = 1000
  }

  tags = {
    Project = "crdb_exploration"
    Role    = "crdb_exploration_db"
    Name    = "crdb_exploration_db_${count.index + 1}"
    Cluster = "${local.cluster_name}"
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
    source      = "../vminit/fetcher.gz"
    destination = "/var/tmp/fetcher.gz"
  }

  provisioner "remote-exec" {
    inline = [
      "bash -x /var/tmp/vminit.sh \"db\" \"db${count.index + 1}\" \"${self.private_ip}\" \"${local.s3_asset_bucket}\"",
    ]
  }
}

resource "aws_instance" "db_nvme" {
  count = local.ndbs_nvme

  ami                         = local.nvme_ami
  instance_type               = local.dbnvme_instance_type
  key_name                    = local.ssh_key_name
  subnet_id                   = aws_subnet.crdb_exploration.id
  vpc_security_group_ids      = [aws_security_group.crdb_exploration.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.primary.id

  tags = {
    Project = "crdb_exploration"
    Role    = "crdb_exploration_nvmedb"
    Name    = "crdb_exploration_nvmedb_${count.index + 1}"
    Cluster = "${local.cluster_name}"
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
    source      = "../vminit/fetcher.gz"
    destination = "/var/tmp/fetcher.gz"
  }

  provisioner "remote-exec" {
    inline = [
      "bash -x /var/tmp/vminit.sh \"db\" \"nvmedb${count.index + 1}\" \"${self.private_ip}\" \"${local.s3_asset_bucket}\"",
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
    ]
  }
}

// We do the same for the NVME cluster.
resource "null_resource" "cluster_config_nvme" {
  count = local.ndbs_nvme

  triggers = {
    my_id       = aws_instance.db_nvme[count.index].id
    cluster_ips = "${join(",", aws_instance.db_nvme.*.private_ip)}"
  }

  connection {
    type = "ssh"
    user = "root"
    host = aws_instance.db_nvme[count.index].public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "svccfg -s cockroachdb setprop config/other_internal_ips = \"${join(",", aws_instance.db_nvme.*.private_ip)}\"",
      "svcadm refresh cockroachdb:default",
    ]
  }
}

// Load generators
resource "aws_instance" "loadgen" {
  count = 1

  // ami                         = data.aws_ami.image.id
  ami                         = local.ami
  instance_type               = local.loadgen_instance_type
  key_name                    = local.ssh_key_name
  subnet_id                   = aws_subnet.crdb_exploration.id
  vpc_security_group_ids      = [aws_security_group.crdb_exploration.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.primary.id

  root_block_device {
    volume_size = 10
  }

  tags = {
    Project = "crdb_exploration"
    Role    = "crdb_exploration_loadgen"
    Name    = "crdb_exploration_loadgen_${count.index}"
    Cluster = "${local.cluster_name}"
  }

  connection {
    type = "ssh"
    user = "root"
    host = self.public_ip
  }

  // See "db" instances.
  provisioner "file" {
    source      = "../vminit/vminit.sh"
    destination = "/var/tmp/vminit.sh"
  }

  provisioner "file" {
    source      = "../vminit/fetcher.gz"
    destination = "/var/tmp/fetcher.gz"
  }

  provisioner "remote-exec" {
    inline = [
      "bash -x /var/tmp/vminit.sh \"loadgen\" \"loadgen${count.index}\" \"${self.private_ip}\" \"${local.s3_asset_bucket}\"",
    ]
  }
}

// Monitoring VM (for Prometheus and Grafana)
resource "aws_instance" "mon" {
  count = 1

  // ami                         = data.aws_ami.image.id
  ami                         = local.ami
  instance_type               = local.mon_instance_type
  key_name                    = local.ssh_key_name
  subnet_id                   = aws_subnet.crdb_exploration.id
  vpc_security_group_ids      = [aws_security_group.crdb_exploration.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.primary.id

  root_block_device {
    volume_size = 30
  }

  tags = {
    Project = "crdb_exploration"
    Role    = "crdb_exploration_mon"
    Name    = "crdb_exploration_mon_${count.index}"
    Cluster = "${local.cluster_name}"
  }

  connection {
    type = "ssh"
    user = "root"
    host = self.public_ip
  }

  // See "db" instances.
  provisioner "file" {
    source      = "../vminit/vminit.sh"
    destination = "/var/tmp/vminit.sh"
  }

  provisioner "file" {
    source      = "../vminit/fetcher.gz"
    destination = "/var/tmp/fetcher.gz"
  }

  provisioner "remote-exec" {
    inline = [
      "bash -x /var/tmp/vminit.sh \"mon\" \"mon${count.index}\" \"${self.private_ip}\" \"${local.s3_asset_bucket}\"",
    ]
  }
}

resource "aws_security_group" "crdb_exploration" {
  name   = "crdb_exploration_${local.cluster_name}"
  vpc_id = aws_vpc.crdb_exploration.id

  tags = {
    Name    = "crdb_exploration"
    Cluster = "${local.cluster_name}"
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
