# Notes on Google Compute Platform (GCP)

## GKE

### Provisioning

* It took ~3 minutes to provision the 3-node basic cluster (I used the web client).

* I connected to it using the GCP browser built-in cloud shell:

```
gcloud container clusters get-credentials my-first-cluster-1 --zone us-central1-c --project predictive-fx-309900
```

### Kubernetes

* K8s is 1.19 by default.

```
ctalledo@cloudshell:~ (predictive-fx-309900)$ kubectl version
Client Version: version.Info{Major:"1", Minor:"20", GitVersion:"v1.20.5", GitCommit:"6b1d87acf3c8253c123756b9e61dac642678305f", GitTreeState:"clean", BuildDate:"2021-03-18T01:10:43Z", GoVersion:"go1.15.8", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"19+", GitVersion:"v1.19.8-gke.1600", GitCommit:"4f6f69fd81ca8cb6962a2f7e1ed9c7880834cf71", GitTreeState:"clean", BuildDate:"2021-03-08T19:22:13Z", GoVersion:"go1.15.8b5", Compiler:"gc", Platform:"linux/amd64"}
```

* There is a "rapid channel" option that carries K8s 1.20.4.

* The cluster can be upgraded, both the control plane and worker nodes.

  - Control plane took 2-3 minutes.

  - Worker nodes took 6 minutes (2 minutes per node).


### Remote access

* I installed the `gcloud` tool, as described here: https://cloud.google.com/sdk/docs/install

* I can then access the GKE cluster via a command such as:

```
cesar@focal:~/nestybox/sysbox-internal-dev-pods/experiments/gke$ gcloud container clusters get-credentials my-first-cluster-1 --zone us-central1-c --project predictive-fx-309900
Fetching cluster endpoint and auth data.
kubeconfig entry generated for my-first-cluster-1.

cesar@focal:~/nestybox/sysbox-internal-dev-pods/experiments/gke$ kubectl get all
NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.108.0.1   <none>        443/TCP   21h
```

* To set the cluster:

```
cesar@focal:~/nestybox/sysbox-internal-dev-pods/experiments/gke$ export CLOUDSDK_CONTAINER_CLUSTER=my-first-cluster-1
```

* To view the node pools in the cluster:

```
cesar@focal:~/nestybox/sysbox-internal-dev-pods/experiments/gke$ gcloud container node-pools list
NAME          MACHINE_TYPE  DISK_SIZE_GB  NODE_VERSION
default-pool  g1-small      32            1.20.4-gke.2200
pool-1        e2-medium     32            1.20.4-gke.2200
```


### Nodes

* Nodes are allocated from node pools.

* Each node pool contains 1 or more nodes of the same type.

#### Node Types

* GKE nodes come in several flavors:

  - Container Optimized OS (with Docker or containerd)

  - Ubuntu (with Docker or containerd)

  - Windows

* I used the container optimized OS first:

```
ctalledo@cloudshell:~ (predictive-fx-309900)$ kubectl get nodes -o wide
NAME                                                STATUS   ROLES    AGE   VERSION            INTERNAL-IP   EXTERNAL-IP      OS-IMAGE                             KERNEL-VERSION   CONTAINER-RUNTIME
gke-my-first-cluster-1-default-pool-381d0f5c-gb4q   Ready    <none>   13m   v1.19.8-gke.1600   10.128.0.2    35.192.79.45     Container-Optimized OS from Google   5.4.89+          docker://19.3.14
gke-my-first-cluster-1-default-pool-381d0f5c-gnl7   Ready    <none>   13m   v1.19.8-gke.1600   10.128.0.4    34.70.253.114    Container-Optimized OS from Google   5.4.89+          docker://19.3.14
gke-my-first-cluster-1-default-pool-381d0f5c-h25j   Ready    <none>   13m   v1.19.8-gke.1600   10.128.0.3    34.123.196.187   Container-Optimized OS from Google   5.4.89+          docker://19.3.14
```

* These carry a GKE specific distro with a 5.4 kernel, so Sysbox won't work well in them (did not try it though):

```
  nodeInfo:
    architecture: amd64
    bootID: 357ff8f6-b56c-4d2b-9f5e-a7260a6b8cf6
    containerRuntimeVersion: docker://19.3.14
    kernelVersion: 5.4.89+
    kubeProxyVersion: v1.19.8-gke.1600
    kubeletVersion: v1.19.8-gke.1600
    machineID: d0b199c102e0dac957d294f47cd52705
    operatingSystem: linux
    osImage: Container-Optimized OS from Google
    systemUUID: d0b199c1-02e0-dac9-57d2-94f47cd52705
```

* Instead, I tried the ubuntu-based nodes:

```
Machine ID: 7df14aa9d7b9e9cb1ab7fa386ba9659d
System UUID: 7df14aa9-d7b9-e9cb-1ab7-fa386ba9659d
Boot ID: 57cfc98d-8c05-4ff3-a30c-9eac077d462f
Kernel version: 5.4.0-1033-gke
OS image: Ubuntu 18.04.5 LTS
Container runtime version: containerd://1.4.1
kubelet version: v1.20.4-gke.2200
kube-proxy version: v1.20.4-gke.2200
```
* These carry Ubuntu Bionic 18.04 with a 5.4 kernel, so they should be fine.

#### Node access

* By default, each node has an internal and external IP address.

* To ssh into it, I added my dev machine's public ssh key to the
  node's `.ssh/authorized-keys` file.

* I then ssh'd into it using the external IP address.

* I had to change the password for user `ctalledo`.

  - From within the web shell client:

```
$ sudo -i
$ passwd delete ctalledo
```

  - and then as user ctalledo:

```
$ passwd
Enter a new UNIX password: ...
```

#### Installing Sysbox on a Node

* I chose the "ubuntu + docker" gke image, and proceeded to install sysbox in it.

* Problem #1: jq not installed in host; fixed with `apt-get update && apt-get install jq`

* Problem #2: Docker is running containers/pods on the node, so sysbox installer failed:

```
Sysbox installer found existing docker containers. Please remove them as indicated below. Refer to Sysbox installation documentation for details.
        "docker rm $(docker ps -a -q) -f"
```

* Problem #3: When I tried to install in a host without Docker, the Sysbox installer still assumed Docker was present:

```
Configuring sysbox-ee
---------------------

Your OS does not include the 'shiftfs' module. As a result, using Sysbox requires that you put Docker in 'userns-remap' mode. If you answer "yes" here, the installer will take care of this configuration process. Otherwise, you will be expected to do this manually. Please refer to Sysbox installation documentation
for more details.

Configure Docker service in 'userns-remap' mode? [yes/no]
```

* Workaround:

  - Use kubectl to delete the node (`kubectl delete node <node-name>`)

  - Stop kubelet on the node (`systemctl stop kubelet`)

  - Remove all docker containers (`docker stop -t0 $(docker ps -aq) && docker rm $(docker ps -aq)`)

* When installing Sysbox, I hit this other error:

```
Apr 07 00:23:07 gke-my-first-cluster-1-pool-1-90e66ff8-dmmk dockerd[135412]: unable to configure the Docker daemon with file /etc/docker/daemon.json: the following directives are specified both as a flag and in the configuration file: bip: (from flag: 169.254.123.1/24, from file: 172.20.0.1/16)
```

* I also experienced a disconnect from the GKE node, and noticed that GKE was "auto-repairing" it:

```
(from the GKE web console):

my-first-cluster-1
Auto-repairing nodes in the node pool.
The values shown below will be updated once the operation finishes.
```

* When the auto-repair finished, I lost access to the node (the ssh authorized
  keys was reset). Seems like the VM associated with the node was destroyed and
  then re-created.

  - The reason the config was lost is because it was not applied via a daemon
    set (see next section).

* Thus, we first need to temporarily the auto-repair feature on the node.

* I tried it, but apparently it's not possible when using the "rapid" release channel:

```
cesar@focal:~/nestybox/sysbox-internal-dev-pods/experiments/gke$ gcloud container node-pools update pool-1 --cluster my-first-cluster-1 --zone us-central1-c --no-enable-autorepair
ERROR: (gcloud.container.node-pools.update) ResponseError: code=400, message=Auto_repair cannot be false when release_channel RAPID is set.
```

Next steps:

* Create a node with k8s + containerd only (no docker) [DONE]

* Install docker manually (optional)

* Install crio manually [DONE - see https://cri-o.io/]

* Install sysbox manually

* Verify docker + sysbox works (to verify kernel is good) (optional)

* Verify crictl + crio + sysbox works (to verify kernel is good)

* Configure kubelet to use crio

* K8s + crio + sysbox works


#### Node Configuration

* GKE->clusters->node->node-pools->instance groups

  - This takes you to GCE window where there is an option to SSH into the node.

* WARNING regarding node configs (per https://cloud.google.com/kubernetes-engine/docs/concepts/node-images):

"Modifications on the boot disk of a node VM do not persist across node
re-creations. Nodes are re-created during manual upgrade, auto-upgrade,
auto-repair, and auto-scaling. In addition, nodes are re-created when you enable
a feature that requires node re-creation, such as GKE sandbox, intranode
visibility, and shielded nodes."

"To preserve modifications across node re-creation, use a DaemonSet."


* I upgraded the node manually:

  - Note: upgrading the via the LTS package did not work as intented (the kernel stayed at 5.4):

  `sudo apt-get update && sudo apt install --install-recommends linux-generic-hwe-18.04 -y`

  - Thus, I did a distro upgrade as follows:

  ```
  sudo apt-get update
  sudo apt-get upgrade -y
  sudo do-release-upgrade
  ```

  - The last command asked way to many confirmation questions

    - TODO: pass a flag that avoid this.

  - In the end it DID NOT work as expected, we got a ubuntu-focal but with a 5.4 kernel still:

```
ctalledo@gke-my-first-cluster-1-pool-1-ef917cbb-5nsl:~$ uname -a
Linux gke-my-first-cluster-1-pool-1-ef917cbb-5nsl 5.4.0-1039-gke #41-Ubuntu SMP Fri Mar 19 17:59:28 UTC 2021 x86_64 x86_64 x86_64 GNU/Linux
ctalledo@gke-my-first-cluster-1-pool-1-ef917cbb-5nsl:~$ lsb_release -a
No LSB modules are available.
Distributor ID: Ubuntu
Description:    Ubuntu 20.04.2 LTS
Release:        20.04
Codename:       focal
```


#### Creating a GCE node and joining it to the cluster

* I created a ubuntu-focal node on GCE, but it's still a 5.4 kernel:

```
ctalledo@ubuntu-focal-1:~$ uname -a
Linux ubuntu-focal-1 5.4.0-1040-gcp #43-Ubuntu SMP Fri Mar 19 17:49:48 UTC 2021 x86_64 x86_64 x86_64 GNU/Linux

ctalledo@ubuntu-focal-1:~$ lsb_release -a
No LSB modules are available.
Distributor ID: Ubuntu
Description:    Ubuntu 20.04.2 LTS
Release:        20.04
Codename:       focal
```

* However, the ubuntu-groovy images on GCE have a 5.8 kernel!

```
ctalledo@ubuntu-groovy-1:~$ uname -a
Linux ubuntu-groovy-1 5.8.0-1026-gcp #27-Ubuntu SMP Sat Mar 20 03:55:48 UTC 2021 x86_64 x86_64 x86_64 GNU/Linux

ctalledo@ubuntu-groovy-1:~$ lsb_release -a
No LSB modules are available.
Distributor ID: Ubuntu
Description:    Ubuntu 20.10
Release:        20.10
Codename:       groovy
```



TODO:

* Is it possible to upgrade the kernel on the nodes?

  - It's possible to upgrade the distro, but the kernel remained at 5.4 unfortunately.

* Is it possible to create a GCE node with ubuntu-groovy and join it to the cluster?

  - Did not find a way to do this.

* Is there a way to do this with a K8s daemon set?

  - Unlikely; it's possible to install sysbox with the daemon set, but upgrading the kernel on the k8s node seems a bit too much.

* Should we use a GCE VM with a custom image

  https://cloud.google.com/compute/docs/images?_ga=2.3401203.-276768672.1617668269

  - No, because we can't join it to the GKE cluster.







### TODO

  - Is the ubuntu kernel 5.X+

  - Is shiftfs present in the ubuntu kernel? Can it be loaded?

  - What distro is the container optimized OS? Does Sysbox work in there?




## Cloud Shell

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


## References

* Installing CRI-O and configuring K8s to use it: https://medium.com/cloudlego/using-cri-o-as-container-runtime-for-kubernetes-b8ddf8326d38
