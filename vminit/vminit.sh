#!/bin/bash

#
# vminit.sh MY_INTERNAL_IP: Terraform remote-exec provisioner script that sets
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
[[ -f /var/tmp/vminit.tar.gz ]] || fail "missing /var/tmp/vminit.tar.gz"
[[ $# == 1 ]] || fail "expected exactly one argument (internal IP)"

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
# Unpack the tarball to /cockroachdb.
#
tar xzvf /var/tmp/vminit.tar.gz -C /cockroachdb
chown -R cockroachdb /cockroachdb

#
# Import the SMF manifest for CockroachDB and configure the service.  All we
# know right now is our own IP address.  This will not yet start the service.
#
svccfg import /cockroachdb/smf/cockroachdb.xml
svccfg -s cockroachdb setprop config/my_internal_ip = "$1"
svcadm refresh cockroachdb:default

#
# Disable the stock NTP service and enable chrony.  (This manifest will start
# the service.)
#
svcadm disable -s ntp
svccfg import /cockroachdb/smf/chrony.xml
