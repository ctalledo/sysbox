#!/usr/bin/env bats

#
# Verify trapping & emulation on "mount" and "unmount2" syscalls
#

load ../helpers/run
load ../helpers/syscall
load ../helpers/docker
load ../helpers/environment
load ../helpers/mounts
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

#
# Test to verify common mount syscall checks performed by sysbox
#

# Verify that mount syscall emulation performs correct path resolution (per path_resolution(7))
@test "mount path-resolution" {

  # TODO: test chmod dir permissions & path-resolution

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # absolute path
  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # relative path
  docker exec "$syscont" bash -c "cd /root/l1 && mount -t proc proc l2/proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # .. in path
  docker exec "$syscont" bash -c "cd /root/l1/l2 && mount -t proc proc ../../../root/l1/l2/proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # . in path
  docker exec "$syscont" bash -c "cd /root/l1/l2 && mount -t proc proc ./proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "cd $mnt_path && mount -t proc proc ."
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # relative symlink
  docker exec "$syscont" bash -c "cd /root && ln -s l1/l2 l2link"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "cd /root && mount -t proc proc l2link/proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "rm /root/l2link"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # relative symlink at end
  docker exec "$syscont" bash -c "cd /root && ln -s l1/l2/proc proclink"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "cd /root && mount -t proc proc proclink"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "rm /root/proclink"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # abs symlink
  docker exec "$syscont" bash -c "cd /root && ln -s /root/l1/l2/proc abslink"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "cd /root && mount -t proc proc abslink"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "rm /root/abslink"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # invalid path
  docker exec "$syscont" bash -c "cd /root && mount -t proc proc invalidpath"
  [ "$status" -eq 255 ]
  [[ "$output" =~ "No such file or directory" ]]

  # TODO: overly long path (> MAXPATHLEN) returns in ENAMETOOLONG

  # TODO: mount syscall with empty mount path (should return ENOENT)
  # requires calling mount syscall directly

  docker_stop "$syscont"
}

# Verify that mount syscall emulation does correct permission checks
@test "mount permission checking" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # root user can mount
  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path

  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # a non-root user can't mount (needs cap_sys_admin)
  docker exec "$syscont" bash -c "useradd -m -u 1000 someone"
  [ "$status" -eq 0 ]

  docker exec -u 1000:1000 "$syscont" bash -c "mkdir -p /home/someone/l1/l2/proc && mount -t proc proc /home/someone/l1/l2/proc"
  [ "$status" -eq 1 ]

  docker_stop "$syscont"
}

# Verify that mount syscall emulation does correct capability checks
@test "mount capability checking" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # root user without CAP_SYS_ADMIN can't mount
  docker exec "$syscont" bash -c "capsh --inh=\"\" --drop=cap_sys_admin -- -c \"mount -t proc proc $mnt_path\""
  [ "$status" -ne 0 ]

  # root user without CAP_DAC_OVERRIDE, CAP_DAC_READ_SEARCH can't mount if path is non-searchable
  docker exec "$syscont" bash -c "chmod 400 /root/l1"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "capsh --inh=\"\" --drop=cap_dac_override,cap_dac_read_search -- -c \"mount -t proc proc $mnt_path\""
  [ "$status" -ne 0 ]

  # a non-root user with appropriate caps can perform the mount; we use the
  # mountProcDac program to obtain these caps.

  make -C "$SYSBOX_ROOT/tests/scr/capRaise"

  docker exec "$syscont" bash -c "useradd -u 1000 someone"
  [ "$status" -eq 0 ]

   # copy mountProcDac program and set file caps on it
  docker cp "$SYSBOX_ROOT/tests/scr/capRaise/mountProcDac" "$syscont:/usr/bin"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "chown someone:someone /usr/bin/mountProcDac"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c 'setcap "cap_sys_admin,cap_dac_read_search,cap_dac_override=p" /usr/bin/mountProcDac'
  [ "$status" -eq 0 ]

  # perform the mount with mountProcDac
  docker exec -u 1000:1000 "$syscont" bash -c "mountProcDac $mnt_path"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

#
# Test to verify sys container immutable mounts.
#
# Note: a sys container immutable mount is a mount that is setup at container
# creation time.
#

# Ensure immutable mounts can't be unmounted from inside the container
@test "immutable mount can't be unmounted" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)

  local immutable_mounts=$(list_container_mounts $syscont)

  for m in $immutable_mounts; do
    printf "\ntesting unmount of immutable mount $m\n"

    docker exec "$syscont" sh -c "umount $m"
    [ "$status" -ne 0 ]
  done

  local immutable_mounts_after=$(list_container_mounts $syscont)

  [[ $immutable_ro_mounts == $immutable_ro_mounts_after ]]

  docker_stop "$syscont"
}

# Ensure that a read-only immutable mount can't be remounted as read-write
# inside the container.
@test "immutable ro mount can't be remounted rw" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)

  local immutable_ro_mounts=$(list_container_ro_mounts $syscont)

  for m in $immutable_ro_mounts; do
    printf "\ntesting rw remount of immutable ro mount $m\n"

    docker exec "$syscont" sh -c "mount -o remount,bind,rw $m"
    [ "$status" -ne 0 ]
  done

  local immutable_ro_mounts_after=$(list_container_ro_mounts $syscont)

  [[ $immutable_ro_mounts == $immutable_ro_mounts_after ]]

  docker_stop "$syscont"
}

# Ensure that a read-write immutable mount *can* be remounted as read-only inside
# the container.
@test "immutable rw mount can be remounted ro" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)

  local immutable_rw_mounts=$(list_container_rw_mounts $syscont)

  for m in $immutable_rw_mounts; do

    # Remounting /proc or /dev as read-only will prevent docker execs into the
    # container; skip these.

    if [[ $m =~ "/proc" ]] || [[ $m =~ "/proc/*" ]] ||
       [[ $m =~ "/dev" ]] || [[ $m =~ "/dev/*" ]]; then
      continue
    fi

    printf "\ntesting ro remount of immutable rw mount $m\n"

    docker exec "$syscont" sh -c "mount -o remount,bind,ro $m"
    [ "$status" -eq 0 ]
  done

  docker_stop "$syscont"
}

# Ensure that a read-only immutable mount *can* be remounted as read-only inside
# the container.
@test "immutable ro mount can be remounted ro" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)

  local immutable_ro_mounts=$(list_container_ro_mounts $syscont)

  for m in $immutable_ro_mounts; do
    printf "\ntesting ro remount of immutable ro mount $m\n"

    docker exec "$syscont" sh -c "mount -o remount,bind,ro $m"
    [ "$status" -eq 0 ]
  done

  local immutable_ro_mounts_after=$(list_container_ro_mounts $syscont)

  [[ $immutable_ro_mounts == $immutable_ro_mounts_after ]]

  docker_stop "$syscont"
}

# Ensure that a read-write immutable mount *can* be remounted as read-write or
# read-only inside the container.
@test "immutable rw mount can be remounted rw" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)

  local immutable_rw_mounts=$(list_container_rw_mounts $syscont)

  for m in $immutable_rw_mounts; do
    printf "\ntesting rw remount of immutable rw mount $m\n"

    docker exec "$syscont" sh -c "mount -o remount,bind,rw $m"
    [ "$status" -eq 0 ]
  done

  local immutable_rw_mounts_after=$(list_container_rw_mounts $syscont)

  [[ $immutable_rw_mounts == $immutable_rw_mounts_after ]]

  docker_stop "$syscont"
}
