#!/bin/sh

###################################################################
# Script Name	: provision-gke-cluster.sh
# Description	: For managing GKE clusters
# Author       	: Kasun Talwatta
# Email         : kasun.talwatta@solo.io
###################################################################

set -e
set -o pipefail

_filename="$(basename $BASH_SOURCE)"

SCOPES=("https://www.googleapis.com/auth/devstorage.read_only"
        "https://www.googleapis.com/auth/logging.write"
        "https://www.googleapis.com/auth/monitoring"
        "https://www.googleapis.com/auth/servicecontrol"
        "https://www.googleapis.com/auth/service.management.readonly"
        "https://www.googleapis.com/auth/trace.append"
        "https://www.googleapis.com/auth/ndev.clouddns.readwrite"
)

# Default values
DEFAULT_PROJECT_ID=$(gcloud config get-value project)
DEFAULT_NODE_NUM="1"
DEFAULT_REGION="asia-northeast1"
DEFAULT_MACHINE_TYPE="e2-standard-4"
DEFAULT_SCOPES=$(IFS=,; echo "${SCOPES[*]}")

OWNER=""
NODE_NUM=""
CLUSTER_NAME_SUFFIX=""
CLUSTER_VERSION=""
ZONE=""
ZONE_OPTION=""
REGION=""

# Check if default project is set
if [[ -z $DEFAULT_PROJECT_ID ]]; then
    echo "No default project set. Please set a default project with `gcloud config set project <project name>`"
    exit 1
fi

# Display usage message function
usage() {
    echo "=================="
    echo "Usage:"
    echo "=================="
    echo "$_filename -h                                                                                                          Display this usage message"
    echo ""
    echo "$_filename create -o <arg> -n <arg> [-a <arg> -m <arg> -r <arg> -v <arg> -z <arg>] ................................... Provisioning a GKE cluster"
    echo "\tRequired arguments:"
    echo "\t-n   Name of the cluster (Uses as the suffix for the name)"
    echo "\t-o   Name of the cluster owner"
    echo "\tOptional arguments:"
    echo "\t-a - Number of nodes (Default 1 if not specified)"
    echo "\t-m   Machine type (Default n2-standard-4 if not specified)"
    echo "\t-r   Region (Default asia-northeast1 if not specified)"
    echo "\t-v   Kubernetes version"
    echo "\t-z   Zone (If provided will be allocated to the specified zone)"
    echo ""
    echo "$_filename delete -o <arg> -n <arg> [-r <arg> -z <arg>] .............................................................. Deleting a GKE cluster"
    echo "\tRequired arguments:"
    echo "\t-n   Suffix of the cluster name (Uses a combination of owner and suffix to make up the actual name)"
    echo "\t-o   Name of the cluster owner"
    echo "\tOptional arguments:"
    echo "\t-r   Region (Default asia-northeast1 if not specified)"
    echo "\t-z   Zone (If provided will be allocated to the specified zone)"
}

# Find default image type in region
get_default_image_type_in_region() {
    echo $(gcloud -q container get-server-config --format="get(defaultImageType)" --region $1 2> /dev/null)
}

# Find default cluster version in region
get_default_cluster_version_in_region() {
    echo $(gcloud -q container get-server-config --flatten="channels" --filter="channels.channel=STABLE" --format='get(channels.defaultVersion)' --region $1 2> /dev/null)
}

# Utility function to create a cluster
create_cluster() {
    echo "Creating cluster $1-$2 with $6 nodes of type $5 in $DEFAULT_PROJECT_ID"

    DEFAULT_IMAGE_TYPE=$(get_default_image_type_in_region $4)
    gcloud services enable "container.googleapis.com" && \
    gcloud services enable "dns.googleapis.com" && \
    gcloud -q container clusters create "$1-$2" \
        --cluster-version $3 \
        --region $4 \
        --machine-type $5 \
        --image-type $DEFAULT_IMAGE_TYPE \
        --num-nodes $6 \
        --min-nodes $6 \
        --max-nodes $6 \
        --scopes $DEFAULT_SCOPES \
        --labels=owner=$1 \
        --labels=team="fe-presale" \
        --labels=created-by="kasun_talwatta" \
        --enable-network-policy \
        --project $DEFAULT_PROJECT_ID \
        $7
}

# Utility function to delete a cluster
delete_cluster() {
    echo "Deleting cluster $1-$2 in $DEFAULT_PROJECT_ID"
    gcloud -q container clusters delete "$1-$2" \
        --region $3 \
        --project $DEFAULT_PROJECT_ID \
        $4
}

[ $# -eq 0 ] && usage && exit 1

while getopts ":h" opt; do # Go through the options
    case $opt in
        h ) # Help
            usage
            exit 0 # Exit correctly
        ;;
        ? ) # Invalid option
            echo "[ERROR]: Invalid option: -${OPTARG}"
            usage
            exit 1
        ;;
    esac
done
shift $((OPTIND-1))
subcommand=$1; shift
case "$subcommand" in
    create )
        unset OPTIND
        [ $# -eq 0 ] && usage && exit 1
        while getopts ":a:m:n:o:r:v:z:" opt; do
            case $opt in
                a )
                    NODE_NUM=$OPTARG
                ;;
                m )
                    MACHINE_TYPE=$OPTARG
                ;;
                n )
                    CLUSTER_NAME_SUFFIX=$OPTARG
                ;;
                o )
                    OWNER=$OPTARG
                ;;
                r )
                    REGION=$OPTARG
                ;;
                v )
                    CLUSTER_VERSION=$OPTARG
                ;;
                z )
                    ZONE=$OPTARG
                ;;
                : ) # Catch no argument provided
                    echo "[ERROR]: option -${OPTARG} requires an argument"
                    usage
                    exit 1
                ;;
                ? ) # Invalid option
                    echo "[ERROR]: Invalid option: -${OPTARG}"
                    usage
                    exit 1
                ;;
            esac
        done

        if [ -z $OWNER ] || [ -z $CLUSTER_NAME_SUFFIX ]; then
            echo "[ERROR]: Both -o and -n are required"
            usage
            exit 1
        fi

        if [ ! -z $ZONE ]; then
            ZONE_OPTION="--zone $ZONE"
        else
            ZONE_OPTION=" "
        fi

        shift $((OPTIND-1))

        NODE_NUM=${NODE_NUM:-$DEFAULT_NODE_NUM}
        REGION=${REGION:-$DEFAULT_REGION}
        DEFAULT_CLUSTER_VERSION=$(get_default_cluster_version_in_region $REGION)
        CLUSTER_VERSION=${CLUSTER_VERSION:-$DEFAULT_CLUSTER_VERSION}
        MACHINE_TYPE=${MACHINE_TYPE:-$DEFAULT_MACHINE_TYPE}

        create_cluster $OWNER $CLUSTER_NAME_SUFFIX $CLUSTER_VERSION $REGION $MACHINE_TYPE $NODE_NUM "$ZONE_OPTION"
    ;;
    delete )
        unset OPTIND
        [ $# -eq 0 ] && usage && exit 1
        while getopts ":n:o:r:z:" opt; do
            case $opt in
                n )
                    CLUSTER_NAME_SUFFIX=$OPTARG
                ;;
                o )
                    OWNER=$OPTARG
                ;;
                r )
                    REGION=$OPTARG
                ;;
                z )
                    ZONE=$OPTARG
                ;;
                : ) # Catch no argument provided
                        echo "[ERROR]: option -${OPTARG} requires an argument"
                        usage
                        exit 1
                ;;
                ? ) # Invalid option
                        echo "[ERROR]: Invalid option: -${OPTARG}"
                        usage
                        exit 1
                ;;
            esac
        done

        if [ -z $OWNER ] || [ -z $CLUSTER_NAME_SUFFIX ]; then
            echo "[ERROR]: Both -o and -n are required"
            usage
            exit 1
        fi

        if [ ! -z $ZONE ]; then
            ZONE_OPTION="--zone $ZONE"
        else
            ZONE_OPTION=" "
        fi

        shift $((OPTIND-1))

        REGION=${REGION:-$DEFAULT_REGION}

        delete_cluster $OWNER $CLUSTER_NAME_SUFFIX $REGION "$ZONE_OPTION"
    ;;
    * ) # Invalid subcommand
        if [ ! -z $subcommand ]; then
            echo "Invalid subcommand: $subcommand"
        fi
        usage
        exit 1
    ;;
esac