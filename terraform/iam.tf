// Copyright 2020 Oxide Computer Company

resource "aws_iam_instance_profile" "primary" {
  role = aws_iam_role.primary.name
}

resource "aws_iam_role" "primary" {
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
                  "arn:aws:s3:::cockroachdb-exploration"
              ]
          },
          {
              "Effect": "Allow",
              "Action": [
                  "s3:Get*"
              ],
              "Resource": [
                  "arn:aws:s3:::cockroachdb-exploration/*"
              ]
          }
      ]
  }
  EOF
}
