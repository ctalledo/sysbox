# Experiment: K8s Pods with Sysbox (aka Sysbox Pods)

## K8s Node Setup

### Background

* The kubelet can only connect to a single CRI implementation at a given time.

  - I.e., one CRI implementation per K8s node

* There are 3 popular implementations:

  - Dockershim (invokes Docker); This was the default but has gone away (since K8s 1.20 I believe)

  - Containerd CRI (invokes containerd); this is the new default.

  - CRI-O (invokes crio, which is a light-weight alternative to containerd); created and backed by RedHat.

* Each of these can then connect to one or more low-level "runtimes" (runc, sysbox-runc, kata, etc.)

* Dockershim and containerd don't yet support creating pods with the Linux
  userns. Thus they won't work with Sysbox initially.

* CRI-O has experimental support for userns (added in July 2020).

  - I.e., on pod sandbox creation, the CRI can create the userns prior to other namespaces.

  - This is exactly what's needed for K8s to integrate with Sysbox.


### Host Config Steps

NOTE:

* These are now documented in https://github.com/nestybox/sysbox-internal/issues/839.

* We will also offer a "sysbox-deploy" daemonset to easily install sysbox on k8s
  host.

* We will also offer docs for installing sysbox manually:

  - On a self-hosted K8s cluster

  - On a GKE cluster

* The notes below provide further details..


### Manual Config Steps for a Self-Hosted K8s Cluster

1) Install and configure CRI-O on the K8s node

  - See section [CRI-O Config](#cri--o-config)

2) Configure K8s to use CRI-O

3) Install Sysbox on the node

4) Configure K8s to learn about Sysbox

5) Configure K8s pod to use Sysbox


#### 1) Install & Configure CRI-O

* Need CRI-O 1.20.

  - It's the first CRI-O release to bring in user-ns support.

  - CRI-O 1.21 breaks userns ID-mapping, so don't use it for now.

* In addition, CRI-O must be configured with:

  - cgroup management set to cgroupfs (not systemd).

    - Alternatively K8s could be configured with systemd cgroups; by default K8s it uses cgroupfs.

    - Sysbox supports either systemd or cgroupfs.

  - Sysbox-runc as one of the runtimes with userns "annotations" enabled.

  - Storage = overlayfs, with "nodev" removed and "metacopy=on" set.

  - User "containers" must be present in the `/etc/sub[ug]id` files.


* E.g., : sample CRI-O config in `/etc/crio/crio.conf`:

```
# Storage config
storage_driver = "overlay"
storage_option = ["overlay.mountopt=metacopy=on"]

# Cgroup setting for conmon
#conmon_cgroup = "system.slice"
conmon_cgroup = "pod"

# Cgroup management implementation used for the runtime.
#cgroup_manager = "systemd"
cgroup_manager = "cgroupfs"

[crio.runtime.runtimes.sysbox-runc]
runtime_path = "/usr/local/sbin/sysbox-runc"
runtime_type = "oci"
allowed_annotations = ["io.kubernetes.cri-o.userns-mode"]
```

* And this is the subid config (CRI-O will pick the container uids from the
  range for user "containers").

```
$ cat /etc/subuid
containers:165536:268435456
sysbox:268600992:268435456
```

* Then restart CRI-O:

```
systemctl restart crio
```


#### Configure K8s to use CRI-O

* NOTE: need k8s 1.20 since CRI-O is 1.20 (versions *must* match).

* Install kubeadm on all nodes

```
sudo curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
sudo apt-get install -y kubelet=1.20.2-00 kubeadm=1.20.2-00 kubectl=1.20.2-00
```

* Init K8s master with kubeadm

```
sudo swapoff -a
sudo kubeadm init --kubernetes-version=v1.20.2 --pod-network-cidr=10.244.0.0/16
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

* For the K8s worker nodes where sysbox will be installed, use CRI-O:

```
sudo swapoff -a
sudo kubeadm join --cri-socket="/var/run/crio/crio.sock" <join-token>"
```

* To clear the worker node's config:

```
sudo kubeadm reset --cri-socket="/var/run/crio/crio.sock"
```

* Kubelet config is here:

```
/etc/kubernetes/kubelet.conf
/var/lib/kubelet/config.yaml
```

* Without kubeadm, this configuration is done via the kubelet's cmd line:

  - Via the `--container-runtime-endpoint` and `--image-service-endpoint` options.

  ```
  kubelet.service
             │ └─1618514 /usr/bin/kubelet --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --config=/var/lib/kubelet/config.yaml --container-runtime=remote --container-runtime-endpoint=/var/run/crio/crio.sock
  ```

* Kubelet systemd service:

```
/lib/systemd/system/kubelet.service
systemd/system/kubelet.service.d/10-kubeadm.conf
```

* When using crio, the kubelet systemd service should have this config:

```
# cat /etc/systemd/system/kubelet.service
Environment="KUBELET_RUNTIME_ARGS=--container-runtime=remote --container-runtime-endpoint=/var/run/crio/crio.sock"
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_RUNTIME_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
Wants=crio.service
```

* More on kubelet config:

  https://github.com/kubernetes/kubernetes/blob/master/staging/src/k8s.io/kubelet/config/v1beta1/types.go

  NOTE: you can't yet configure the CRI via the kubelet config file.


#### Configure K8s to learn about the Sysbox runtime

* This is done via a k8s `RuntimeClass` object:

```
apiVersion: node.k8s.io/v1beta1
kind: RuntimeClass
metadata:
  name: sysbox-runc
  handler: sysbox-runc
scheduling:
  nodeSelector:
    sysbox-runtime: running
```

* Here we assume that nodes where Sysbox is running are labeled with
  "sysbox-runtime=running".


#### Configure Pods to use Sysbox

* Do this by adding a runtimeClass *and* userns annotation to the pod.

  - The runtimeClass causes K8s to command CRI-O to use sysbox.

  - The userns annotation causes k8s to command CRI-O to use userns for the pods.

* For example:

```
apiVersion: v1
kind: Pod
metadata:
  name: alpine-docker
  annotations:
    io.kubernetes.cri-o.userns-mode: "auto:size=65536"
spec:
  runtimeClassName: sysbox-runc
  containers:
  - name: alpine-docker
    image: nestybox/alpine-docker
    command: ["tail"]
    args: ["-f", "/dev/null"]
  restartPolicy: Never
```

* NOTE: don't set `shareProcessNamespace: true` in the pod spec when
  running pods with systemd (otherwise the pod's pause container
  will be pid 1 inside the pod, and systemd won't work properly).

#### Optional: allow sched on master node (for single node clusters)

```
kubectl taint node k8s-node node-role.kubernetes.io/master:NoSchedule-
```


## CRI-O Config Notes

* CRI-O brings experimental support for pods with user-ns.

  - This is a must-have to launch pods with sysbox.

* Need CRI-O 1.20.

  - It's the first CRI-O release to bring in user-ns support.

  - CRI-O 1.21 breaks userns ID-mapping, so don't use it for now.

* CRI-O: install from packaged version:

  https://cri-o.io/
  https://kubernetes.io/docs/setup/production-environment/container-runtimes/
  https://github.com/cri-o/cri-o/blob/master/tutorials/kubernetes.md

  NOTE: The CRI-O major and minor versions must match the Kubernetes major and minor versions.

* CRI-O: install from source (for CRI-O with experimental userns support):

  - Commit that brings in userns support: `commit ad2ed3b79251ffa2f60f28ba4a975b24abc9d311`  (07/09/2020)

  - That commit has a good description of how to use it.

  - Had to use this and build CRI-O from scratch: https://github.com/cri-o/cri-o/blob/master/install.md#build-and-install-cri-o-from-source

  - When I did `make install`, I get this error:

  `ERRO[0000] The storage 'driver' option must be set in /etc/containers/storage.conf, guarantee proper operation.`

    - Fixed it by adding `driver = "overlay"` to /etc/containers/storage.conf  (see man 5 containers-storage.conf)

* Config file: `/etc/crio/crio.conf` or `/etc/crio/crio.conf.d/00-sysbox.conf`

```
allow_userns_annotation = true   <<< older CRI-O versions only; not needed in newer CRI-O versions.

[crio.runtime.runtimes.sysbox-runc]
runtime_path = "/usr/local/sbin/sysbox-runc"
runtime_type = "oci"
allowed_annotations = ["io.kubernetes.cri-o.userns-mode"]
```

  See:
  https://github.com/cri-o/cri-o/blob/master/docs/CRI-O.conf.5.md
  https://github.com/cri-o/cri-o/blob/master/docs/CRI-O.conf.d.5.md
  https://docs.openshift.com/container-platform/3.11/CRI-O/CRI-O_runtime.html

* Start CRI-O after installation: `systemctl start crio.service`.

* cri-o cmd line: https://github.com/cri-o/cri-o/blob/master/docs/CRI-O.8.md

* crictl + cri-o tutorial: https://github.com/cri-o/cri-o/blob/master/tutorials/crictl.md

```
# cat /etc/crictl.yaml
runtime-endpoint: unix:///var/run/crio/crio.sock
```

* Data store: `/var/lib/containers/`

  - Container config.json is at `/var/lib/containers/storage/overlay-containers/<container-id>/userdata`.

  - Container rootfs is at `/var/lib/containers/storage/overlay`

* Run dir:

  `/var/run/containers/`

  `/var/run/<nstype>/<file>`

  - Where `file` is a bind-mount to a linux namespace created by CRI-O:

```
│ ├─/run/userns/709e1fe2-ca15-417a-a373-b1b2c9f78f27                                                                         nsfs[user:[4026532380]]                        nsfs       rw
│ ├─/run/utsns/709e1fe2-ca15-417a-a373-b1b2c9f78f27                                                                          nsfs[uts:[4026532381]]                         nsfs       rw
│ ├─/run/ipcns/709e1fe2-ca15-417a-a373-b1b2c9f78f27                                                                          nsfs[ipc:[4026532382]]                         nsfs       rw
│ └─/run/netns/709e1fe2-ca15-417a-a373-b1b2c9f78f27                                                                          nsfs[net:[4026532384]]                         nsfs       rw
```

  - This way, the ns created by CRI-O and kept alive, even if no processes exist within it.

* CRI-O creates several namespaces for the pods prior to creating the containers within it.

  - The namespaces are kept alive even if no processes exist within them by
    bind-mounts previously described.

  - The id mappings for the userns are setup a-priori.

* Userns subuid range config:

  ```
  cat /etc/subuid
  containers:296608:655360
  ```

* CRI-O-status tool: https://github.com/cri-o/cri-o/blob/master/docs/CRI-O-status.8.md

* If you get this error, then remove the ipv6 configs in the CNI (`/etc/cni/net.d`):

`FATA[0002] run pod sandbox: rpc error: code = Unknown desc = failed to create pod network sandbox k8s_nginx-sandbox_default_myfirstpod_1(cc35d42f62131338ac45d8ba16814159f9077bae9225a5d714b338daa891edf7): failed to set bridge addr: could not add IP address to "cni0": permission denied `

  (or alternatively enable ipv6 in the machine via sysctl (`/proc/sys/net/ipv6/conf/all/disable_ipv6`))

* CRI-O status:

```
sudo CRI-O-status config
```



## Containerd + Sysbox Config

* NOTE: Containerd does not yet support pods with user-ns yet.

* If and when it does, we would configure it as follows.

  - In the containerd config file: `/etc/containerd/config.toml`.

    - Comment "disabled_plugins = ["cri"]" line

    - Set `version = 2`

    - Configure the containerd CRI plugin to know about sysbox-runc:

```
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.sysbox-runc]
    runtime_type = "io.containerd.runtime.v1.linux"
    runtime_engine = "/usr/bin/sysbox-runc"
```

* Then restart containerd:

```
sudo systemctl restart containerd
```


## Crictl setup

* crictl is a low-level tool to talk to the CRI implementations directly (e.g.,
  CRI-O, containerd).

* See:

  https://github.com/kubernetes-sigs/cri-tools/blob/master/docs/crictl.md
  https://kubernetes.io/docs/tasks/debug-application-cluster/crictl/
  https://github.com/kubernetes-sigs/cri-tools

* crictl config example:

```
$ cat /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
```

* For CRI-O use: `unix:///var/run/crio/crio.sock`

* You can talk to CRI-O via critcl or directly via it's HTTP API:

```
sudo curl -v --unix-socket /var/run/crio/crio.sock http://localhost/info | jq
```

```
$ sudo crictl runp --runtime=sysbox-runc pod-config.json
$ sudo crictl pods
$ sudo crictl inspectp <pod-id>
$ sudo crictl --config=/etc/crictl.yaml --debug --runtime=sysbox-runc

$ sudo crictl stopp <pod-id>
$ sudo crictl rmp <pod-id>
```

* Images

```
$ sudo crictl images
$ sudo crictl pull busybox
```

* Containers

```
$ sudo crictl create <pod-id> <container-spec> <pod-spec>
$ sudo crictl ps -a
$ sudo crictl start <container-id>
$ sudo crictl exec -i -t <container-id> ls
```

* This command creates a pod and the container in one shot:

```
$ sudo crictl run --runtime=sysbox-runc container-config.json pod-config.json
```

* To exec into the pod:

```
sudo crictl exec -i -t 4907f5c792a28 /bin/sh
```

* NOTE: when k8s is running on the host, do not launch independent pods with
  crictl, as k8s will detect them and prevent them from working correctly.

* Pod spec example:

```
{
    "metadata": {
        "name": "ubu-bionic-systemd-docker-sandbox",
        "namespace": "default",
        "attempt": 1,
        "uid": "sysbox-pod"
    },
    "annotations": {
        "io.kubernetes.cri-o.userns-mode": "auto:size=65536"
    },
    "log_directory": "/tmp",
    "linux": {
        "security_context": {
            "namespace_options": {
                "pid": 1                    <<< Don't share pid ns; found it in the CRI-O repo, via "grep -A 5 -R --exclude-dir=vendor "namespace_options" *"
            },
           "run_as_user":{
               "value": 296608
           }
        }
    }
}
```

* Container spec example:

```
{
  "metadata": {
      "name": "ubu-bionic-systemd-docker"
  },
  "image":{
      "image": "nestybox/ubuntu-bionic-systemd-docker"
  },
  "command": [
      "/sbin/init"
  ],
  "log_path":"container.log",
   "linux": {
       "security_context": {
           "namespace_options": {
               "pid": 1
           }
       }
   }
}
```

* Crictl errors & solutions:

Error: not enough available IDs:

```
FATA[0001] running container: run pod sandbox: rpc error: code = Unknown desc = error creating pod sandbox with name "k8s_alpine-sandbox_default_sysbox-pod_1": could not find enough available IDs
```

Solution: add user "containers" to `/etc/subuid` and `/etc/subgid`.


Error:

```
No CNI configuration file in /etc/cni/net.d/.
```

Solution: add CNI




## Issues

The following are issues we found while experimenting with Sysbox pods.


### Issue: pod with k8s + containerd + sysbox fails  [SOLVED]

* NOTE: Tracked by sysbox issue #67.

* Launching a pod with K8s + containerd + sysbox causes an EPERM error when
  sysbox-runc is preparing the container's rootfs (specifically mounting sysfs
  into the container):

```
Oct 29 17:00:03 k8s-node kubelet[39866]: E1029 17:00:03.640898   39866 remote_runtime.go:113] RunPodSandbox from runtime service failed: rpc error: code = Unknown desc = failed to create containerd task:
OCI runtime create failed: container_linux.go:364: starting container process caused "process_linux.go:533: container init caused \"rootfs_linux.go:62: setting up rootfs mounts caused \\\"rootfs_linux.go:932:
mounting \\\\\\\"sysfs\\\\\\\" to rootfs \\\\\\\"/run/containerd/io.containerd.runtime.v1.linux/k8s.io/eaba8255cb94e106d94e8fd8f8249200652b2275407464b8bc70e376b6c1a2aa/rootfs\\\\\\\" at \\\\\\\"sys\\\\\\\" caused \\\\\\\"operation not permitted\\\\\\\"\\\"\"": unknown
```

* Problem is tracked by sysbox issue: https://github.com/nestybox/sysbox/issues/67

* Was able to repro the problem directly with crictl:

```
sudo crictl runp --runtime=sysbox-runc pod-config.json
FATA[0000] run pod sandbox failed: rpc error: code = Unknown desc = failed to create containerd task: OCI runtime create failed: container_linux.go:364: starting container process caused "process_linux.go:533: container init caused \"rootfs_linux.go:62: setting up rootfs mounts caused \\\"rootfs_linux.go:938: mounting \\\\\\\"sysfs\\\\\\\" to rootfs \\\\\\\"/run/containerd/io.containerd.runtime.v1.linux/k8s.io/a524c97b5cee9c2c999080f3ce899c9926fb2b138c95c3c43528604c18949d6a/rootfs\\\\\\\" at \\\\\\\"sys\\\\\\\" caused \\\\\\\"base mount failed: sysfs sys sysfs 14 : operation not permitted\\\\\\\"\\\"\"": unknown
```

* The problem is related to entering the netns before entering the userns:

```
$ sudo unshare -n bash
$ unshare -U -m -i -p -u -C -f -r --mount-proc bash
$ mount -t sysfs sysfs sys
mount: /home/cesar/shiftfs-exp/rootfs/sys: permission denied
$ unshare -n bash
$ mount -t sysfs sysfs sys
(no problem)
```

* Thus, we need a solution a CRI implementation that supports userns (which must
  be created **before** other the other namespaces of the container).

* Solution: use CRI-O 1.20, as it adds support for userns pods.

  - CRI-O will setup the user-ns for the pod before creating the containers that
    will live within that user-ns.

  - Make sure that sysbox-runc is added as a runtime in `/etc/CRI-O/CRI-O.conf`:

```toml
[crio.runtime.runtimes.sysbox-runc]
runtime_path = "/usr/local/sbin/sysbox-runc"
runtime_type = "oci"
allowed_annotations = ["io.kubernetes.cri-o.userns-mode"]
```

  - Note: using CRI-O 1.20 will force use of K8s 1.20 too.


### Issue: Sysbox lacked systemd cgroup support [SOLVED]

* Tracked by sybox issue #165.

* Creating a pod with crictl + CRI-O + sysbox fails with a systemd cgroup related error:

```
$ sudo crictl runp --runtime=sysbox-runc pod-config.json
FATA[0002] run pod sandbox failed: rpc error: code = Unknown desc = container create failed: time="2020-10-31T04:02:30Z" level=error msg="flag provided but not defined: -systemd-cgroup"
flag provided but not defined: -systemd-cgroup
```

* The problem was that sysbox-runc did not support the `--systemd-cgroup` option (the OCI runc does).

* This problem occurs because crictl uses the systemd cgroup manager by default.

* Solution: this has been fixed in sysbox-runc top-of-tree by virtue of sync'in
  it with the latest OCI runc and adding systemd cgroup v1 support.

  * FYI: after fix, when using crictl to create pods, the pods's cgroup
    hierarchy is placed in the following host dir:

    `/sys/fs/cgroup/memory/system.slice/runc-8494764d1a15ac2d3f33beb5cb343208ec5099ede6264136a2c3b0ae9406501f.scope`

* Workaround: configure CRI-O with the cgroupfs cgroup manager (rather than systemd):

```
# Cgroup management implementation used for the runtime.
#cgroup_manager = "systemd"
cgroup_manager = "cgroupfs"

Cgroup setting for conmon
#conmon_cgroup = "system.slice"
conmon_cgroup = "pod"
```

* K8s by default sets up kubelet to use the `cgroupfs` driver (which means
  that CRI-O must be configured with this driver too).

* But it's possible to reproduce this problem with k8s too, by configuring the
  kubelet with the `cgroupDriver` set to `systemd` (by default it's set to
  `cgroupfs`).

  - For example, if using kubeadm, using this config file:

```
root@k8s-node:~# more kubeadm-config.yaml

apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: v1.19.3
clusterName: kubernetes
certificatesDir: /etc/kubernetes/pki
apiServer:
extraArgs:
authorization-mode: Node,RBAC
timeoutForControlPlane: 4m0s
dns:
type: CoreDNS
etcd:
local:
dataDir: /var/lib/etcd
imageRepository: k8s.gcr.io
networking:
dnsDomain: cluster.local
podSubnet: 10.244.0.0/16
serviceSubnet: 10.96.0.0/12
scheduler: {}
controllerManager: {}
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
```

  - and then start kubeadm with:

```
$ sudo kubeadm init --config=/root/kubeadm-config.yaml
```


### Issue: pod creation results in sysbox-runc nsenter `update_score_adj` error [SOLVED - sysbox-pod branch]

* Tracked by sysbox-internal issue #835.


```
$ sudo crictl runp --runtime=sysbox-runc pod-config2.json

$ sudo crictl create b87cd144afd25 container-config2.json pod-config2.json

FATA[0006] creating container: rpc error: code = Unknown desc = container create failed: time="2021-02-27T22:28:24Z" level=fatal msg="update_oom_score_adj:355 nsenter: failed to update /proc/self/oom_score_adj: Permission denied"
time="2021-02-27T22:28:24Z" level=fatal msg="nsexec:895 nsenter: failed to sync with child: next state: Connection reset by peer"
time="2021-02-27T22:28:24Z" level=warning msg="cgroup: subsystem does not exist"
time="2021-02-27T22:28:24Z" level=warning msg="cgroup: subsystem does not exist"
time="2021-02-27T22:28:24Z" level=warning msg="cgroup: subsystem does not exist"
time="2021-02-27T22:28:24Z" level=error msg="container_linux.go:392: starting container process caused: process_linux.go:408: getting pipe fds for pid 77150 caused: readlink /proc/77150/fd/0: no such file or directory"
```

* Failure occurs in nsenter, when writing to `oom_adjust_score`.

* Failure occurs for the work container that is part of the pod; it does **not**
  occur for the initial `pause` container inside the pod.

* Problem is related to sysbox setting the `oom_score_adj`: it can't be
  set to -1000 within a user-ns. This was happening implicitly when deploying pods
  with crictl as it was not setting an explicit value for `oom_score_adj`, and
  as a result sysbox-runc was using it's value with is -1000.

  - It's easy to repro the problem with `docker run --runtime=sysbox-runc --oom-score-adj=-1000 ...`.


### Issue: sysbox-fs enforces "one container per userns", preventing pods from working correctly [SOLVED - sysbox-pod branch]

* Tracked by sysbox-internal issue #836.

* Sysbox-fs bug:

```
cesar@k8s-node:~/nestybox/experiments/sysbox-pods/crictl/test-sysbox-pod$ sudo crictl create 4942d1b8a8732 container-config.json pod-config2.json
FATA[0002] Creating container failed: rpc error: code = Unknown desc = container create failed: container_linux.go:364: starting container process caused "process_linux.go:404:
registering with sysbox-fs caused \"failed to register with sysbox-fs: failed to register container with sysbox-fs: rpc error: code = AlreadyExists desc =
Container 61a1e2967a5eb8cfbb1d8070ec4e2fdd1917dac51093a976ce3185c06052e402 with userns inode already present\""
```

* sysbox-fs is confused: it's enforcing a "one container per userns". Pods break this assumption.

* Work-around: comment out the enforcement code.

* Problem also occurs when pod is deleted:

```
INFO[2020-11-04 05:13:56] Container unregistration message received for id: 438c45a4f824b2c946863bcc3aa3f9c24e7baab3fd4481ccf996e84c1a1a236b
ERRO[2020-11-04 05:13:56] Container unregistration error: could not find userns-inode 4026532597 for container 438c45a4f824b2c946863bcc3aa3f9c24e7baab3fd4481ccf996e84c1a1a236b
```

### Issue: runc and sysbox-runc missing support for seccomp ERRNO return action [SOLVED]

* NOTE: this has been fixed in sysbox-runc top-of-tree by virtue of sync'in it with the latest OCI runc on 12/2020.

* Found this error when using K8s 1.19.3 with CRI-O top-of-tree: the coredns pods
  launched by kubeadm failed to start:

```
  Warning  FailedCreatePodSandBox  119s  kubelet  Failed to create pod sandbox: rpc error: code = Unknown desc = container create failed:
    time="2020-11-02T22:12:39Z" level=error msg="container_linux.go:349: starting container process caused \"error adding seccomp rule for syscall socket: requested action matches defa
  ult action of filter\""
```

* The error is due to a bug in the OCI runc: https://github.com/containers/podman/issues/6506

  - runc was missing support for the seccomp ERRNO return action.

* The top-of-tree OCI runc has the fix: https://github.com/opencontainers/runc/pull/2424


### Issue: Deploying a K8s pod with a systemd-based container fails. [SOLVED - sysbox-pod branch]

* Tracked by sysbox-internal issue #837.

* I can see that systemd is launched as pid 1 inside the pod, but it did not
  start any services.

* NOTE: for such pods, ensure each container in the pod is in a dedicated pid
  ns. Otherwise the pause container will be pid 1, causing trouble since systemd
  wants to be pid 1.

  - This is the default in k8s, but it's not the default when using crictl to
    deploy pods for example.

  - Guidance: don't set `shareProcessNamespace: true` in the pod spec.

* The problem is caused by the following:

  - When deploying a pod with k8s + CRI-O, CRI-O sets up the container spec to
    mount the host's `/sys/fs/cgroup/systemd` inside the container:

```
{
    "destination": "/sys/fs/cgroup/systemd",
    "type": "bind",
    "source": "/sys/fs/cgroup/systemd",
    "options": [
        "bind",
        "nodev",
        "noexec",
        "nosuid"
    ]
},
```

  - Inside the container, the mount looks like this:

```
TARGET                                                       SOURCE                                                                                                                              FSTYPE   OPTIONS
/                                                            overlay                                                                                                                             overlay  rw,relatime,lowerdir=/var/lib/containers/storage/overlay/l/BUZFOZUWHP3U3Y6G4SQXNOYP27:/var/lib/containers/storage/ov
|-/sys                                                       sysfs                                                                                                                               sysfs    rw,nosuid,nodev,noexec,relatime
| |-/sys/firmware                                            tmpfs                                                                                                                               tmpfs    ro,relatime,uid=296608,gid=296608
| |-/sys/fs/cgroup                                           tmpfs                                                                                                                               tmpfs    ro,nosuid,nodev,noexec,mode=755,uid=296608,gid=296608
| | |-/sys/fs/cgroup/systemd                                 systemd                                                                                                                             cgroup   rw,nosuid,nodev,noexec,relatime,xattr,name=systemd
| | | `-/sys/fs/cgroup/systemd                               cgroup[/../../../../..]                                                                                                             cgroup   rw,nosuid,nodev,noexec,relatime,xattr,name=systemd
| | |   `-/sys/fs/cgroup/systemd/release_agent               udev[/null]                                                                                                                         devtmpfs rw,nosuid,noexec,relatime,size=4032536k,nr_inodes=1008134,mode=755
```

  - This is not good, as it allows the container to modify the systemd cgroup
    resources at host level.

  - Furthermore, it's causing systemd to fail to initialize since it finds
    itself without permissions to access that directory.

* Solution: sysbox-runc should ignore bind-mounts on `/sys/fs/cgroup/systemd`. In fact it should
  ignore bind mounts on any subdir of `/sys/fs/cgroup`.


### Issue: Deploying K8s-in-Pod (K8s-in-K8s) failed due to networking [SOLVED]

* Tracked by sysbox issue #840.

* The pod was created correctly and networking was fine before `kubeadm init` was executed in it.

  - ping worked, nslookup worked, apt-get update worked.

* `kubeadm init` worked well.

* But after `kubeadm init` finishes, the pod's DNS resolution stops working:

  - `apt-get update` fails, but `ping 8.8.8.8` passes.

* This turned out to be a networking problem, due to IP subnet collisions between
  the inner K8s and the outer K8s.

  - Basically, the inner K8s must use a different (virtual) IP for it's services.

  - Otherwise, DNS resolution won't work on the inner K8s, because the virtual
    IP for it's services will default to 10.96.*, but it's /etc/resolv.conf is
    also setup with 10.96.0.10 (i.e., the k8s DNS at host level). Thus DNS
    resolution breaks.

  - Also, the inner K8s pod network CIDR should also be different, though I've
    not yet confirmed if it must be different.

* Details below:

  - Networking inside the k8s pod:

```
root@k8s-master:/# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever

3: eth0@if294: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UP group default
    link/ether f6:e9:19:37:4a:73 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.244.0.35/24 brd 10.244.0.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::f4e9:19ff:fe37:4a73/64 scope link
       valid_lft forever preferred_lft forever

4: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default
    link/ether 02:42:ec:61:56:79 brd ff:ff:ff:ff:ff:ff
    inet 172.18.0.1/16 brd 172.18.255.255 scope global docker0
       valid_lft forever preferred_lft forever


// NOTE: The /etc/resolv.conf is setup such that the resolver is at 10.96.0.10, which is the virtual IP for the kube-dns service at host level.

root@k8s-master:/# more /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5


root@k8s-master:/# kubeadm init --kubernetes-version=v1.18.2 --pod-network-cidr=10.245.0.0/16
...

// NOTE: inner pod-cidr chosen to not conflict with host level pod-cidr
// NOTE: K8s services virtual cluster IP = 10.96.0.1 (same as on host)

[certs] apiserver serving cert is signed for DNS names [k8s-master kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local] and IPs [10.96.0.1 10.244.0.35]
[certs] etcd/server serving cert is signed for DNS names [k8s-master localhost] and IPs [10.244.0.35 127.0.0.1 ::1]
[certs] etcd/peer serving cert is signed for DNS names [k8s-master localhost] and IPs [10.244.0.35 127.0.0.1 ::1]
...


root@k8s-master:/# kubectl get all --all-namespaces
NAMESPACE     NAME                                     READY   STATUS    RESTARTS   AGE
kube-system   pod/coredns-66bff467f8-hbll4             0/1     Pending   0          106s
kube-system   pod/coredns-66bff467f8-nlmdl             0/1     Pending   0          106s
kube-system   pod/etcd-k8s-master                      1/1     Running   0          114s
kube-system   pod/kube-apiserver-k8s-master            1/1     Running   0          114s
kube-system   pod/kube-controller-manager-k8s-master   1/1     Running   0          114s
kube-system   pod/kube-proxy-vxcps                     1/1     Running   0          107s
kube-system   pod/kube-scheduler-k8s-master            1/1     Running   0          114s

NAMESPACE     NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
default       service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP                  2m4s
kube-system   service/kube-dns     ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   2m2s

NAMESPACE     NAME                        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kube-system   daemonset.apps/kube-proxy   1         1         1       1            1           kubernetes.io/os=linux   2m2s

NAMESPACE     NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
kube-system   deployment.apps/coredns   0/2     2            0           2m2s

NAMESPACE     NAME                                 DESIRED   CURRENT   READY   AGE
kube-system   replicaset.apps/coredns-66bff467f8   2         2         0       106s
```


  - Networking setup by K8s at host level:


```
cesar@k8s-node:~/nestybox/sysbox$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever

2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 52:54:00:fa:c2:16 brd ff:ff:ff:ff:ff:ff
    inet 192.168.121.55/24 brd 192.168.121.255 scope global dynamic eth0
       valid_lft 3437sec preferred_lft 3437sec
    inet6 fe80::5054:ff:fefa:c216/64 scope link
       valid_lft forever preferred_lft forever

3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default
    link/ether 02:42:c0:ff:46:24 brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
       valid_lft forever preferred_lft forever


cesar@k8s-node:~/nestybox/sysbox-internal/experiments/sysbox-pods/crictl/test-sysbox-pod$ sudo kubeadm init --cri-socket="/var/run/CRI-O/CRI-O.sock" --kubernetes-version=v1.19.3 --pod-network-cidr=10.244.0.0/16
...
[certs] apiserver serving cert is signed for DNS names [k8s-node kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local] and IPs [10.96.0.1 192.168.121.55]
[certs] etcd/server serving cert is signed for DNS names [k8s-node localhost] and IPs [192.168.121.55 127.0.0.1 ::1]
[certs] etcd/peer serving cert is signed for DNS names [k8s-node localhost] and IPs [192.168.121.55 127.0.0.1 ::1]
...


cesar@k8s-node: sudo kubeadm init --cri-socket="/var/run/CRI-O/CRI-O.sock" --kubernetes-version=v1.19.3 --pod-network-cidr=10.244.0.0/16

cesar@k8s-node:~/nestybox/sysbox$ kubectl get all --all-namespaces
NAMESPACE     NAME                                   READY   STATUS    RESTARTS   AGE
default       pod/k8s-master                         1/1     Running   0          7m12s
kube-system   pod/coredns-f9fd979d6-t5tk9            1/1     Running   0          12h
kube-system   pod/coredns-f9fd979d6-v58sq            1/1     Running   0          12h
kube-system   pod/etcd-k8s-node                      1/1     Running   0          12h
kube-system   pod/kube-apiserver-k8s-node            1/1     Running   0          12h
kube-system   pod/kube-controller-manager-k8s-node   1/1     Running   0          12h
kube-system   pod/kube-proxy-vrw5n                   1/1     Running   0          12h
kube-system   pod/kube-scheduler-k8s-node            1/1     Running   0          12h

NAMESPACE     NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
default       service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP                  12h
kube-system   service/kube-dns     ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   12h

NAMESPACE     NAME                        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kube-system   daemonset.apps/kube-proxy   1         1         1       1            1           kubernetes.io/os=linux   12h

NAMESPACE     NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
kube-system   deployment.apps/coredns   2/2     2            2           12h

NAMESPACE     NAME                                DESIRED   CURRENT   READY   AGE
kube-system   replicaset.apps/coredns-f9fd979d6   2         2         2       12h


1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever

2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 52:54:00:fa:c2:16 brd ff:ff:ff:ff:ff:ff
    inet 192.168.121.55/24 brd 192.168.121.255 scope global dynamic eth0
       valid_lft 3437sec preferred_lft 3437sec
    inet6 fe80::5054:ff:fefa:c216/64 scope link
       valid_lft forever preferred_lft forever

3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default
    link/ether 02:42:c0:ff:46:24 brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
       valid_lft forever preferred_lft forever

274: veth456164b1@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue master cni0 state UP group default
    link/ether 12:0c:00:b5:a6:98 brd ff:ff:ff:ff:ff:ff link-netns 5a8bcbdd-c977-4b1c-9329-36ce135b2ff8
275: veth4d418f34@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue master cni0 state UP group default
    link/ether de:c7:aa:e4:c3:0f brd ff:ff:ff:ff:ff:ff link-netns 661b01eb-4ad4-4196-a1e1-9420b34b888f

20: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN group default
    link/ether be:54:34:42:21:8c brd ff:ff:ff:ff:ff:ff
    inet 10.244.0.0/32 brd 10.244.0.0 scope global flannel.1
       valid_lft forever preferred_lft forever

21: cni0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UP group default qlen 1000
    link/ether 3a:4d:23:8d:d3:41 brd ff:ff:ff:ff:ff:ff
    inet 10.244.0.1/24 brd 10.244.0.255 scope global cni0
       valid_lft forever preferred_lft forever

294: vethf1841ae9@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue master cni0 state UP group default
    link/ether 32:fe:87:45:c9:73 brd ff:ff:ff:ff:ff:ff link-netns 39114329-c723-45cf-adee-6e35dacfb292
```


* SOLUTION: modify the config of the inner k8s to avoid IP address overlaps with the host, as follows:

* Create a config file for `kubeadm`:

  - NOTE: the certSANs is needed as otherwise the certificate for the API server
    won't be signed for the cluster IP 10.97.0.1.

```
root@k8s-master:~# more kubeadm-conf.yaml
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: "v1.18.2"
networking:
  podSubnet: "10.245.0.0/16"
  serviceSubnet: "10.97.0.0/12"
apiServer:
  certSANs:
  - "10.97.0.1"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
clusterDNS:
- 10.97.0.10
```

* Then pass it to kubeadm init:

```
kubeadm init --config kubeadm-conf.yaml
```

* Once kubeadm init completes, more changes are needed.

* The IP address for the `kubernetes` and `kube-dns` services needs to be reconfigured:

```
$ kubectl get service kubernetes -o yaml > kubernetes-service.yaml
$ sed -i 's/10.96.0.1/10.97.0.1/' kubernetes-service.yaml
$ kubectl apply --force -f kubernetes-service.yaml

$ kubectl -n kube-system get service -o yaml > kube-dns-service.yaml
$ sed -i 's/10.96.0.1/10.97.0.1/' kube-dns-service.yaml
$ kubectl apply --force -f kube-dns-service.yaml
```

* TODO: try using kubectl patch for this instead.

* After this, we should see the following:

```
root@k8s-master:~# kubectl get all --all-namespaces
NAMESPACE     NAME                                     READY   STATUS    RESTARTS   AGE
kube-system   pod/coredns-66bff467f8-5k9vj             0/1     Pending   0          3h35m
kube-system   pod/coredns-66bff467f8-nlm4z             0/1     Pending   0          3h35m
kube-system   pod/etcd-k8s-master                      1/1     Running   0          3h35m
kube-system   pod/kube-apiserver-k8s-master            1/1     Running   0          3h35m
kube-system   pod/kube-controller-manager-k8s-master   1/1     Running   0          3h35m
kube-system   pod/kube-proxy-qq7pc                     1/1     Running   0          3h35m
kube-system   pod/kube-scheduler-k8s-master            1/1     Running   0          3h35m

NAMESPACE     NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
default       service/kubernetes   ClusterIP   10.97.0.1    <none>        443/TCP                  6m8s
kube-system   service/kube-dns     ClusterIP   10.97.0.10   <none>        53/UDP,53/TCP,9153/TCP   4m13s

NAMESPACE     NAME                        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kube-system   daemonset.apps/kube-proxy   1         1         1       1            1           kubernetes.io/os=linux   3h35m

NAMESPACE     NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
kube-system   deployment.apps/coredns   0/2     2            0           3h35m

NAMESPACE     NAME                                 DESIRED   CURRENT   READY   AGE
kube-system   replicaset.apps/coredns-66bff467f8   2         2         0       3h35m
```

* DNS resolution now works inside the inner k8s cluster:

```
root@k8s-master:~# nslookup www.google.com
Server:         10.96.0.10
Address:        10.96.0.10#53

Non-authoritative answer:
Name:   www.google.com
Address: 172.217.5.100
Name:   www.google.com
Address: 2607:f8b0:4005:801::2004
```

* Flannel init works fine now:

```
root@k8s-master:~# kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
podsecuritypolicy.policy/psp.flannel.unprivileged created
clusterrole.rbac.authorization.k8s.io/flannel created
clusterrolebinding.rbac.authorization.k8s.io/flannel created
serviceaccount/flannel created
configmap/kube-flannel-cfg created
daemonset.apps/kube-flannel-ds created


root@k8s-master:~# kubectl get all --all-namespaces
NAMESPACE     NAME                                     READY   STATUS    RESTARTS   AGE
kube-system   pod/coredns-66bff467f8-pgfmd             1/1     Running   0          8m41s
kube-system   pod/coredns-66bff467f8-szz7f             1/1     Running   0          8m41s
kube-system   pod/etcd-k8s-master                      1/1     Running   0          8m49s
kube-system   pod/kube-apiserver-k8s-master            1/1     Running   0          8m49s
kube-system   pod/kube-controller-manager-k8s-master   1/1     Running   0          8m49s
kube-system   pod/kube-flannel-ds-zz744                1/1     Running   0          3m56s
kube-system   pod/kube-proxy-hclpr                     1/1     Running   0          8m41s
kube-system   pod/kube-scheduler-k8s-master            1/1     Running   0          8m49s

NAMESPACE     NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
default       service/kubernetes   ClusterIP   10.97.0.1    <none>        443/TCP                  5m14s
kube-system   service/kube-dns     ClusterIP   10.97.0.10   <none>        53/UDP,53/TCP,9153/TCP   4m54s

NAMESPACE     NAME                             DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kube-system   daemonset.apps/kube-flannel-ds   1         1         1       1            1           <none>                   3m56s
kube-system   daemonset.apps/kube-proxy        1         1         1       1            1           kubernetes.io/os=linux   8m57s

NAMESPACE     NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
kube-system   deployment.apps/coredns   2/2     2            2           8m57s

NAMESPACE     NAME                                 DESIRED   CURRENT   READY   AGE
kube-system   replicaset.apps/coredns-66bff467f8   2         2         2       8m42s
```

* One more change: the flannel configMap has the incorrect pod network cidr; needs to be patched:

```
$ kubectl -n kube-system get configmap kube-flannel-cfg  -o yaml > kube-flannel-configmap.yaml
$ sed -i 's/10.244.0.0/10.245.0.0/' kube-flannel-configmap.yaml
$ kubectl apply -f kube-flannel-configmap.yaml
# kubectl -n kube-system delete pod <flannel-pod>     <<< MUST HAVE
```

* After this everything starts working ...

* Joining a worker node was easy; just get the cluster join token and apply.

* I did some basic testing (manually) such as:

 - Creating a K8s cluster using two k8s-in-pod nodes.

 - Verifying dns works in the k8s-in-pod node.

 - Verifying inner/nested pod networking works (dns, ping, external access, etc)

 - Verifying multiple nodes and traffic among pods deployed within them



### K8s-in-pod fails when "nodev" is set in the CRI-O storage options [ SOLVED]

Inside the pod, kubeadm init fails due to runc mount problem (operation not permitted)

```
Mar 12 04:33:40 k8s-master kubelet[2664]: E0312 04:33:40.232136    2664 kuberuntime_manager.go:801] container start failed: RunContainerError: failed to start container "8288458ff049f5d00690f5e85eeb6dedfdccb9f5a1956a06f693a2d652f03ee6": Error response from daemon: OCI runtime create failed: container_linux.go:349: st
arting container process caused "process_linux.go:449: container init caused \"rootfs_linux.go:58: mounting \\\"/etc/ca-certificates\\\" to rootfs \\\"/var/lib/docker/overlay2/9f7f7084cefe161652ba83b12e65509ec70ae0be70cafaf8be1092f5f3dfb05d/merged\\\" at \\\"/var/lib/docker/overlay2/9f7f7084cefe161652ba83b12e65509ec7
0ae0be70cafaf8be1092f5f3dfb05d/merged/etc/ca-certificates\\\" caused \\\"operation not permitted\\\"\"": unknown
```

* I tracked it down to the following remount in the OCI runc (rootfs_linux.go, function remount(), L1005):

  ```
  unix.Mount(m.Source, dest, m.Device, uintptr(m.Flags|unix.MS_REMOUNT), "")
  ```

  where flags = 0x5001  (`MS_RDONLY | MS_BIND | MS_REC`)

  and dest = `var/lib/docker/overlay2/49ee48c33365f570ce84c430f7ec943e43c12113351d0522f9297067e59fca9d/merged/etc/ca-certificates`


* But it's weird: if I enter the namespaces of the runc init process whose `mount` failed, I can use the mount command
  and it works fine:

  ```
  mount -o remount,ro,rbind /var/lib/docker/overlay2/49ee48c33365f570ce84c430f7ec943e43c12113351d0522f9297067e59fca9d/merged/etc/ca-certificates
  ```

* The mount at `/var/lib/docker/overlay2/49ee48c33365f570ce84c430f7ec943e43c12113351d0522f9297067e59fca9d/merged/etc/ca-certificates` is a bind
  mount from directory `/etc/ca-certificates` inside the container:

```
| |-/var/lib/docker/overlay2/49ee48c33365f570ce84c430f7ec943e43c12113351d0522f9297067e59fca9d/merged                     overlay                                                overlay  rw,relatime,lowerdir=/var/lib/docker/overlay2/l/JDKSX2KKUWKAT4K7FMWSOWRV5P:/var/lib/docker/overlay2/l/MX46MMCFHG6CMTZEA3T3AWWG2A:/var
| | `-/var/lib/docker/overlay2/49ee48c33365f570ce84c430f7ec943e43c12113351d0522f9297067e59fca9d/merged                   overlay                                                overlay  rw,relatime,lowerdir=/var/lib/docker/overlay2/l/JDKSX2KKUWKAT4K7FMWSOWRV5P:/var/lib/docker/overlay2/l/MX46MMCFHG6CMTZEA3T3AWWG2A:/var
| |   |-/var/lib/docker/overlay2/49ee48c33365f570ce84c430f7ec943e43c12113351d0522f9297067e59fca9d/merged/etc/ca-certificates
| |   |                                                                                                                  overlay[/etc/ca-certificates]                          overlay  rw,nodev,relatime,lowerdir=/var/lib/containers/storage/overlay/l/5LBUU6AAND5O2EL5FCE3JWV7KK:/var/lib/containers/storage/overlay/l/5LB
```

* The problem is that when OCI runc is doing the bind-mount per the container's
  OCI spec, it does a remount to apply the specified mount options. But the
  specified mount options do not include `nodev`, so runc is in fact clearing
  that mount option. The kernel denies this with EPERM (aparently this is not
  allowed within a user-ns).

* Problem is a known issue to the OCI runc developers.

  - https://github.com/opencontainers/runc/pull/1603
  - https://github.com/opencontainers/runc/issues/1523

* No fix as consensus is that fix should be done at higher layer (e.g.,
  containerd or docker).

* Note: problem occurs with latest k8s too (1.20 inside the sysbox pod), with
  latest Docker (20.1) and latest containerd (1.4.4).

* Reviewing the linux kernel, it looks like certain mount attributes are not
  changeable from within a user-ns (i.e., they are "locked"). These are:

  ATIME, RDONLY, NODEV, NOEXEC, NOSUID

  See `lock_mnt_tree()` in fs/namespace.c (and callers)

  TODO: check how the locks get applied in the kernel

* Solution: maybe sysbox can allow these inside a sys container, *if* they
  don't change an immutable mount. This way we know that they are only
  changing a mount

  - No way to do this; mounts are locked at kernel level.

  - Even true root can't modify those mount attributes.

* Why is "nodev" set on the sysbox pod's "/" mount?

* Solution 1:

  - Check if there is a CRI-O or containers/storage config to avoid
    the 'nodev' attribute on the sysbox container's rootfs mount.

  - This way we avoid triggering the Docker bug inside the sys container
    which causes it to not honor the `nodev` when setting up inner container
    attributes (as directed by k8s).

  - There is: globally in `/etc/containers/storage.conf`, set `mountopt = ""` (default is `mountopt = "nodev"`)

  - Or for CRI-O only in: `/etc/crio/crio.conf`, set `crio.storage_driver=overlay` and `crio.storage_option=["overlay.mountopt=metacopy=on"]`.

  - NOTE: THIS WORKED!

* Solution 2:

  - Have sysbox setup the container's rootfs mounts in a temporary mount-ns,
    before creating the container's user-ns and mount-ns.

  - This way, all the container rootfs mount become locked by the linux kernel.

  - This would void the need for sysbox-fs to handle the locking of these mounts
    (i.e., void the need for the immutable mounts mechanism).

  - Note: I added this to the sysbox internal user guide "immutable mounts" doc.



### Found this error when running pods on a worker node (not sysbox related) [SOLVED]

```
6b-c0cd6c981492)" with CreatePodSandboxError: "CreatePodSandbox for pod \"nginx-6799fc88d8-cpk7s_default(1c72b1fb-f0ae-4915-9c6b-c0cd6c981492)\" failed: rpc error: code = Unknown desc = failed to create pod network sandbox k8s_nginx-6799fc88d8-cpk7s_default_1c72b1fb-f0ae-4915-9c6b-c0cd6c981492_0(eeb6a59bbcb04be1463b9
937873f137a4dcd2f7fda5ef4b60ce64ffdc73ae071): failed to set bridge addr: \"cni0\" already has an IP address different from 10.244.2.1/24"
```

* Solve it by removing the node from the cluster, then running:

```
$ ip link set cni0 down
$ brctl delbr cni0
```

Then restarting CRI-O, then re-joining the node to the cluster.




## Troubleshooting Tips

### Pod fails to launch and Kubelet logs show "not enough avaiable IDs" error.

```
known desc = error creating pod sandbox with name "k8s_ubu-bio-systemd-docker_default_0d0e5315-eaaf-43dc-be44-d7bc436f7b4b_0": could not find enough available IDs
0e5315-eaaf-43dc-be44-d7bc436f7b4b)" failed: rpc error: code = Unknown desc = error creating pod sandbox with name "k8s_ubu-bio-systemd-docker_default_0d0e5315-eaaf-43dc-be44-d7bc436f7b4b_0": could not find enough available IDs
```

Solution: make sure user "containers" has an entry in `/etc/subuid` and
`/etc/subgid`, and that the range is large enough. CRI-O picks up the
containers subuids from that range.



## TODO

* Add crictl + CRI-O + sysbox tests to sysbox test suite  [DONE]

* See if there is a way for CRI-O to use user-ns but not chown the container's rootfs. [DONE - none found]

  - This, together with a change in sysbox, may enable faster pod deployment by
    avoiding CRI-O having to chown the container image.

* Ensure sysbox ITs and UTs pass with all sysbox-pod changes. [DONE]

* Should this CRI-O setting be increased (in `/etc/crio/crio.conf`)?

  - "pids_limit = 1024"

* TODO: in sysbox-runc we used the mount() command to overcome EPERM problems on
  mount syscalls. We should study this problem again and possibly improve it by
  pulling mount attributes using the statfs() syscall.

* Re-work sysbox-fs: use combination of same netns to identify a pod. [DONE]

* Fix problem with `docker run --runtime=sysbox-runc --net=container:<id>` [DONE]

* Work on fix for pod volume/mount permissions. [DONE]

* Sysbox-fs: when sysbox-runc fails to create a container, it leaves a stale mount under `/var/lib/sysboxfs/<id>` [DONE]

* Fix userns ID mappings coallescing in sysbox-runc. [DONE]

* Rebase sysbox-pod branches based on latest changes in master branches.  [DONE]

* Submit sysbox-pod PRs to sysbox internal branches. [IN-PROG]

  - sysbox-fs-internal [REVIEW DONE, NEEDS MERGING]

  - sysbox-runc-internal [PENDING REVIEW]

  - sysbox-mgr-internal [PENDING REVIEW]

  - sysbox-ipc-internal [PENDING REVIEW]

  - sysbox-libs-internal [PENDING REVIEW]

  - sysbox-pkgr [REVIEW DONE, NEEDS MERGING]

  - sysbox-internal [NEED TO REBASE FROM MASTER, CREATE PR]

* Create package for GKE (ubu-bionic) [DONE]

* Try installing sysbox on a GCP k8s node [DONE]

  - Worked manually; I created a doc to track this.

* Update other test container images to add crictl + CRI-O (same as done on
  ubuntu-focal image).

* Debug and fix hang in kind test [DONE]

* Write up sysbox install daemon-set [DONE]

* Update sysbox-pkg installer tests per changes in installer.  << HERE

* Send sysbox pods early sample to:

  - Okteto

  - Jerome Petazzoni

  - Miroslav

  - Coder

  - Clidey

* Debug this sysbox-fs error (saw it during the sysbox perf tests and kind tests, consistently every few iterations):

```
# time="2021-04-04 19:08:25" level=error msg="FUSE file-system could not be unmounted: waitid: no child processes"
# time="2021-04-04 19:08:25" level=error msg="FuseServer to destroy could not be eliminated for container id 0e23da6a824f5ab30bc18c70a5d6f7180ca6d32395ad5154ec0f6036cc19c55e"
```

* Come up with solution for CRI-O versions > 1.20

* Remove all unneeded usage of userns in sysbox-fs

* See if we can fix the inner user-ns restriction in sysbox.

* Add apparmor profile for sysbox containers.

  - Use it by default, unless a profile is explicitly set by higher level container manager.

* Deal with lack of Docker apparmor profile inside k8s-host. [SKIP - not a critical issue since the inner Docker works either way]

* Fix sysbox-runc sysctl validator code

  `libcontainer/configs/validate/validator.go`

* Come up with bind mount ownership soludion for distros without shiftfs / id-mapped mounts

  - auto-chown

  - with auto detection for sharing (containers sharing same storage are assigned same uid mappings)

  - sysbox-ee feature

* Add more sysbox pod tests

* Write up docs on how to use sysbox pods

* Cleanup github issues

* Fix problem with sysbox-mgr failing to init `/var/lib/sysbox` correctly sometimes.

* See if CRI-O 1.21 and top-of-tree works when /etc/subuid has
  `containers:0:296608:65536` and we use "runAsUser: 296608".

  - This way we always use the same UID for all containers.

* Modify sysbox installer to not require Docker [DONE - sysbox-pkgr repo, sysbox-pod branch]

  - Modify sysbox docs accordingly

* Modify sysbox installer to configure CRI-O with Sysbox. [SKIP]

* Fix this problem with sysbox's systemd service unit on ubu bionic:

```
systemctl status sysbox

Apr 09 05:49:22 gke-my-first-cluster-1-pool-1-fdd5037a-4jp3 systemd[1]: /lib/systemd/system/sysbox.service:15: Failed to parse service type, ignoring: exec
```

* write tests for newly added sysbox-fs proc handlers.

* sysbox-fs: log when modifying a host sysctl.
