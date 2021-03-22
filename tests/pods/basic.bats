#!/usr/bin/env bats

#
# Basic tests for sysbox-pods (i.e., deploying pods with crictl + CRI-O + Sysbox)
#

load ../helpers/run
load ../helpers/sysbox-health
load ../helpers/crio

function teardown() {
  sysbox_log_check
}

@test "pod create" {

	local pod=$(crictl_runp ${POD_MANIFEST_DIR}/alpine-pod.json)
	local pod_pid=$(crictl_pod_get_pid $pod)

	# Verify the pod is rootless (uid_map & gid_map)
	local uid=$(cat /proc/${pod_pid}/uid_map | awk '{print $2}')
	local gid=$(cat /proc/${pod_pid}/gid_map | awk '{print $2}')

   local subuid=$(grep containers /etc/subuid | cut -d":" -f2)
   local subgid=$(grep containers /etc/subgid | cut -d":" -f2)

	[ $uid -eq $subuid ]
	[ $gid -eq $subgid ]

	# Verify the sysbox mounts are present
	cat /proc/${pod_pid}/mountinfo | grep sysboxfs

	crictl stopp $pod
	crictl rmp $pod
}

@test "pod run" {

	local syscont=$(crictl_run ${POD_MANIFEST_DIR}/alpine-container.json ${POD_MANIFEST_DIR}/alpine-pod.json)
	local syscont_pid=$(crictl_cont_get_pid $syscont)
	local pod=$(crictl_cont_get_pod $syscont)

	# Verify the pod's container is rootless
	local uid=$(cat /proc/${syscont_pid}/uid_map | awk '{print $2}')
	local gid=$(cat /proc/${syscont_pid}/gid_map | awk '{print $2}')

   local subuid=$(grep containers /etc/subuid | cut -d":" -f2)
   local subgid=$(grep containers /etc/subgid | cut -d":" -f2)

	[ $uid -eq $subuid ]
	[ $gid -eq $subgid ]

	# Verify the sysbox mounts are present
	cat /proc/${syscont_pid}/mountinfo | grep sysboxfs

	# Cleanup
	crictl stopp $pod
	crictl rmp $pod
}

# @test "multi-container pod" {

# 	# Verify all containers of a pod see shared sysbox-fs state

# }

# @test "multiple pods" {

# 	# Create several pods, verify each sees it's own sysbox-fs state
# }

# @test "docker-in-pod" {

# 	# Verify Docker works inside the sysbox pod

# }

# @test "systemd-in-pod" {

# 	# Verify Docker works inside the sysbox pod

# }

# @test "k8s-in-pod" {

# 	# Verify K8s works inside the sysbox pod
# }
