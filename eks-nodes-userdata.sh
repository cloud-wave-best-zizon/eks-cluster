#!/bin/bash
set -ex
cat <<'EKS_BOOTSTRAP_EOF' >> /etc/eks/bootstrap.sh
export KUBELET_EXTRA_ARGS="${KUBELET_EXTRA_ARGS} --read-only-port=10255"
EKS_BOOTSTRAP_EOF
