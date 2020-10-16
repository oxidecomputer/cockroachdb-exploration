#!/bin/bash

#
# vminit.sh MY_INTERNAL_IP ROLE: Terraform remote-exec provisioner script that
# sets up a fresh OmniOS VM within the cockroachdb_exploration project.
#

set -o errexit
set -o pipefail
set -o xtrace

#
# COMMAND-LINE ARGUMENTS
#

arg0="$(basename "${BASH_SOURCE[0]}")"
# role for this VM ("db", "loadgen", or "mon")
VMI_ROLE="$1"
# alias for this VM (e.g., "db1")
VMI_ALIAS="$2"
# internal IP for this VM
VMI_IP="$3"
# S3 bucket where our assets are stored.
VMI_S3BUCKET="$4"

#
# VARIABLES
#

# role-specific tarball to download
VMI_EXTRA_TARBALL=
# role-specific Unix user to create
VMI_USER=
# role-specific ZFS dataset name
VMI_DSNAME=
# zpool for our work
VMI_ZPOOL=

# fail ARGS: print message to stderr and exit failure
function fail
{
	echo "$arg0: $@" >&2
	exit 1
}

# Validate arguments.
[[ $# == 4 ]] || fail "usage: $arg0 ROLE ALIAS INTERNAL_IP S3BUCKET"

case "$VMI_ROLE" in
	db|loadgen)
		VMI_USER=cockroachdb
		VMI_DSNAME=cockroachdb
		VMI_EXTRA_TARBALL=cockroachdb
		;;
	mon)
		VMI_USER=mon
		VMI_DSNAME=mon
		VMI_EXTRA_TARBALL=mon
		;;
	*)
		fail "unexpected role: $VMI_ROLE " \
		    '(expected "db", "loadgen", or "mon")'
esac

# Check prerequisites.
[[ -f /var/tmp/fetcher.gz ]] || fail "missing /var/tmp/fetcher.gz"

# Unzip the "fetcher" tool.
gzcat < /var/tmp/fetcher.gz > /var/tmp/fetcher
chmod +x /var/tmp/fetcher

# Fetch both the common tarball and the one for this role.
/var/tmp/fetcher "$VMI_S3BUCKET" "vminit-common.tgz" \
    > /var/tmp/vminit-common.tgz
/var/tmp/fetcher "$VMI_S3BUCKET" "vminit-$VMI_EXTRA_TARBALL.tgz" \
    > /var/tmp/vminit-$VMI_EXTRA_TARBALL.tgz

#
# Update the hostname, in three parts:
# (1) The hostname(1) command updates it now.
# (2) The update of /etc/nodename causes this name to persist across reboots.
# (3) The update of /etc/default/dhcpagent causes /etc/nodename NOT to be
#     clobbered by the DHCP "Hostname" parameter.
# TODO it would be helpful to put the private IP in the bash prompt, too.
#
hostname "$VMI_ALIAS"
echo "$VMI_ALIAS" > /etc/nodename
/usr/bin/sed -i '/^PARAM_IGNORE_LIST=/s/=.*/=12/' /etc/default/dhcpagent

# Figure on which disk to create our non-root zpool.
if [[ "$VMI_ROLE" == "db" ]]; then
	rpool_disk="$(zpool list -v -H rpool | awk 'NR == 2{ print $1 }')"
	other_disks=$(diskinfo -Hp | awk '$2 != "'$rpool_disk'"')
	if [[ $(wc -l <<< $other_disks) -ne 1 ]]; then
		fail "could not choose disk for new zpool"
	fi
	IFS=$'\t' read u1 name u2 u3 size rmv ssd <<< $other_disks
	if [[ "$size" =~ [^0-9] ]]; then
		fail "failed to parse size of disk"
	fi
	avail_disk="$name"
	zpool create -O compression=on tank "$avail_disk"
	VMI_ZPOOL=tank
else
	VMI_ZPOOL=rpool
fi

# Set up filesystems and users.
zfs create -o mountpoint=/export/home $VMI_ZPOOL/home
zfs create -o mountpoint="/$VMI_DSNAME" "$VMI_ZPOOL/$VMI_DSNAME"
useradd -d "/export/home/$VMI_USER" -m -s /bin/bash "$VMI_USER"

# Unpack the tarballs and correct permissions for the unpacked dataset.
tar xzvf "/var/tmp/vminit-common.tgz" -C /
tar xzvf "/var/tmp/vminit-$VMI_EXTRA_TARBALL.tgz" -C /
chown -R "$VMI_USER" "/$VMI_DSNAME"

# Configure chrony.
svcadm disable -s ntp
svccfg import /opt/oxide/smf/chrony.xml

# Configure node_exporter
svccfg import /opt/oxide/smf/node-exporter.xml

# Configure illumos-exporter
svccfg import /opt/oxide/smf/illumos-exporter.xml

# Apply role-specific configuration.
if [[ $VMI_ROLE == "mon" ]]; then
	#
	# For Grafana, we'd like to keep any local customizations (like the
	# config file and the provisioning directory) as well as any writable
	# areas (like the "data" and "logs" directories) separate from the
	# directory containing the software package itself.  To help catch cases
	# where we've missed something, make the software directory
	# not-writable.
	#
	chmod -R -w /mon/grafana/grafana/

	svccfg import /mon/smf/prometheus.xml
	svccfg import /mon/smf/grafana.xml
elif [[ $VMI_ROLE == "db" ]]; then
	#
	# Import the SMF manifest for CockroachDB and configure the
	# service.  All we know right now is our own IP address.  This
	# will not yet start the service.
	#
	svccfg import /cockroachdb/smf/cockroachdb.xml
	svccfg -s cockroachdb setprop config/my_internal_ip = "$VMI_IP"
	svcadm refresh cockroachdb:default
elif [[ $VMI_ROLE == "loadgen" ]]; then
	#
	# Set up haproxy, which will function as client-side load balancing for
	# our cluster.  This will not configure or enable the service -- that
	# can only happen once the cluster has been initialized, once everything
	# has been deployed.
	#
	svccfg import /cockroachdb/smf/haproxy.xml

	#
	# Additionally, set up root's and cockroachdb's environment so that our
	# tools are on the path and so that cockroachdb connection parameters
	# are available.
	#
	# It's a little dicey to have root's profile include some other user's
	# environment file.  In this specific instance, we're really in the same
	# trust domain.
	#
	cat >> /cockroachdb/etc/environment <<-EOF
	export COCKROACH_HOST="$VMI_IP"
	export COCKROACH_INSECURE=true
	export PATH="\$PATH:/cockroachdb/bin:/opt/sysbench/bin"
	EOF
	echo "source /cockroachdb/etc/environment" >> ~root/.profile
	echo "source /cockroachdb/etc/environment" >> ~cockroachdb/.profile
	chown cockroachdb /cockroachdb/etc/environment ~cockroachdb/.profile
fi
