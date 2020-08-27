#!/bin/bash

#
# dbinit.sh MY_INTERNAL_IP: Terraform remote-exec provisioner script that sets
# up a fresh OmniOS VM as a CockroachDB server.
#

set -o errexit
set -o pipefail
set -o xtrace

arg0="$(basename "${BASH_SOURCE[0]}")"

function fail
{
	echo "$arg0: $@" >&2
	exit 1
}

#
# Check prerequisites.
#
[[ -f /tmp/cockroachdb.xml ]] || fail "missing /tmp/cockroachdb.xml"
[[ -f /tmp/ntpfix.xml ]] || fail "missing /tmp/ntpfix.xml"
[[ -f /tmp/cockroachdb.tar.gz ]] || fail "missing /tmp/cockroachdb.tar.gz"
[[ $# == 1 ]] || fail "expected exactly one argument (internal IP)"

#
# Configure NTP.  CockroachDB requires all nodes to be pretty closely
# synchronized.  Empirically, it's not sufficient to let the stock ntpd to do
# this.  We want to make sure we're sync'd up now and also after every boot,
# before we start CockroachDB.  Long term, we probably want to look at chrony
# for this.  For now, we'll configure ntpd to use Amazon's Time Service at
# 169.254.169.123.  We'll also install a boot-time service to run `ntpdate` to
# adjust the clock immediately.
#
# There's also an issue here where "svcadm enable -s ntp" fails because of a
# dependency problem, but it actually comes up fine.  Instead, we start it
# without waiting.  We already sync'd up with `ntpdate`.
#
svcadm disable -s ntp

svccfg import /tmp/ntpfix.xml
svcadm enable -s ntpfix

if ! [[ -e /etc/inet/ntp.conf_orig ]]; then
	cp /etc/inet/ntp.conf /etc/inet/ntp.conf.orig
fi
cat > /etc/inet/ntp.conf <<EOF
## NTP daemon configuration file. See ntp.conf(4) for full documentation.
## This file is derived from the stock OmniOS file, modified for our
## CockroachDB exploration.

## Always configure the drift file. It can take days for ntpd to completely
## stabilise and without the drift file, it has to cold start following an
## ntpd restart.
driftfile /var/ntp/ntp.drift

## Default to ignore all for safety -- no incoming packets are trusted.
restrict default kod limited nomodify nopeer noquery
restrict -6 default kod limited nomodify nopeer noquery

## Permit localhost to connect to and manage ntpd
restrict 127.0.0.1      # Allow localhost full access
restrict -6 ::1         # Same, for IPv6

## Permit ntp server to reply to our queries
restrict source nomodify noquery notrap

server 169.254.169.123

tos minclock 4 minsane 4

## It is always wise to configure at least the loopstats and peerstats files.
## Otherwise when ntpd does something you don't expect there is no way to
## find out why.
statsdir /var/ntp/ntpstats/
filegen peerstats file peerstats type day enable
filegen loopstats file loopstats type day enable
EOF
svcadm refresh ntp
svcadm enable ntp

#
# Set up filesystems and users.  We'll use "cockroachdb" for everything, so
# we'll give it "Primary Administrator" and DTrace privileges.
#
zfs create -o mountpoint=/export/home rpool/home
zfs create -o mountpoint=/cockroachdb rpool/cockroachdb
useradd -d /export/home/cockroachdb \
    -P "Primary Administrator" -m -s /bin/bash \
    -K defaultpriv="basic,dtrace_user,dtrace_proc,dtrace_kernel" cockroachdb

#
# Unpack the CockroachDB binaries to /cockroachdb.
#
tar xzvf /tmp/cockroachdb.tar.gz -C /cockroachdb
chown -R cockroachdb /cockroachdb

#
# Import the SMF manifest.  This will not yet start the service.
#
svccfg import /tmp/cockroachdb.xml

#
# Configure the service.  All we know right now is our own IP address.
#
svccfg -s cockroachdb setprop config/my_internal_ip = "$1"
svcadm refresh cockroachdb:default
