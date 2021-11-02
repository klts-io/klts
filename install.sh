#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

if [[ $(uname -s) != "Linux" ]]; then
    echo "This script is only for Linux"
    exit 1
fi

GIT_PREFIX="https://github.com"
CONTAINER_REGISTRY_PREFIX="ghcr.io"

KUBERNETES_CONTAINER_REGISTRY=${KUBERNETES_CONTAINER_REGISTRY:-"${CONTAINER_REGISTRY_PREFIX}/klts-io/kubernetes-lts"}

# Version
KUBERNETES_VERSION=${KUBERNETES_VERSION:-"1.18.20-lts.0"}
CONTAINERD_VERSION=${CONTAINERD_VERSION:-"1.3.10-lts.0"}
RUNC_VERSION=${RUNC_VERSION:-"1.0.2-lts.0"}

# RPM Packages
KUBERNETES_RPM_REPOS=${KUBERNETES_RPM_REPOS:-"${GIT_PREFIX}/klts-io/kubernetes-lts/raw/rpm-v${KUBERNETES_VERSION}"}
CONTAINERD_RPM_REPOS=${CONTAINERD_RPM_REPOS:-"${GIT_PREFIX}/klts-io/containerd-lts/raw/rpm-v${CONTAINERD_VERSION}"}
RUNC_RPM_REPOS=${RUNC_RPM_REPOS:-"${GIT_PREFIX}/klts-io/runc-lts/raw/rpm-v${RUNC_VERSION}"}
OTHERS_RPM_REPOS=${OTHERS_RPM_REPOS:-"${GIT_PREFIX}/klts-io/others/raw/rpm"}

# DEB Packages
KUBERNETES_DEB_REPOS=${KUBERNETES_DEB_REPOS:-"${GIT_PREFIX}/klts-io/kubernetes-lts/raw/deb-v${KUBERNETES_VERSION}"}
CONTAINERD_DEB_REPOS=${CONTAINERD_DEB_REPOS:-"${GIT_PREFIX}/klts-io/containerd-lts/raw/deb-v${CONTAINERD_VERSION}"}
RUNC_DEB_REPOS=${RUNC_DEB_REPOS:-"${GIT_PREFIX}/klts-io/runc-lts/raw/deb-v${RUNC_VERSION}"}
OTHERS_DEB_REPOS=${OTHERS_DEB_REPOS:-"${GIT_PREFIX}/klts-io/others/raw/deb"}

STEPS=(
    setup-source
    install
    setup-config
    setup-containerd
    setup-kubelet
    netfilter
    swapoff
    images-pull
    control-plane-init
    show-join-command
)

function command_exists() {
    command -v "$@" >/dev/null 2>&1
}

function options_parsing() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
        --kubernetes-version | --kubernetes-version=*)
            [[ "${key#*=}" != "$key" ]] && KUBERNETES_VERSION="${key#*=}" || { KUBERNETES_VERSION="$2" && shift; }
            ;;
        --containerd-version | --containerd-version=*)
            [[ "${key#*=}" != "$key" ]] && CONTAINERD_VERSION="${key#*=}" || { CONTAINERD_VERSION="$2" && shift; }
            ;;
        --runc-version | --runc-version=*)
            [[ "${key#*=}" != "$key" ]] && RUNC_VERSION="${key#*=}" || { RUNC_VERSION="$2" && shift; }
            ;;
        --kubernetes-rpm-repos | --kubernetes-rpm-repos=*)
            [[ "${key#*=}" != "$key" ]] && KUBERNETES_RPM_REPOS="${key#*=}" || { KUBERNETES_RPM_REPOS="$2" && shift; }
            ;;
        --containerd-rpm-repos | --containerd-rpm-repos=*)
            [[ "${key#*=}" != "$key" ]] && CONTAINERD_RPM_REPOS="${key#*=}" || { CONTAINERD_RPM_REPOS="$2" && shift; }
            ;;
        --runc-rpm-repos | --runc-rpm-repos=*)
            [[ "${key#*=}" != "$key" ]] && RUNC_RPM_REPOS="${key#*=}" || { RUNC_RPM_REPOS="$2" && shift; }
            ;;
        --others-rpm-repos | --others-rpm-repos=*)
            [[ "${key#*=}" != "$key" ]] && OTHERS_RPM_REPOS="${key#*=}" || { OTHERS_RPM_REPOS="$2" && shift; }
            ;;
        --kubernetes-deb-repos | --kubernetes-deb-repos=*)
            [[ "${key#*=}" != "$key" ]] && KUBERNETES_DEB_REPOS="${key#*=}" || { KUBERNETES_DEB_REPOS="$2" && shift; }
            ;;
        --containerd-deb-repos | --containerd-deb-repos=*)
            [[ "${key#*=}" != "$key" ]] && CONTAINERD_DEB_REPOS="${key#*=}" || { CONTAINERD_DEB_REPOS="$2" && shift; }
            ;;
        --runc-deb-repos | --runc-deb-repos=*)
            [[ "${key#*=}" != "$key" ]] && RUNC_DEB_REPOS="${key#*=}" || { RUNC_DEB_REPOS="$2" && shift; }
            ;;
        --others-deb-repos | --others-deb-repos=*)
            [[ "${key#*=}" != "$key" ]] && OTHERS_DEB_REPOS="${key#*=}" || { OTHERS_DEB_REPOS="$2" && shift; }
            ;;
        --focus | --focus=*)
            local focus=""
            [[ "${key#*=}" != "$key" ]] && focus="${key#*=}" || { focus="$2" && shift; }
            IFS=',' read -a STEPS <<<"${focus}"
            for add in ${STEPS[@]}; do
                if ! command_exists step-${add}; then
                    echo Step ${add} not exists
                    exit 3
                fi
            done
            ;;
        --skip | --skip=*)
            local skip=""
            local skipArr=()
            [[ "${key#*=}" != "$key" ]] && skip="${key#*=}" || { skip="$2" && shift; }
            IFS=',' read -a skipArr <<<"$skip"
            for del in ${skipArr[@]}; do
                if ! command_exists step-${del}; then
                    echo Step ${del} not exists
                    exit 3
                fi
                STEPS=(${STEPS[@]/${del}/})
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
    echo "  --kubernetes-version=${KUBERNETES_VERSION} : Kubernetes version to install"
    echo "  --containerd-version=${CONTAINERD_VERSION} : Containerd version to install"
    echo "  --runc-version=${RUNC_VERSION} : Runc version to install"
    echo "  --kubernetes-rpm-repos=${KUBERNETES_RPM_REPOS} : Kubernetes RPM repos"
    echo "  --containerd-rpm-repos=${CONTAINERD_RPM_REPOS} : Containerd RPM repos"
    echo "  --runc-rpm-repos=${RUNC_RPM_REPOS} : Runc RPM repos"
    echo "  --others-rpm-repos=${OTHERS_RPM_REPOS} : Other RPM repos"
    echo "  --kubernetes-deb-repos=${KUBERNETES_DEB_REPOS} : Kubernetes DEB repos"
    echo "  --containerd-deb-repos=${CONTAINERD_DEB_REPOS} : Containerd DEB repos"
    echo "  --runc-deb-repos=${RUNC_DEB_REPOS} : Runc DEB repos"
    echo "  --others-deb-repos=${OTHERS_DEB_REPOS} : Other DEB repos"
    echo "  --kubernetes-container-registry=${KUBERNETES_CONTAINER_REGISTRY} : Kubernetes container registry"
    local tmp="${STEPS[*]}"
    echo "  --focus=${tmp//${IFS:0:1}/,} : Focus on specific step"
    echo "  --skip='' : Skip on specific step"
}

function rpm-repos-template() {
    cat <<EOF
# KLTS

[klts-kubernetes]
name=KLTS - Kubernetes
baseurl=${KUBERNETES_RPM_REPOS}/\$basearch/
enabled=1
gpgcheck=0

[klts-containerd]
name=KLTS - Containerd
baseurl=${CONTAINERD_RPM_REPOS}/\$basearch/
enabled=1
gpgcheck=0

[klts-runc]
name=KLTS - RunC
baseurl=${RUNC_RPM_REPOS}/\$basearch/
enabled=1
gpgcheck=0

[klts-others]
name=KLTS - Others
baseurl=${OTHERS_RPM_REPOS}/\$basearch/
enabled=1
gpgcheck=0

EOF
}

function deb-repos-template() {
    cat <<EOF
# KLTS

deb [trusted=yes] ${KUBERNETES_DEB_REPOS}/ stable main
deb [trusted=yes] ${CONTAINERD_DEB_REPOS}/ stable main
deb [trusted=yes] ${RUNC_DEB_REPOS}/ stable main
deb [trusted=yes] ${OTHERS_DEB_REPOS}/ stable main

EOF
}

function step-rpm-setup-source() {
    rpm-repos-template >/etc/yum.repos.d/klts.repo
    yum makecache
}

function step-deb-setup-source() {
    apt-get update -y
    apt-get install -y ca-certificates
    deb-repos-template >/etc/apt/sources.list.d/klts.list
    apt-get update -y
}

function step-setup-source() {
    if command_exists yum; then
        step-rpm-setup-source
    elif command_exists apt-get; then
        step-deb-setup-source
    else
        echo "Unsupported Package Manager"
        exit 1
    fi
}

function step-rpm-install() {
    yum install -y kubeadm-${KUBERNETES_VERSION} kubelet-${KUBERNETES_VERSION} kubectl-${KUBERNETES_VERSION} containerd-${CONTAINERD_VERSION} runc-${RUNC_VERSION} cri-tools kubernetes-cni
}

function step-deb-install() {
    apt-get install -y kubeadm=${KUBERNETES_VERSION} kubelet=${KUBERNETES_VERSION} kubectl=${KUBERNETES_VERSION} containerd=${CONTAINERD_VERSION} runc=${RUNC_VERSION} cri-tools kubernetes-cni
}

function step-install() {
    if command_exists yum; then
        step-rpm-install
    elif command_exists apt-get; then
        step-deb-install
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

function step-setup-kubelet-config() {
    mkdir -p /etc/systemd/system/kubelet.service.d/
    cat <<EOF >/etc/systemd/system/kubelet.service.d/10-containerd.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--container-runtime=remote --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock"
EOF
}

function step-setup-config() {
    step-setup-crictl-config
    step-setup-containerd-cni-config
    step-setup-kubelet-config
    step-setup-containerd-config
}

function step-setup-containerd-config() {
    mkdir -p /etc/containerd
    sandbox_image=$(images-list | grep pause | head -n 1)
    containerd config default | sed "s|\(\s\+\)sandbox_image|\1sandbox_image = \"${sandbox_image}\"\\n\1# sandbox_image|g" >/etc/containerd/config.toml
}

function step-enable-containerd() {
    systemctl daemon-reload
    systemctl enable containerd
}

function step-start-containerd() {
    systemctl start containerd
}

function step-status-containerd() {
    systemctl status containerd
}

function step-setup-containerd() {
    step-enable-containerd
    step-start-containerd
    step-status-containerd
}

function step-enable-kubelet() {
    systemctl daemon-reload
    systemctl enable kubelet
}

function step-start-kubelet() {
    systemctl start kubelet
}

function step-status-kubelet() {
    systemctl status kubelet
}

function step-setup-kubelet() {
    step-enable-kubelet
    step-start-kubelet
    step-status-kubelet
}

function step-netfilter() {
    modprobe br_netfilter
    mkdir -p /proc/sys/net/bridge/
    echo "1" >/proc/sys/net/bridge/bridge-nf-call-iptables
    echo "1" >/proc/sys/net/bridge/bridge-nf-call-ip6tables
}

function step-swapoff() {
    swapoff -a
}

function images-list() {
    kubeadm config images list --image-repository ${KUBERNETES_CONTAINER_REGISTRY} --kubernetes-version v${KUBERNETES_VERSION}
}

function step-images-pull() {
    for image in $(images-list); do
        echo "Pulling image: ${image}" >&2
        crictl pull ${image}
    done
}

function get-discovery-token-ca-cert-hash() {
    openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'
}

function find-token() {
    kubeadm --kubeconfig=/etc/kubernetes/admin.conf token list -o 'go-template={{.token}}{{"\n"}}' | head -n 1
}

function create-token() {
    kubeadm --kubeconfig=/etc/kubernetes/admin.conf token create
}

function get-token() {
    local token="$(find-token)"
    if [[ "${token}" == "" ]]; then
        token=$(create-token)
    fi
    echo ${token}
}

function get-local-ip() {
    ip addr | grep global | grep inet | grep -v cni | awk '/inet.*global/ {print gensub(/(.*)\/(.*)/, "\\1", "g", $2)}' | head -n 1
}

function step-control-plane-init() {
    kubeadm init --image-repository ${KUBERNETES_CONTAINER_REGISTRY} --kubernetes-version v${KUBERNETES_VERSION}
}

function step-show-join-command() {
    cat <<EOF
Then you can join any number of worker nodes by running the following on each as root:

$0 \\
    --skip images-pull,control-plane-init \\
    --kubernetes-version ${KUBERNETES_VERSION} \\
    --containerd-version ${CONTAINERD_VERSION} \\
    --runc-version ${RUNC_VERSION} \\
    --kubernetes-rpm-repos ${KUBERNETES_RPM_REPOS} \\
    --containerd-rpm-repos ${CONTAINERD_RPM_REPOS} \\
    --runc-rpm-repos ${RUNC_RPM_REPOS} \\
    --others-rpm-repos ${OTHERS_RPM_REPOS} \\
    --kubernetes-deb-repos ${KUBERNETES_DEB_REPOS} \\
    --containerd-deb-repos ${CONTAINERD_DEB_REPOS} \\
    --runc-deb-repos ${RUNC_DEB_REPOS} \\
    --others-deb-repos ${OTHERS_DEB_REPOS} \\
    && \\
kubeadm join $(get-local-ip):6443 \\
    --token $(get-token) \\
    --discovery-token-ca-cert-hash sha256:$(get-discovery-token-ca-cert-hash)
EOF
}

function main() {
    for step in ${STEPS[@]}; do
        local title=${step//-/ }
        echo ">>>>>>>>>>>> ${title^} >>>>>>>>>>>>" >&2
        step-${step} || {
            echo "<<<<<<<<<<<< Fail ${title^} <<<<<<<<<<<<" >&2
            exit 1
        }
        echo "<<<<<<<<<<<< ${title^} <<<<<<<<<<<<" >&2
    done
}

options_parsing "$@"

main
