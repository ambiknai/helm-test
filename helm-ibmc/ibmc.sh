#!/bin/bash
set -e

# Indicates whether chart is tar archive or pulled from repo
flag=0

create_dir_flag=0

CHARTREFERENCE="" # For example, ibm-helm/ibm-object-storage-plugin, ./ibm-object-storage-plugin-1.0.6.tgz, ./ibm-object-storage-plugin
CHARTNAME="" # Name of the chart. For example: ibm-object-storage-plugin
CHARTVERSION=""
PLUGIN_DIR_CACHE=""
CONFIG_BUCKET_ACCESS_POLICY=""

usage() {
if [[ "$clientVersion" == "v2."* ]]; then
  echo ""
  echo "============================================================================="
  echo "IMPORTANT NOTE: CURRENT HELM CLIENT VERSION IS \"${clientVersion}\"."
  echo "PLEASE UPGRADE HELM CLIENT TO v3.x FOR INSTALLING THE CHART \"WITHOUT TILLER\"."
  echo "============================================================================="
  echo ""
fi
cat << EOF
Install or upgrade Helm charts in IBM K8S Service(IKS) and IBM Cloud Private(ICP)
Usage:
  helm ibmc [command]
Available Commands:
  install           Install a Helm chart
  upgrade           Upgrade the release to a new version of the Helm chart
Available Flags:
  -h, --help        (Optional) This text.
  -u, --update      (Optional) Update this plugin to the latest version
EOF

if [[ "$clientVersion" == "v2."* ]]; then
  echo "Example Usage:"
  echo "    Install: helm ibmc install ibm-helm/ibm-object-storage-plugin --name ibm-object-storage-plugin"
  echo "    Upgrade: helm ibmc upgrade [RELEASE] ibm-helm/ibm-object-storage-plugin"
else
  echo "Example Usage:"
  echo "    Install: helm ibmc install ibm-object-storage-plugin ibm-helm/ibm-object-storage-plugin"
  echo "    Upgrade: helm ibmc upgrade [RELEASE] ibm-helm/ibm-object-storage-plugin"
fi

cat << EOF
Note:
    1. It is always recommended to install latest version of ibm-object-storage-plugin chart.
    2. It is always recommended to have 'kubectl' client up-to-date.
EOF
}

helm2_install_usage() {
cat << EOF
This command installs a chart archive in IBM K8S Service(IKS) and IBM Cloud Private(ICP).
The install argument must be a chart reference, a path to a packaged chart,
a path to an unpacked chart directory or a URL.
Usage:
  helm ibmc install [CHART] [flags]
EOF
helm install --help | awk '/Flags/{y=1}y'
cat << EOF
Example Usage:
    helm ibmc install ibm-helm/ibm-object-storage-plugin --name ibm-object-storage-plugin
EOF
}

helm3_install_usage() {
cat << EOF
This command installs a chart archive in IBM K8S Service(IKS) and IBM Cloud Private(ICP).
The install argument must be a chart reference, a path to a packaged chart,
a path to an unpacked chart directory or a URL.
Usage:
  helm ibmc install [NAME] [CHART] [flags]
EOF
helm install --help | awk '/Flags/{y=1}y'
cat << EOF
Example Usage:
    helm ibmc install ibm-object-storage-plugin ibm-helm/ibm-object-storage-plugin
EOF
}

helm_upgrade_usage() {
cat << EOF
This command upgrades a release to a new version of a chart in IBM K8S Service(IKS) and IBM Cloud Private(ICP).
The upgrade arguments must be a release and chart. The chart
argument can be either: a chart reference('stable/mariadb'), a path to a chart directory,
a packaged chart, or a fully qualified URL. For chart references, the latest
version will be specified unless the '--version' flag is set.
Usage:
  helm ibmc upgrade [RELEASE] [CHART] [flags]
EOF
helm upgrade --help | awk '/Flags/{y=1}y'
cat << EOF
Example Usage:
    helm ibmc upgrade [RELEASE] ibm-helm/ibm-object-storage-plugin
EOF
}

check_pod_status() {
  attempts=0
  pod_name=$1
  while true; do
    attempts=$((attempts+1))
    pod_status=$(kubectl get pod -n kube-system | grep $pod_name | awk '{print $3}')
    if [[ "$pod_status" == "Completed" || "$pod_status" == "Running" ]]; then
      echo "pod '$pod_name' is healthy."
      break
    fi
    if [[ $attempts -gt 12 ]]; then
      echo "$pod_name  is not running well."
      kubectl get pod -n kube-system $pod_name
      kubectl describe pod -n kube-system $pod_name
      exit 1
    fi
    echo "pod '$pod_name' is not running. Sleeping 5 seconds..."
    sleep 5
  done
}

# Create the passthru array
PASSTHRU=()
#Create flags array
FLAGS=()

while [[ $# -gt 0 ]]
do
    key="$1"

    # Parse arguments
   case $key in
        -h|--help)
        HELP="TRUE"
        ;;

        --verbos)
        DEBUG="TRUE"
        ;;

        -u|--update)
        UPDATE="TRUE"
        ;;

        "--version"*)
        if [[ "$1" == "--version="* ]]; then
          CHARTVERSION=$(echo $1 | awk -F '=' '{print $2}')
        elif [[ $# -gt 1 ]] && [[ "$2" != "-"* ]]; then
          CHARTVERSION="$2"
          shift
        fi
        ;;

        "-"*)
        if [[ $# -gt 1 ]] && [[ "$2" != "-"* ]]; then
          if [[ "$2" = *"bucketAccessPolicy"* ]]; then
            CONFIG_BUCKET_ACCESS_POLICY=$(echo $2 | cut -d "=" -f 2);
          else
            FLAGS+=("$1" "$2")
          fi
          shift
        else
          FLAGS+=("$1")
        fi
        ;;

        *)       # Command(install/upgrade), release name and chart name
        PASSTHRU+=("$1")
        ;;
   esac
   shift  # past argument
done

# Restore PASSTHRU parameters
set -- "${PASSTHRU[@]}"
# Restore FLAG parameters
set -- "${FLAGS[@]}"

set +e
clientVersion=$(helm version --client --short  2>&1)
set -e

if [[ "$clientVersion" == "Client: v2."* ]]; then
  clientVersion=$(echo $clientVersion | awk -F ': ' '{print $2}')
  PLUGIN_DIR_CACHE=$HELM_HOME/cache/plugins
else
  PLUGIN_DIR_CACHE=$HELM_REPOSITORY_CACHE/../plugins
fi
echo "Helm version: $clientVersion"

PLUGIN_LOCATION=$(ls -l $HELM_PLUGIN_DIR | awk -F ' -> ' '{print $2}')
if [[ "$PLUGIN_LOCATION" != "$PLUGIN_DIR_CACHE/helm-ibmc" ]]; then
  if [ ! -d "$PLUGIN_DIR_CACHE" ]; then
    mkdir -p $PLUGIN_DIR_CACHE
  fi
  cp -r $PLUGIN_LOCATION $PLUGIN_DIR_CACHE/
  #Delete existing symlink
  rm -rf $HELM_PLUGIN_DIR
  #Create new symlink
  ln -s $PLUGIN_DIR_CACHE/helm-ibmc $HELM_PLUGIN_DIR
fi

COMMAND=${PASSTHRU[0]}
# Show help if flagged
if [ "$HELP" == "TRUE" ]; then
  if [[ "$COMMAND" == "install" ]]; then
    if [[ "$clientVersion" == "v2."* ]]; then
      helm2_install_usage
    else
      helm3_install_usage
    fi
    exit 0
  elif [[ "$COMMAND" == "upgrade" ]]; then
    helm_upgrade_usage
    exit 0
  else
    usage
    exit 0
  fi
fi

#  Update this Helm plugin
if [ "$UPDATE" == "TRUE" ]; then
    if [ ! -d "$PLUGIN_DIR_CACHE" ]; then
      mkdir -p $PLUGIN_DIR_CACHE
    fi
    cd $PLUGIN_DIR_CACHE

    # Pull latest chart for upgrading ibmc helm plugin
    helm repo add ibmc-upgrade https://raw.githubusercontent.com/IBM/charts/master/repo/ibm-helm
    helm repo update
    helm fetch --untar ibmc-upgrade/ibm-object-storage-plugin
    helm repo remove ibmc-upgrade

    cp -r $PLUGIN_DIR_CACHE/ibm-object-storage-plugin/helm-ibmc $PLUGIN_DIR_CACHE/
    rm -rf $PLUGIN_DIR_CACHE/ibm-object-storage-plugin
    PLUGIN_LOCATION=$(ls -l $HELM_PLUGIN_DIR | awk -F ' -> ' '{print $2}')
    if [[ "$PLUGIN_LOCATION" != "$PLUGIN_DIR_CACHE/helm-ibmc" ]]; then
      rm -rf $HELM_PLUGIN_DIR
      ln -s $PLUGIN_DIR_CACHE/helm-ibmc $HELM_PLUGIN_DIR
    fi
    PLUGIN_VERSION=$(helm plugin list | grep ibmc | awk '{print $2}')
    echo "Success! Updated this plugin to: $PLUGIN_VERSION"
    exit 0
fi

# Print params for debugging
if [ "$DEBUG" == "TRUE" ]; then
    echo "PARAMS";
    echo $*;
    echo " ......................... ";
    echo Helm kubeconfig      = "$KUBECONFIG";
    if [[ "$clientVersion" == "v2."* ]]; then
     echo Helm home            = "$HELM_HOME";
    fi
    echo Helm plugin dir       = "$HELM_PLUGIN_DIR";
    echo helm plugin cache dir = "$PLUGIN_DIR_CACHE";
    echo PASSTHRU              = "${PASSTHRU[@]}";
    if [[ "${#FLAGS[@]}" -ne 0 ]]; then
     echo FLAGS                = "${FLAGS[@]}";
    fi
fi

# COMMAND must be one of 'install' or 'upgrade'
if [[ "$COMMAND" == "install" ]]; then
  if [[ "$clientVersion" == "v2."* ]]; then
    if [[ "${#PASSTHRU[@]}" -ne 2 ]]; then
      echo "Error: This command needs 1 argument: chart name"
      exit 1
    fi
    CHARTREFERENCE=${PASSTHRU[1]}
  else
    if [[ "${#PASSTHRU[@]}" -ne 3 ]]; then
      echo "Error: This command needs 2 arguments: release name, chart path"
      exit 1
    fi
    CHARTREFERENCE=${PASSTHRU[2]}
  fi
elif [[ "$COMMAND" == "upgrade" ]]; then
  if [[ "${#PASSTHRU[@]}" -ne 3 ]]; then
    echo "Error: This command needs 2 arguments: release name, chart path"
    exit 1
  fi
  CHARTREFERENCE=${PASSTHRU[2]}
else
  echo "Error: Invalid command, must be one of 'install' or 'upgrade'."
  usage
  exit 1
fi

# Check cluster provider (ICP or IKS)
if [[ `kubectl get nodes -o yaml | grep 'node-role\.kubernetes\.io'` == "" || \
  `kubectl get nodes -o yaml | grep 'ibm-cloud\.kubernetes\.io/worker-version'` == *"openshift"* ]]; then
  if [[ `kubectl get nodes -o yaml | grep 'ibm-cloud\.kubernetes\.io/iaas-provider\: \(gc\|g2\|ng\)'` != "" ]]; then
    CLUSTER_PROVIDER="IBMC-VPC"
  else
    CLUSTER_PROVIDER="IBMC"
  fi
  DC_NAME=$(kubectl get cm cluster-info -n kube-system -o jsonpath='{.data.cluster-config\.json}' | grep datacenter | awk -F ': ' '{print $2}' | sed 's/\"//g' |sed 's/,//g')
  REGION=$(kubectl get nodes -o yaml | grep 'ibm-cloud\.kubernetes\.io/region'  | head -n1 | awk -F ":" '/:/{gsub(/ /, "", $2); print $2} ')
elif [[ `kubectl get nodes -o yaml | grep 'node-role\.kubernetes\.io/\(etcd\|master\|management\|worker\|proxy\|va\|compute\|infra\|icp-management\|icp-master\|icp-proxy\)'` != "" ]]; then
  CLUSTER_PROVIDER="ICP"
  DC_NAME=""
else
  echo "ERROR: Cluster provider is not supported. Exiting!!!"
  exit 1
fi

if [[ $CONFIG_BUCKET_ACCESS_POLICY == "" ]]; then
  if [[ "$CLUSTER_PROVIDER" == "IBMC-VPC" ]]; then
      if [[ `kubectl get nodes -o yaml | grep 'ibm-cloud\.kubernetes\.io/region\: \(eu-fr2\)'` != "" ]]; then
        CONFIG_BUCKET_ACCESS_POLICY="true"
      else
        CONFIG_BUCKET_ACCESS_POLICY="false"
      fi
  else
    CONFIG_BUCKET_ACCESS_POLICY="false"
  fi
fi

# Check worker node's OS
WORKER_OS=$(kubectl get nodes -o jsonpath='{ .items[0].status.nodeInfo.osImage }' | tr [:lower:] [:upper:])
if [[ "$WORKER_OS" == "RED HAT"* || "$WORKER_OS" == "OPENSHIFT"* ]]; then
  WORKER_OS="redhat"
  PLATFORM="openshift"
else
  WORKER_OS="debian"
  PLATFORM="k8s"
fi

KUBE_DRIVER_PATH="/usr/libexec/kubernetes"
podImage="ibmcom/busybox:1.30.1"

if [[ "$CLUSTER_PROVIDER" == "IBMC"* ]]; then
  podImage="icr.io/ibm/ibmcloud-object-storage-plugin:1.8.27"
fi

if [[ "$WORKER_OS" == "redhat" ]]; then
  echo "Fetching WORKER OS details using pod..."
  kubectl run get-os-info --overrides='
  {
    "kind": "Pod",
    "apiVersion": "v1",
    "metadata": {
      "name": "get-os-info",
      "namespace": "kube-system",
      "labels": {
        "app": "ibmcloud-object-storage-plugin"
      }
    },
    "spec": {
      "containers": [{
        "name": "get-os-info",
        "image": "'"$podImage"'",
        "command": ["/bin/sh", "-c", "cat /hostetc/os-release"],
        "volumeMounts": [{
          "mountPath": "/hostetc/os-release",
          "name": "os-info",
          "readOnly": true
        }, {
          "mountPath": "/host/usr/lib",
          "name": "usr-lib",
          "readOnly": true
        }]
      }],
      "volumes": [{
        "name":"os-info",
        "hostPath": {
          "path": "/etc/os-release",
          "type": "File"
        }
      }, {
        "name":"usr-lib",
        "hostPath": {
          "path": "/usr/lib"
        }
      }]
    }
  }' --image=ibmcom/busybox:1.30.1 --namespace=kube-system --restart=Never
  check_pod_status "get-os-info"
  OS_DESTRO=$(kubectl logs -n kube-system $pod_name | grep ^'ID=')
  kubectl delete pod -n kube-system $pod_name
  if [[ "$OS_DESTRO" == "ID=\"rhcos\"" ]]; then
    KUBE_DRIVER_PATH="/etc/kubernetes"
  fi
fi

if [ "$COMMAND" == "install" ]; then
  echo "Installing the Helm chart..."
  echo "PROVIDER: ${CLUSTER_PROVIDER}"
  echo "WORKER_OS: "${WORKER_OS}
  echo "PLATFORM: "${PLATFORM}
  echo "KUBE_DRIVER_PATH: ${KUBE_DRIVER_PATH}"
  echo "CONFIG_BUCKET_ACCESS_POLICY: "${CONFIG_BUCKET_ACCESS_POLICY}
  if [[ "$CLUSTER_PROVIDER" == "IBMC"* ]]; then
    echo "DC: ${DC_NAME}"
    echo "Region: ${REGION}"
  fi
  echo "Chart: $CHARTREFERENCE"
  if [[ "${FLAGS[@]}" = *"-f"* || "${FLAGS[@]}" = *"--values"* ]]; then
    if [[ "$CHARTREFERENCE" = *"/"* ]] && [[ "$CHARTREFERENCE" != ./* ]] && [[ "$CHARTREFERENCE" != /* ]]; then
      if [[ ! -z "$CHARTVERSION" ]]; then
        helm fetch --untar "$CHARTREFERENCE" --version "$CHARTVERSION"
      else
        helm fetch --untar "$CHARTREFERENCE"
      fi
      CHARTNAME=$(echo "$CHARTREFERENCE" | awk -F '/' '{print $2}')
      flag=1
    elif [[ "$CHARTREFERENCE" = *".tgz"* ]]; then
      tar -xzf "$CHARTREFERENCE"
      CHARTNAME=$(tar tzf "$CHARTREFERENCE" | sed -e 's@/.*@@' | uniq)
      flag=1
    fi
  fi
  set +e
  if [[ ! -z "$CHARTVERSION" ]]; then
    helm ${PASSTHRU[@]} --version "$CHARTVERSION" --set bucketAccessPolicy="${CONFIG_BUCKET_ACCESS_POLICY}" --set dcname="${DC_NAME}" --set region=${REGION} --set provider="${CLUSTER_PROVIDER}" --set workerOS="${WORKER_OS}" --set platform="${PLATFORM}" --set kubeDriver="${KUBE_DRIVER_PATH}" "${FLAGS[@]}"
  else
    helm ${PASSTHRU[@]} --set dcname="${DC_NAME}" --set region=${REGION} --set bucketAccessPolicy="${CONFIG_BUCKET_ACCESS_POLICY}" --set provider="${CLUSTER_PROVIDER}" --set workerOS="${WORKER_OS}" --set platform="${PLATFORM}" --set kubeDriver="${KUBE_DRIVER_PATH}" "${FLAGS[@]}"
  fi
  exit_status=$(echo $?)
  if [[ $exit_status -ne 0 ]]; then
    if [[ $flag -eq 1 ]]; then
      rm -rf "$CHARTNAME"
    fi
    exit $exit_status
  fi
  set -e
  if [[ $flag -eq 1 ]]; then
    rm -rf "$CHARTNAME"
  fi
  exit 0
elif [[ "$COMMAND" == "upgrade" ]]; then
  echo "Upgrading the Helm chart..."
  echo "PROVIDER: ${CLUSTER_PROVIDER}"
  if [[ "$CLUSTER_PROVIDER" == "IBMC"* ]]; then
    echo "DC: ${DC_NAME}"
    echo "Region: ${REGION}"
  fi
  echo "Chart: $CHARTREFERENCE"
  if [[ "${FLAGS[@]}" = *"-f"* || "${FLAGS[@]}" = *"--values"* ]]; then
    if [[ "$CHARTREFERENCE" = *"/"* ]] && [[ "$CHARTREFERENCE" != ./* ]] && [[ "$CHARTREFERENCE" != /* ]]; then
      if [[ ! -z "$CHARTVERSION" ]]; then
        helm fetch --untar "$CHARTREFERENCE" --version "$CHARTVERSION"
      else
        helm fetch --untar "$CHARTREFERENCE"
      fi
      CHARTNAME=$(echo "$CHARTREFERENCE" | awk -F '/' '{print $2}')
      flag=1
    elif [[ "$CHARTREFERENCE" = *".tgz"* ]]; then
      tar -xzf "$CHARTREFERENCE"
      CHARTNAME=$(tar tzf "$CHARTREFERENCE" | sed -e 's@/.*@@' | uniq)
      flag=1
    fi
  fi
  set +e
  if [[ ! -z "$CHARTVERSION" ]]; then
    helm ${PASSTHRU[@]} --version "$CHARTVERSION" --set bucketAccessPolicy="${CONFIG_BUCKET_ACCESS_POLICY}" --set region=${REGION} --set dcname="${DC_NAME}" --set provider="${CLUSTER_PROVIDER}" --set workerOS="${WORKER_OS}" --set platform="${PLATFORM}" --set kubeDriver="${KUBE_DRIVER_PATH}" "${FLAGS[@]}"
  else
    helm ${PASSTHRU[@]} --set dcname="${DC_NAME}" --set bucketAccessPolicy="${CONFIG_BUCKET_ACCESS_POLICY}" --set region=${REGION} --set provider="${CLUSTER_PROVIDER}" --set workerOS="${WORKER_OS}" --set platform="${PLATFORM}" --set kubeDriver="${KUBE_DRIVER_PATH}" "${FLAGS[@]}"
  fi
  exit_status=$(echo $?)
  if [[ $exit_status -ne 0 ]]; then
    if [[ $flag -eq 1 ]]; then
      rm -rf "$CHARTNAME"
    fi
    exit $exit_status
  fi
  set -e
  if [[ $flag -eq 1 ]]; then
    rm -rf "$CHARTNAME"
  fi
  exit 0
fi
