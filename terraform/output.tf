// Copyright 2020 Oxide Computer Company

output "db_external_ip" {
  value = aws_instance.db.*.public_ip
}

output "loadgen_external_ip" {
  value = aws_instance.loadgen.*.public_ip
}

output "mon_external_ip" {
  value = aws_instance.mon.*.public_ip
}

output "db_internal_ip" {
  value = aws_instance.db.*.private_ip
}

output "loadgen_internal_ip" {
  value = aws_instance.loadgen.*.private_ip
}

output "mon_internal_ip" {
  value = aws_instance.mon.*.private_ip
}
