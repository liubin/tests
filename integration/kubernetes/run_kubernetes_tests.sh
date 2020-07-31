#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

source /etc/os-release || source /usr/lib/os-release
kubernetes_dir=$(dirname "$(readlink -f "$0")")
cidir="${kubernetes_dir}/../../.ci/"
source "${cidir}/lib.sh"

arch="$(uname -m)"

KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"

if [ "$KATA_HYPERVISOR" == "firecracker" ]; then
	die "Kubernetes tests will not run with $KATA_HYPERVISOR"
fi

# Using trap to ensure the cleanup occurs when the script exists.
trap '${kubernetes_dir}/cleanup_env.sh' EXIT

# Docker is required to initialize kubeadm, even if we are
# using cri-o as the runtime.
systemctl is-active --quiet docker || sudo systemctl start docker


K8S_TEST_UNION=("k8s-custom-dns.bats")

if [ "${KATA_HYPERVISOR:-}" == "cloud-hypervisor" ]; then
	sysctl_issue="https://github.com/kata-containers/tests/issues/2324"
	info "$KATA_HYPERVISOR sysctl is failing:"
	info "sysctls: ${sysctl_issue}"

	oom_issue="https://github.com/kata-containers/tests/issues/2864"
	info "$KATA_HYPERVISOR is failing on:"
	info "pod oom: ${oom_issue}"
else
	K8S_TEST_UNION+=("k8s-sysctls.bats")
	# filter_k8s_test.sh requires a space at the end of the last component
	K8S_TEST_UNION+=("k8s-oom.bats ")
fi

# we may need to skip a few test cases when running on non-x86_64 arch
if [ -f "${cidir}/${arch}/configuration_${arch}.yaml" ]; then
	config_file="${cidir}/${arch}/configuration_${arch}.yaml"
	arch_k8s_test_union=$(${cidir}/filter/filter_k8s_test.sh ${config_file} "${K8S_TEST_UNION[*]}")
	mapfile -d " " -t K8S_TEST_UNION <<< "${arch_k8s_test_union}"
fi

pushd "$kubernetes_dir"
./init.sh
for K8S_TEST_ENTRY in ${K8S_TEST_UNION[@]}
do
	bats -t "${K8S_TEST_ENTRY}"
done
popd
