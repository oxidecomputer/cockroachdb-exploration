// Copyright 2020 Oxide Computer Company

resource "aws_iam_instance_profile" "primary" {
  role = aws_iam_role.primary.name
}

resource "aws_iam_role" "primary" {
  name               = "primary_cluster_${local.cluster_name}"
  assume_role_policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF
}

resource "aws_iam_role_policy" "read_from_s3_bucket" {
  role   = aws_iam_role.primary.id
  policy = <<-EOF
  {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Effect": "Allow",
              "Action": [
                  "s3:List*"
              ],
              "Resource": [
                  "arn:aws:s3:::${local.s3_asset_bucket}"
              ]
          },
          {
              "Effect": "Allow",
              "Action": [
                  "s3:Get*"
              ],
              "Resource": [
                  "arn:aws:s3:::${local.s3_asset_bucket}/*"
              ]
          },
          {
            "Effect": "Allow",
            "Action": "ec2:Describe*",
            "Resource": [ "arn:aws:ec2:us-west-2:*" ]
          }
      ]
  }
  EOF
}

resource "aws_iam_role_policy" "read_ec2" {
  role   = aws_iam_role.primary.id
  policy = <<-EOF
  {
      "Version": "2012-10-17",
      "Statement": [
          {
            "Effect": "Allow",
            "Action": "ec2:Describe*",
            "Resource": "*"
          }
      ]
  }
  EOF
}
