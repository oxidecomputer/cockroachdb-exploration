#
# Environment file for "cockroachdb_exploration" project.  This just provides
# some useful aliases for managing instances related to the project.
#

# Configurables
AWSALIASES_PROJECT="crdb_exploration"
AWSALIASES_MYKEY="dap-terraform"
AWSALIASES_CLUSTER="main"
export AWS_PROFILE=oxide-sandbox-dap

# Derived globals
AWSALIASES_PROJECT_FILTER="Name=tag:Project,Values=$AWSALIASES_PROJECT"
AWSALIASES_CLUSTER_FILTER="Name=tag:Cluster,Values=$AWSALIASES_CLUSTER"
AWSALIASES_MY_FILTER="Name=key-name,Values=$AWSALIASES_MYKEY"
AWSALIASES_QUERY="Reservations[*].Instances[*].{"
AWSALIASES_QUERY="${AWSALIASES_QUERY}Name:Tags[?Key=='Name']|[0].Value"
AWSALIASES_QUERY="${AWSALIASES_QUERY},InstanceId:InstanceId"
AWSALIASES_QUERY="${AWSALIASES_QUERY},StateName:State.Name"
AWSALIASES_QUERY="${AWSALIASES_QUERY},Internal:PrivateIpAddress"
AWSALIASES_QUERY="${AWSALIASES_QUERY},Public:PublicIpAddress}"
AWSALIASES_ROOT="$(cd $(dirname ${BASH_SOURCE[0]}); pwd)"

#
# Execs the "terraform" command, but wraps it with `aws as-session` if
# AWS_PROFILE is set.
#
function run_terraform {
	if [[ -n "$AWS_PROFILE" ]]; then
		echo "running terraform under \`aws as-session\`" \
		    "because AWS_PROFILE is set" >&2
		(cd $AWSALIASES_ROOT/terraform && \
		    exec aws as-session terraform "$@")
	else
		(cd $AWS_ALIASES_ROOT/terraform && exec terraform "$@")
	fi
}

#
# List all instances associated with the key above, not just those in the
# project.
#
function list_my_instances {
	aws ec2 describe-instances \
	    --filters "$AWSALIASES_MY_FILTER" \
	    --query "$AWSALIASES_QUERY" \
	    --output json \
	    | json -a \
	    | json -ga InstanceId StateName Internal Public Name \
	    | column -t \
	    | sort -k7n
}

function list_project_instances_raw {
	aws ec2 describe-instances \
	    --filters "$AWSALIASES_PROJECT_FILTER" \
	    --filters "$AWSALIASES_CLUSTER_FILTER" \
	    --query "$AWSALIASES_QUERY" \
	    --output json \
	    | json -a
}

#
# List only the instances in this project, whether they're running or not.
#
function list_project_instances {
	list_project_instances_raw \
	    | json -ga InstanceId StateName Internal Public Name \
	    | column -t | sort -k5
}

#
# Stop all the instances in this project.
#
function stop_project_instances {
	list_project_instances_raw \
	    | json -ga InstanceId  \
	    | xargs -t aws ec2 stop-instances --instance-ids
}

#
# Start all the instances in this project.
#
function start_project_instances {
	list_project_instances_raw \
	    | json -ga InstanceId  \
	    | xargs -t aws ec2 start-instances --instance-ids
}

#
# Generate the shell command to ssh to an instance
#
function project_ssh_cmd {
	local kind which ip

	kind="$1"
	case "$kind" in
		db|nvmedb)
			which="$2"
			if ! [[ $which =~ ^[0-9]*$ ]]; then
				echo "bad number: \"$which\"" >&2
				return
			fi
			if [[ -z "$which" ]]; then
				which=0
			else
				which=$(( which - 1 ))
			fi
			;;
		loadgen|mon)
			which="0"
			;;
		*)
			echo "unsupported kind (must be one of" \
			    "\"db\", \"nvmedb\", \"loadgen\", or \"mon\")" >&2
			return
			;;
	esac

	ip="$(run_terraform output -json "${kind}_external_ip" | json $which)"
	if [[ $? != 0 || -z "$ip" ]]; then
		echo "failed to get IP from 'terraform output'" >&2
		return
	fi

	echo "ssh -o StrictHostKeyChecking=accept-new root@$ip"
}

#
# SSH to a remote instance.
#
function project_ssh {
	local cmd

	cmd="$(project_ssh_cmd "$@")" || return
	echo "running: $cmd"
	$cmd
}

#
# Set up ssh tunnels for key services.
#
function start_project_ssh {
	local mon_internal_ip nvmedb_internal_ip any_external_ip
	local terraform_output

	terraform_output="$(run_terraform output -json \
	    | json mon_internal_ip.value.0 nvmedb_internal_ip.value.0 \
	      nvmedb_external_ip.value.0)"

	read mon_internal_ip nvmedb_internal_ip any_external_ip \
	    <<< $terraform_output
	echo "mon internal IP: $mon_internal_ip"
	echo "nvmedb1 internal IP: $nvmedb_internal_ip"
	echo "nvmedb1 external IP: $any_external_ip"
	#
	# Ports:
	#
	#    9090  Prometheus web UI
	#    3000  Grafana web UI
	#    8080  CockroachDB Admin UI
	#
	ports="-L9090:$mon_internal_ip:9090"
	ports="$ports -L3000:$mon_internal_ip:3000"
	ports="$ports -L8080:$nvmedb_internal_ip:8080"
	# TODO This option is not secure.
	options="-o \"StrictHostKeyChecking accept-new\""
	echo "ssh $options $ports root@$any_external_ip"
}
