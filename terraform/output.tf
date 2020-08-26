// Copyright 2020 Oxide Computer Company

output "db_ip" {
  value = aws_instance.db.*.public_ip
}

output "loadgen_ip" {
  value = aws_instance.loadgen.*.public_ip
}

output "mon_ip" {
  value = aws_instance.mon.*.public_ip
}
