#
# Environment file for "cockroachdb_exploration" project.  This just provides
# some useful aliases for managing instances related to the project.
#

# Configurables
AWSALIASES_PROJECT="crdb_exploration"
AWSALIASES_MYKEY="dap-terraform"

# Derived globals
AWSALIASES_PROJECT_FILTER="Name=tag:Project,Values=$AWSALIASES_PROJECT"
AWSALIASES_MY_FILTER="Name=key-name,Values=$AWSALIASES_MYKEY"
AWSALIASES_QUERY="Reservations[*].Instances[*].{"
AWSALIASES_QUERY="${AWSALIASES_QUERY}Name:Tags[?Key=='Name']|[0].Value"
AWSALIASES_QUERY="${AWSALIASES_QUERY},InstanceId:InstanceId"
AWSALIASES_QUERY="${AWSALIASES_QUERY},StateName:State.Name"
AWSALIASES_QUERY="${AWSALIASES_QUERY},Internal:PrivateIpAddress"
AWSALIASES_QUERY="${AWSALIASES_QUERY},Public:PublicIpAddress}"

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
