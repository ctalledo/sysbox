# GKE Cloud Shell

* GCP offers a cloud shell.

* It runs in a privileged K8s pod on top of a Debian Buster VM (kernel 5.4):

```
ctalledo@cloudshell:~ (predictive-fx-309900)$ uname -a
Linux cs-406612939017-default-default-nqhj5 5.4.89+ #1 SMP Wed Feb 24 19:44:28 PST 2021 x86_64 GNU/Linux

ctalledo@cloudshell:~ (predictive-fx-309900)$ lsb_release -a
No LSB modules are available.
Distributor ID: Debian
Description:    Debian GNU/Linux 10 (buster)
Release:        10
Codename:       buster
```

* The pod was apparently deployed with dockershim, as evidenced by the fact that `/etc/hostname` is backed by `/var/lib/docker/containers/..`.

* The pod has a mount over `/var/lib/docker` too (so that Docker can run inside)

* Dockerd is running inside the pod.

* The `gcloud` tool is also running inside the pod; it allows the shell to connect to GCP resources. E.g., to connect to a GKE cluster:


```
gcloud container clusters get-credentials my-first-cluster-1 --zone us-central1-c --project predictive-fx-309900
```


* Low-level details of the cloud shell pod:

```
root@cs-406612939017-default-default-pf99c:~# findmnt
TARGET                                SOURCE                                                                                                                  FSTYPE     OPTIONS
/                                     overlay                                                                                                                 overlay    rw,relatime,lowerdir=/var/lib/docker/overlay2/l/BF2JFCEOQZ2L2IYZ3A5UJE46NF:
├─/proc                               proc                                                                                                                    proc       rw,nosuid,nodev,noexec,relatime
├─/dev                                tmpfs                                                                                                                   tmpfs      rw,nosuid,size=65536k,mode=755
│ ├─/dev/pts                          devpts                                                                                                                  devpts     rw,nosuid,noexec,relatime,gid=5,mode=620,ptmxmode=666
│ ├─/dev/mqueue                       mqueue                                                                                                                  mqueue     rw,nosuid,nodev,noexec,relatime
│ ├─/dev/termination-log              /dev/sda1[/var/lib/kubelet/pods/7fccb20b4bbb99e737878eab4bb685c1/containers/cloudshell/6730d3ca]                        ext4       rw,nosuid,nodev,noexec,relatime,commit=30
│ └─/dev/shm                          shm                                                                                                                     tmpfs      rw,nosuid,nodev,noexec,relatime,size=65536k
├─/sys                                sysfs                                                                                                                   sysfs      ro,nosuid,nodev,noexec,relatime
│ ├─/sys/fs/cgroup                    tmpfs                                                                                                                   tmpfs      rw,nosuid,nodev,noexec,relatime,mode=755
│ │ ├─/sys/fs/cgroup/systemd          cgroup[/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f]
│ │ │                                                                                                                                                         cgroup     rw,nosuid,nodev,noexec,relatime,xattr,name=systemd
│ │ ├─/sys/fs/cgroup/pids             cgroup[/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f]
│ │ │                                                                                                                                                         cgroup     rw,nosuid,nodev,noexec,relatime,pids
│ │ ├─/sys/fs/cgroup/devices          cgroup[/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f]
│ │ │                                                                                                                                                         cgroup     rw,nosuid,nodev,noexec,relatime,devices
│ │ ├─/sys/fs/cgroup/hugetlb          cgroup[/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f]
│ │ │                                                                                                                                                         cgroup     rw,nosuid,nodev,noexec,relatime,hugetlb
│ │ ├─/sys/fs/cgroup/net_cls,net_prio cgroup[/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f]
│ │ │                                                                                                                                                         cgroup     rw,nosuid,nodev,noexec,relatime,net_cls,net_prio
│ │ ├─/sys/fs/cgroup/cpu,cpuacct      cgroup[/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f]
│ │ │                                                                                                                                                         cgroup     rw,nosuid,nodev,noexec,relatime,cpu,cpuacct
│ │ ├─/sys/fs/cgroup/freezer          cgroup[/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f]
│ │ │                                                                                                                                                         cgroup     rw,nosuid,nodev,noexec,relatime,freezer
│ │ ├─/sys/fs/cgroup/perf_event       cgroup[/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f]
│ │ │                                                                                                                                                         cgroup     rw,nosuid,nodev,noexec,relatime,perf_event
│ │ ├─/sys/fs/cgroup/cpuset           cgroup[/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f]
│ │ │                                                                                                                                                         cgroup     rw,nosuid,nodev,noexec,relatime,cpuset
│ │ ├─/sys/fs/cgroup/rdma             cgroup                                                                                                                  cgroup     rw,nosuid,nodev,noexec,relatime,rdma
│ │ ├─/sys/fs/cgroup/blkio            cgroup[/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f]
│ │ │                                                                                                                                                         cgroup     rw,nosuid,nodev,noexec,relatime,blkio
│ │ └─/sys/fs/cgroup/memory           cgroup[/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f]
│ │                                                                                                                                                           cgroup     rw,nosuid,nodev,noexec,relatime,memory
│ └─/sys/kernel/security              none                                                                                                                    securityfs rw,relatime
├─/root                               /dev/sda1[/var/lib/kubelet/pods/7fccb20b4bbb99e737878eab4bb685c1/volumes/kubernetes.io~empty-dir/root-home-directory]   ext4       rw,nosuid,nodev,noexec,relatime,commit=30
├─/home                               /dev/sda1[/var/google/home]                                                                                             ext4       rw,nosuid,nodev,noexec,relatime,commit=30
│ └─/home                             /dev/disk/by-id/google-home-part1                                                                                       ext4       rw,nosuid,nodev,noatime,journal_checksum,errors=remount-ro,data=ordered
├─/lib/modules                        /dev/dm-0[/lib/modules]                                                                                                 ext2       ro,relatime
├─/etc/hosts                          /dev/sda1[/var/lib/kubelet/pods/7fccb20b4bbb99e737878eab4bb685c1/etc-hosts]                                             ext4       rw,nosuid,nodev,noexec,relatime,commit=30
├─/etc/hostname                       /dev/sda1[/var/lib/docker/containers/3478f3eff5feb40315f1f59b0461286336e522a1763122e80e4af251b5ce32c4/hostname]         ext4       rw,nosuid,nodev,relatime,commit=30
├─/etc/resolv.conf                    /dev/sda1[/var/lib/docker/containers/3478f3eff5feb40315f1f59b0461286336e522a1763122e80e4af251b5ce32c4/resolv.conf]      ext4       rw,nosuid,nodev,relatime,commit=30
├─/run/metrics                        /dev/sda1[/var/volumes/metrics]                                                                                         ext4       rw,nosuid,nodev,noexec,relatime,commit=30
├─/etc/ssh/keys                       /dev/sda1[/var/volumes/ssh-keys]                                                                                        ext4       rw,nosuid,nodev,noexec,relatime,commit=30
├─/var/lib/docker                     /dev/sda1[/var/lib/docker/volumes/f2d20d3c2b6ca933bddb9b4c24ddff780bcd2c17e63cb697393b05ec2d65df37/_data]               ext4       rw,nosuid,nodev,relatime,commit=30
├─/var/config/tmux                    /dev/sda1[/var/volumes/tmux]                                                                                            ext4       ro,relatime,commit=30
├─/run/google/devshell                /dev/sda1[/var/lib/kubelet/pods/7fccb20b4bbb99e737878eab4bb685c1/volumes/kubernetes.io~empty-dir/devshell-client-ports] ext4       rw,nosuid,nodev,noexec,relatime,commit=30
└─/google/host/var/run                tmpfs                                                                                                                   tmpfs      rw,nosuid,nodev,mode=755
  ├─/google/host/var/run/docker/netns/91e9ce235fd0
  │                                   nsfs[net:[4026532315]]                                                                                                  nsfs       rw
  ├─/google/host/var/run/docker/netns/2b7f58084e8c
  │                                   nsfs[net:[4026532379]]                                                                                                  nsfs       rw
  └─/google/host/var/run/docker/netns/a0fd65d743d2
                                      nsfs[net:[4026532253]]
```

```
root@cs-406612939017-default-default-pf99c:~# cat /proc/self/cgroup
12:memory:/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f
11:blkio:/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f
10:rdma:/
9:cpuset:/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f
8:perf_event:/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f
7:freezer:/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f
6:cpu,cpuacct:/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f
5:net_cls,net_prio:/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f
4:hugetlb:/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f
3:devices:/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f
2:pids:/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f
1:name=systemd:/kubepods/besteffort/pod7fccb20b4bbb99e737878eab4bb685c1/cbc5a5ce0e59be70efd95106d567442196c5a55e2e9656eb63dc412f93903f3f
0::/system.slice/containerd.service
```
