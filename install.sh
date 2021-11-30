#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

GIT_PREFIX="https://github.com"
CONTAINER_REGISTRY_PREFIX="ghcr.io"

KUBERNETES_CONTAINER_REGISTRY=${KUBERNETES_CONTAINER_REGISTRY:-"${CONTAINER_REGISTRY_PREFIX}/klts-io/kubernetes-lts"}

# Version
KUBERNETES_VERSION=${KUBERNETES_VERSION:-"1.18.20-lts.1"}
CONTAINERD_VERSION=${CONTAINERD_VERSION:-"1.3.10-lts.0"}
RUNC_VERSION=${RUNC_VERSION:-"1.0.2-lts.0"}

# RPM Packages
KUBERNETES_RPM_SOURCE=${KUBERNETES_RPM_SOURCE:-"${GIT_PREFIX}/klts-io/kubernetes-lts/raw/rpm-v${KUBERNETES_VERSION}"}
CONTAINERD_RPM_SOURCE=${CONTAINERD_RPM_SOURCE:-"${GIT_PREFIX}/klts-io/containerd-lts/raw/rpm-v${CONTAINERD_VERSION}"}
RUNC_RPM_SOURCE=${RUNC_RPM_SOURCE:-"${GIT_PREFIX}/klts-io/runc-lts/raw/rpm-v${RUNC_VERSION}"}
OTHERS_RPM_SOURCE=${OTHERS_RPM_SOURCE:-"${GIT_PREFIX}/klts-io/others/raw/rpm"}

# DEB Packages
KUBERNETES_DEB_SOURCE=${KUBERNETES_DEB_SOURCE:-"${GIT_PREFIX}/klts-io/kubernetes-lts/raw/deb-v${KUBERNETES_VERSION}"}
CONTAINERD_DEB_SOURCE=${CONTAINERD_DEB_SOURCE:-"${GIT_PREFIX}/klts-io/containerd-lts/raw/deb-v${CONTAINERD_VERSION}"}
RUNC_DEB_SOURCE=${RUNC_DEB_SOURCE:-"${GIT_PREFIX}/klts-io/runc-lts/raw/deb-v${RUNC_VERSION}"}
OTHERS_DEB_SOURCE=${OTHERS_DEB_SOURCE:-"${GIT_PREFIX}/klts-io/others/raw/deb"}

STEPS=(
    # Setup Iptables bridge
    enable-iptables-discover-bridged-traffic

    # Disable Swap
    disable-swap

    # Disable SELinux
    disable-selinux

    # Setup Repositories Source
    setup-source

    # Install Dependencies
    install-kubernetes
    install-containerd
    install-runc
    install-crictl
    install-cniplugins

    # Setup Configurations
    setup-crictl-config
    setup-containerd-cni-config
    setup-kubelet-config
    setup-containerd-config

    # Daemon Reload
    daemon-reload

    # Start Containerd Services
    start-containerd
    status-containerd
    enable-containerd

    # Start Kubelet Services
    start-kubelet
    status-kubelet
    enable-kubelet

    # Pull Images Early
    images-pull

    # Initialize Kubernetes Control Plane
    control-plane-init

    # Show Nodes Infomation
    status-nodes

    # Show Node Join Command
    show-join-command
)

function command-exists() {
    command -v "$@" >/dev/null 2>&1
}

function options-parsing() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        case ${key} in
         --kubernetes-container-registry | --kubernetes-container-registry=*)
            [[ "${key#*=}" != "$key" ]] && KUBERNETES_CONTAINER_REGISTRY="${key#*=}" || { KUBERNETES_CONTAINER_REGISTRY="$2" && shift; }
            ;;
        --kubernetes-version | --kubernetes-version=*)
            [[ "${key#*=}" != "$key" ]] && KUBERNETES_VERSION="${key#*=}" || { KUBERNETES_VERSION="$2" && shift; }
            ;;
        --containerd-version | --containerd-version=*)
            [[ "${key#*=}" != "$key" ]] && CONTAINERD_VERSION="${key#*=}" || { CONTAINERD_VERSION="$2" && shift; }
            ;;
        --runc-version | --runc-version=*)
            [[ "${key#*=}" != "$key" ]] && RUNC_VERSION="${key#*=}" || { RUNC_VERSION="$2" && shift; }
            ;;
        --kubernetes-rpm-source | --kubernetes-rpm-source=*)
            [[ "${key#*=}" != "$key" ]] && KUBERNETES_RPM_SOURCE="${key#*=}" || { KUBERNETES_RPM_SOURCE="$2" && shift; }
            ;;
        --containerd-rpm-source | --containerd-rpm-source=*)
            [[ "${key#*=}" != "$key" ]] && CONTAINERD_RPM_SOURCE="${key#*=}" || { CONTAINERD_RPM_SOURCE="$2" && shift; }
            ;;
        --runc-rpm-source | --runc-rpm-source=*)
            [[ "${key#*=}" != "$key" ]] && RUNC_RPM_SOURCE="${key#*=}" || { RUNC_RPM_SOURCE="$2" && shift; }
            ;;
        --others-rpm-source | --others-rpm-source=*)
            [[ "${key#*=}" != "$key" ]] && OTHERS_RPM_SOURCE="${key#*=}" || { OTHERS_RPM_SOURCE="$2" && shift; }
            ;;
        --kubernetes-deb-source | --kubernetes-deb-source=*)
            [[ "${key#*=}" != "$key" ]] && KUBERNETES_DEB_SOURCE="${key#*=}" || { KUBERNETES_DEB_SOURCE="$2" && shift; }
            ;;
        --containerd-deb-source | --containerd-deb-source=*)
            [[ "${key#*=}" != "$key" ]] && CONTAINERD_DEB_SOURCE="${key#*=}" || { CONTAINERD_DEB_SOURCE="$2" && shift; }
            ;;
        --runc-deb-source | --runc-deb-source=*)
            [[ "${key#*=}" != "$key" ]] && RUNC_DEB_SOURCE="${key#*=}" || { RUNC_DEB_SOURCE="$2" && shift; }
            ;;
        --others-deb-source | --others-deb-source=*)
            [[ "${key#*=}" != "$key" ]] && OTHERS_DEB_SOURCE="${key#*=}" || { OTHERS_DEB_SOURCE="$2" && shift; }
            ;;
        --focus | --focus=*)
            local focus=""
            [[ "${key#*=}" != "$key" ]] && focus="${key#*=}" || { focus="$2" && shift; }
            IFS=',' read -ra STEPS <<<"${focus}"
            for add in ${STEPS[@]}; do
                if ! command-exists step-${add}; then
                    echo "Step ${add} not exists"
                    exit 3
                fi
            done
            ;;
        --skip | --skip=*)
            local skip=""
            local skipArr=()
            [[ "${key#*=}" != "$key" ]] && skip="${key#*=}" || { skip="$2" && shift; }
            IFS=',' read -ra skipArr <<<"${skip}"
            for del in ${skipArr[@]}; do
                if ! command-exists step-${del}; then
                    echo "Step ${del} not exists"
                    exit 3
                fi
                STEPS=("${STEPS[@]/${del}/}")
            done
            ;;
        --help | -h)
            help
            exit 0
            ;;
        *)
            echo "Unknown option: ${key}"
            exit 3
            ;;
        esac
        shift
    done
}

function help() {
    echo "Usage: $0 [OPTIONS]"
    echo "  -h, --help : Display this help and exit"
    echo "  --kubernetes-container-registry=${KUBERNETES_CONTAINER_REGISTRY} : Kubernetes container registry"
    echo "  --kubernetes-version=${KUBERNETES_VERSION} : Kubernetes version to install"
    echo "  --containerd-version=${CONTAINERD_VERSION} : Containerd version to install"
    echo "  --runc-version=${RUNC_VERSION} : Runc version to install"
    echo "  --kubernetes-rpm-source=${KUBERNETES_RPM_SOURCE} : Kubernetes RPM source"
    echo "  --containerd-rpm-source=${CONTAINERD_RPM_SOURCE} : Containerd RPM source"
    echo "  --runc-rpm-source=${RUNC_RPM_SOURCE} : Runc RPM source"
    echo "  --others-rpm-source=${OTHERS_RPM_SOURCE} : Other RPM source"
    echo "  --kubernetes-deb-source=${KUBERNETES_DEB_SOURCE} : Kubernetes DEB source"
    echo "  --containerd-deb-source=${CONTAINERD_DEB_SOURCE} : Containerd DEB source"
    echo "  --runc-deb-source=${RUNC_DEB_SOURCE} : Runc DEB source"
    echo "  --others-deb-source=${OTHERS_DEB_SOURCE} : Other DEB source"
    local tmp="${STEPS[*]}"
    echo "  --focus=${tmp//${IFS:0:1}/,} : Focus on specific step"
    echo "  --skip='' : Skip on specific step"
}

if [[ $(uname -s) != "Linux" ]]; then
    help
    echo "This script is only for Linux"
    exit 1
fi

function rpm-source-template() {
    cat <<EOF
# KLTS

[klts-kubernetes]
name=KLTS - Kubernetes
baseurl=${KUBERNETES_RPM_SOURCE}/\$basearch/
enabled=1
gpgcheck=0

[klts-containerd]
name=KLTS - Containerd
baseurl=${CONTAINERD_RPM_SOURCE}/\$basearch/
enabled=1
gpgcheck=0

[klts-runc]
name=KLTS - RunC
baseurl=${RUNC_RPM_SOURCE}/\$basearch/
enabled=1
gpgcheck=0

[klts-others]
name=KLTS - Others
baseurl=${OTHERS_RPM_SOURCE}/\$basearch/
enabled=1
gpgcheck=0

EOF
}

function deb-source-template() {
    cat <<EOF
# KLTS

deb [trusted=yes] ${KUBERNETES_DEB_SOURCE}/ stable main
deb [trusted=yes] ${CONTAINERD_DEB_SOURCE}/ stable main
deb [trusted=yes] ${RUNC_DEB_SOURCE}/ stable main
deb [trusted=yes] ${OTHERS_DEB_SOURCE}/ stable main

EOF
}

function setup-source-rpm() {
    rpm-source-template >/etc/yum.repos.d/klts.repo
    yum makecache
}

function setup-source-deb() {
    apt-get update -y
    apt-get install -y ca-certificates
    deb-source-template >/etc/apt/sources.list.d/klts.list
    apt-get update -y
}

function step-setup-source() {
    if command-exists yum; then
        setup-source-rpm
    elif command-exists apt-get; then
        setup-source-deb
    else
        echo "Unsupported Package Manager"
        exit 1
    fi
}

function install-kubernetes-rpm() {
    yum install -y "kubeadm-${KUBERNETES_VERSION}" "kubelet-${KUBERNETES_VERSION}" "kubectl-${KUBERNETES_VERSION}"
}

function install-kubernetes-deb() {
    apt-get install -y "kubeadm=${KUBERNETES_VERSION}" "kubelet=${KUBERNETES_VERSION}" "kubectl=${KUBERNETES_VERSION}"
}

function step-install-kubernetes() {
    if command-exists yum; then
        install-kubernetes-rpm
    elif command-exists apt-get; then
        install-kubernetes-deb
    else
        echo "Unsupported Package Manager"
        exit 1
    fi
}

function install-containerd-rpm() {
    yum install -y "containerd-${CONTAINERD_VERSION}"
}

function install-containerd-deb() {
    apt-get install -y "containerd=${CONTAINERD_VERSION}"
}

function step-install-containerd() {
    if command-exists yum; then
        install-containerd-rpm
    elif command-exists apt-get; then
        install-containerd-deb
    else
        echo "Unsupported Package Manager"
        exit 1
    fi
}

function install-runc-rpm() {
    yum install -y "runc-${RUNC_VERSION}"
}

function install-runc-deb() {
    apt-get install -y "runc=${RUNC_VERSION}"
}

function step-install-runc() {
    if command-exists yum; then
        install-runc-rpm
    elif command-exists apt-get; then
        install-runc-deb
    else
        echo "Unsupported Package Manager"
        exit 1
    fi
}

function install-crictl-rpm() {
    yum install -y cri-tools
}

function install-crictl-deb() {
    apt-get install -y cri-tools
}

function step-install-crictl() {
    if command-exists yum; then
        install-crictl-rpm
    elif command-exists apt-get; then
        install-crictl-deb
    else
        echo "Unsupported Package Manager"
        exit 1
    fi
}

function install-cniplugins-rpm() {
    yum install -y kubernetes-cni
}

function install-cniplugins-deb() {
    apt-get install -y kubernetes-cni
}

function step-install-cniplugins() {
    if command-exists yum; then
        install-cniplugins-rpm
    elif command-exists apt-get; then
        install-cniplugins-deb
    else
        echo "Unsupported Package Manager"
        exit 1
    fi
}

function step-setup-crictl-config() {
    cat <<EOF >/etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF
}

function step-setup-containerd-cni-config() {
    mkdir -p /etc/cni/net.d/
    cat <<EOF >/etc/cni/net.d/10-containerd-net.conflist
{
  "cniVersion": "0.4.0",
  "name": "containerd-net",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cni0",
      "isGateway": true,
      "ipMasq": true,
      "promiscMode": true,
      "ipam": {
        "type": "host-local",
        "ranges": [
          [{
            "subnet": "10.88.0.0/16"
          }],
          [{
            "subnet": "2001:4860:4860::/64"
          }]
        ],
        "routes": [
          { "dst": "0.0.0.0/0" },
          { "dst": "::/0" }
        ]
      }
    },
    {
      "type": "portmap",
      "capabilities": {"portMappings": true}
    }
  ]
}
EOF
}

function kubelet-config-template() {
    cat <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--container-runtime=remote --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock"
EOF
}

function step-setup-kubelet-config() {
    if [[ -f /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf ]]; then
        kubelet-config-template >/usr/lib/systemd/system/kubelet.service.d/10-containerd.conf
    else
        mkdir -p /etc/systemd/system/kubelet.service.d/
        kubelet-config-template >/etc/systemd/system/kubelet.service.d/10-containerd.conf
    fi
}

function step-setup-containerd-config() {
    mkdir -p /etc/containerd
    sandbox_image=$(images-list | grep pause | head -n 1)
    containerd config default | sed "s|\(\s\+\)sandbox_image|\1sandbox_image = \"${sandbox_image}\"\\n\1# sandbox_image|g" >/etc/containerd/config.toml
}

function step-enable-containerd() {
    systemctl enable containerd || :
}

function step-start-containerd() {
    systemctl start containerd
}

function step-status-containerd() {
    systemctl status containerd | cat
}

function step-enable-kubelet() {
    systemctl enable kubelet || :
}

function step-start-kubelet() {
    systemctl start kubelet
}

function step-status-kubelet() {
    systemctl status kubelet | cat
}

function step-daemon-reload() {
    systemctl daemon-reload
}

function step-enable-iptables-discover-bridged-traffic() {
    modprobe br_netfilter &&
        echo "br_netfilter" >/etc/modules-load.d/k8s.conf &&
        echo "1" >/proc/sys/net/bridge/bridge-nf-call-iptables &&
        echo "1" >/proc/sys/net/bridge/bridge-nf-call-ip6tables &&
        sysctl --system ||
        echo "Failed to enable iptables discover bridged traffic"
}

function step-disable-swap() {
    swapoff -a ||
        echo "Failed to disable swap"
}

function step-disable-selinux() {
    setenforce 0 ||
        echo "Failed to disable selinux"
}

function images-list() {
    kubeadm config images list --image-repository "${KUBERNETES_CONTAINER_REGISTRY}" --kubernetes-version "v${KUBERNETES_VERSION}"
}

function step-images-pull() {
    for image in $(images-list); do
        echo "Pulling image: ${image}" >&2
        ctr -n k8s.io images pull "${image}"
    done
}

function get-discovery-token-ca-cert-hash() {
    openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'
}

function find-token() {
    kubeadm --kubeconfig=/etc/kubernetes/admin.conf token list -o 'go-template={{.token}}{{"\n"}}' | head -n 1
}

function find-token-expires() {
    kubeadm --kubeconfig=/etc/kubernetes/admin.conf token list -o 'go-template={{.expires}}{{"\n"}}' | head -n 1
}

function create-token() {
    kubeadm --kubeconfig=/etc/kubernetes/admin.conf token create
}

function get-token() {
    local token=""
    token="$(find-token)"
    if [[ "${token}" == "" ]]; then
        token=$(create-token)
    fi
    echo "${token}"
}

function get-local-ip() {
    ip addr | grep global | grep inet | grep -v cni | awk '/inet.*global/ {print gensub(/(.*)\/(.*)/, "\\1", "g", $2)}' | head -n 1
}

function step-control-plane-init() {
    kubeadm init --image-repository "${KUBERNETES_CONTAINER_REGISTRY}" --kubernetes-version "v${KUBERNETES_VERSION}"
}

function step-status-nodes() {
    kubectl --kubeconfig=/etc/kubernetes/kubelet.conf get nodes -o wide
}

function step-show-join-command() {
    cat <<EOF

Then you can join any number of worker nodes by running the following on each as root:

$0 \\
    --skip images-pull,control-plane-init,show-join-command \\
    --kubernetes-container-registry ${KUBERNETES_CONTAINER_REGISTRY} \\
    --kubernetes-version ${KUBERNETES_VERSION} \\
    --containerd-version ${CONTAINERD_VERSION} \\
    --runc-version ${RUNC_VERSION} \\
    --kubernetes-rpm-source ${KUBERNETES_RPM_SOURCE} \\
    --containerd-rpm-source ${CONTAINERD_RPM_SOURCE} \\
    --runc-rpm-source ${RUNC_RPM_SOURCE} \\
    --others-rpm-source ${OTHERS_RPM_SOURCE} \\
    --kubernetes-deb-source ${KUBERNETES_DEB_SOURCE} \\
    --containerd-deb-source ${CONTAINERD_DEB_SOURCE} \\
    --runc-deb-source ${RUNC_DEB_SOURCE} \\
    --others-deb-source ${OTHERS_DEB_SOURCE} \\
    && \\
kubeadm join $(get-local-ip):6443 \\
    --token $(get-token) \\
    --discovery-token-ca-cert-hash sha256:$(get-discovery-token-ca-cert-hash)

The token expiration time $(find-token-expires)
Then you can get/regenerate token by running the following on the control plane node:

$0 --focus=show-join-command

EOF
}

function main() {
    for step in ${STEPS[@]}; do
        local title="${step//-/ }"
        echo ">>>>>>>>>>>> ${title^} >>>>>>>>>>>>" >&2
        "step-${step}" || {
            echo "<<<<<<<<<<<< Failed ${title^} <<<<<<<<<<<<" >&2
            exit 1
        }
        echo "<<<<<<<<<<<< ${title^} <<<<<<<<<<<<" >&2
    done
}

options-parsing "$@"

main
