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
[[ -f /tmp/cockroachdb.tar.gz ]] || fail "missing /tmp/cockroachdb.tar.gz"
[[ $# == 1 ]] || fail "expected exactly one argument (internal IP)"

#
# Configure NTP.  There's an issue here where "svcadm enable -s ntp" fails
# because of a dependency problem, but it actually comes up fine.  We don't
# bother using "-s" since we don't care when it comes up.
#
ntpdate 0.pool.ntp.org
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
