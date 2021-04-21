# Installing Sysbox on GKE

This document describes how to manually install Sysbox on a GKE Kubernetes
cluster node.

*   NOTE: Manual configurations on a GKE Kubernetes (K8s) node DO NOT PERSIST if
    the node is destroyed and re-created (e.g., if it becomes unhealthy and GKE
    decides to replace it).

*   Nestybox is developing a Kubernetes (K8s) daemonset that will perform this
    setup automatically and which ensures the configuration persists across a
    node's life-cycle.

## Contents

*   [Why Sysbox on GKE?](#why-sysbox-on-gke)
*   [GKE Requirements](#gke-requirements)
*   [Sysbox Installation](#sysbox-installation)
*   [Setup Steps](#setup-steps)
*   [Sysbox Container Images](#sysbox-container-images)
*   [Pod Isolation / Security](#pod-isolation--security)
*   [Volume Mounts](#volume-mounts)
*   [Upgrading Sysbox](#upgrading-sysbox)
*   [Uninstalling Sysbox](#uninstalling-sysbox)

## Why Sysbox on GKE?

Sysbox is a low-level container runtime (aka "runc") that improves the
security and capabilities of containers and pods.

With Sysbox, GKE can deploy strongly isolated (rootless) pods that can act as
container-based "VMs", capable of seamlessly running systemd, Docker, and even
Kubernetes in them.

Prior to Sysbox, running such pods required using privileged pods and very
complex pod setups and entrypoints. This is insecure (privileged pods allow
users inside the pod to easily compromise the K8s host) and puts a lot of
complexity on the K8s cluster admin & users.

With Sysbox this insecurity and complexity go away: the pods are well isolated,
and Sysbox absorbs all the complexity of setting up the pod correctly.

## GKE Requirements

To use Sysbox on GKE, you need a GKE K8s cluster with K8s version 1.20.

*   By default GKE chooses the K8s 1.19 version.

*   However the GKE "rapid channel" carries the 1.20 version. Upgrade the cluster
    to this version before installing Sysbox on the cluster nodes.

## Sysbox Installation

Sysbox can be installed in all or some of the cluster nodes, per your
requirements. The steps are below.

Installing Sysbox on a node does not imply all pods on the node are deployed
with Sysbox. You can choose which pods use Sysbox and which continue to use the
default GKE low-level runtime (OCI runc), or any other runtime you choose.

Pods deployed with Sysbox are managed via GKE just like any other pods, and
can communicate with any other pods according to your K8s networking policy.

## Setup Steps

These are the high-level steps to setup Sysbox on GKE:

1.  Create GKE K8s nodes using the "Ubuntu with Containerd" image.

2.  Configure each node:

a) Install CRI-O

b) Install Shifts

c) Install Sysbox

d) Configure Kubelet to use CRI-O

3.  Add the K8s runtime class for Sysbox and label the nodes

4.  Deploy your pods

Details for each step are in the sections that follow.

### Step 1: Create GKE K8s nodes based on the "Ubuntu with Containerd" image

If you have nodes based on this image already, then skip this step. Otherwise
follow the sub-steps below.

To use Sysbox on GKE, use the "Ubuntu with Containerd" node image for each node
in which Sysbox will be installed. This image carries Ubuntu Bionic with a 5.4
kernel, thus meeting Sysbox's requirements.

To do this via the GKE web interface:

*   Select the desired K8s cluster

*   Select "Add Node Pool"

*   Select "Nodes -> Image Type" to "Ubuntu with Containerd (ubuntu_containerd)".

*   Configure any other parameters for the nodes and node-pool per your
    requirements (e.g., number of nodes, machine type, disk size, etc.)

We recommend the node have 4 vCPUs and 4GB RAM at a minimum.

Note that it's fine to have a cluster with heterogeneous nodes, where some have
Sysbox installed and some don't. In a subsequent step we will label the nodes so
K8s can schedule pods that require Sysbox on the appropriate node(s).

### Step 2: Per-Node Setup

This is the most tedious part of the process to do manually. Nestybox is
developing a K8s daemonset that will take care of this automatically.

Apply the following sub-steps on each node. You'll need to ssh into the
node(s) and have root privileges on it.

#### a) Install CRI-O

CRI-O is a container runtime. It logically sits between K8s and Sysbox (i.e.,
K8s sends pod creation commands to kubelet, which then talks to CRI-O, which
then talks to Sysbox to create the pod).

CRI-O is currently (as of 04/2021) the only CRI that supports rootless pods (a
feature that is required to deploy pods with Sysbox). Containerd does not yet
support this yet.

CRI-O installation steps can be found in the [CRI-O homepage](https://cri-o.io/)
but we repeat them here for convenience.

Please use CRI-O v1.20 so that it matches the K8s version.

*   CRI-O versions < v1.20 do not support rootless pods, so they won't work
    with Sysbox.

*   CRI-O versions > v1.20 won't work either since they don't match the K8s cluster version
    and are not yet tested with Sysbox.

In the steps below, note that the shell environment variable "OS" must match the
node's distro (e.g., Ubuntu 18.04 (Bionic)) and "VERSION" must match the K8s
version (e.g., 1.20):

Do these steps as the root user:

```console
export OS=xUbuntu_18.04
export VERSION=1.20

echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list

curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/Release.key | apt-key add -
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | apt-key add -

apt-get update
apt-get install cri-o cri-o-runc
```

#### b) Install Shiftfs

The shiftfs kernel module is needed if you want support for host volume mounts
on pods deployed with K8s + Sysbox.

NOTE: If you don't need this, you can skip this section.

The shiftfs module performs filesystem user-ID and group-ID "shifting", which
enables host volumes mounted into pods deployed with Sysbox to show up inside
the pod with appropriate user:group ownership.

Shiftfs is typically included in Ubuntu desktop and service images, but it's not
currently included in the Ubuntu-based cloud images in GKE (unfortunately).

To install shiftfs, do these steps as the root user:

```console
apt-get install -y make dkms
git clone -b k5.4 https://github.com/toby63/shiftfs-dkms.git shiftfs-k54
cd shiftfs-k54
./update1
make -f Makefile.dkms
echo shiftfs | tee /etc/modules-load.d/shiftfs.conf
modprobe shiftfs
```

Then verify shiftfs is loaded in the kernel:

```console
lsmod | grep shiftfs
```

#### c) Install Sysbox

Use a Sysbox package version that supports sysbox-pods.

Install Sysbox (as a root user):

```console
dpkg -i <sysbox-pkg-name>
```

NOTE: If the sysbox package installer asks about configuring Docker, answer "no".

Configure CRI-O to learn about Sysbox by editing the `/etc/crio/crio.conf` file as follows:

*   Modify the cgroup settings:

```toml
# Cgroup setting for conmon
#conmon_cgroup = "system.slice"
conmon_cgroup = "pod"

# Cgroup management implementation used for the runtime.
#cgroup_manager = "systemd"
cgroup_manager = "cgroupfs"
```

* Set the CRI-O storage driver to "overlayfs" with "metacopy=on"; make sure to
  remove the "nodev" option too (if present):

```toml
# Storage driver
crio.storage_driver=overlay
crio.storage_option=["overlay.mountopt=metacopy=on"]
```

*   Add the sysbox runtime setting:

```toml
# Sysbox runtime
[crio.runtime.runtimes.sysbox-runc]
runtime_path = "/usr/local/sbin/sysbox-runc"
runtime_type = "oci"
allowed_annotations = ["io.kubernetes.cri-o.userns-mode"]
```

Then restart CRI-O:

```console
systemctl restart crio
```

Finally verify CRI-O is happy:

```console
systemctl status crio
```

#### d) Configure Kubelet to use CRI-O

By default, Kubelet is configured to use the containerd runtime to create pods.

We want Kubelet to use CRI-O instead of containerd to deploy pods on the node
(because CRI-O supports rootless pods, while containerd does not).

This is done by modifying the `KUBELET_OPTS` environment variable defined in the
`/etc/default/kubelet`. This variable dictates the command line options passed
to Kubelet when it starts.

The following `sed` commands do this (must run as root):

```console
sed -i 's@--container-runtime-endpoint=unix:///run/containerd/containerd.sock@--container-runtime-endpoint=unix:///run/crio/crio.sock@g' /etc/default/kubelet
sed -i 's@--runtime-cgroups=/system.slice/containerd.service@--runtime-cgroups=/system.slice/crio.service@g' /etc/default/kubelet
```

Then restart Kubelet:

```console
systemctl restart kubelet
```

Verify Kubelet is happy:

```console
systemctl status kubelet
```

Verify K8s is happy (since kubelet restarted). Use `kubectl` on the K8s management machine:

```console
kubectl get nodes
```

If all is good, the node in which we just reconfigured the kubelet should show
up as "Ready" in K8s.

That's it for installations. This was the harder part of the setup and from here
on it should be prety easy.

### Step 3: Add the K8s runtime class for Sysbox and label the nodes

In order for K8s to become aware of Sysbox, a new "runtime class" resource must
be applied.

But before doing so, if only some nodes in the cluster have Sysbox but some don't,
you need to label the Sysbox nodes so that you can direct K8s to schedule the
desired pods on them.

You can chose whatever label you want. In the example below we use the label
"sysboxInNode=true", but you can choose any other label that makes sense to you
(e.g., "nodeSupportsSysbox=yes", etc.)

For each node where Sysbox is installed, label them with:

```console
kubectl label nodes <node-name> sysboxInNode=true
```

Once you've labeled the nodes, you define the runtime class resource for
Sysbox as follows:

```yaml
apiVersion: node.k8s.io/v1beta1
kind: RuntimeClass
metadata:
  name: sysbox-runc
handler: sysbox-runc
scheduling:
  nodeSelector:
     sysboxInNode: true
```

The `scheduling.nodeSelector` ensures that all pods that use this runtime class
will be scheduled on nodes that support Sysbox.

### Step 4: Deploy pods

Now to the fun part: create a pod spec and deploy it!

Here is a sample pod spec to deploy a "VM-like" pod that is rootless (i.e., the
root user in the pod maps to an unprivileged user on the host), runs systemd as
init (pid 1), and comes with Docker (daemon + CLI) inside.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ubu-bio-systemd-docker
  annotations:
    io.kubernetes.cri-o.userns-mode: "auto:size=65536"
spec:
  runtimeClassName: sysbox-runc
  containers:
  - name: ubu-bio-systemd-docker
    image: ghcr.io/nestybox/ubuntu-bionic-systemd-docker
    command: ["/sbin/init"]
  restartPolicy: Never
```

There are two key pieces of the pod's spec that tie it to Sysbox:

*   "runtimeClassName": Tells K8s to deploy the pod with Sysbox (rather than the
    default OCI runc). The pods will be scheduled on the nodes that support
    Sysbox.

*   "io.kubernetes.cri-o.userns-mode": Tells CRI-O to launch this as a rootless
    pod (i.e., via the Linux user-namespace) and to allocate a range of 65536
    Linux user-namespace user and group IDs. This is required for Sysbox pods.

Also, for Sysbox pods you typically want to avoid sharing the process namespace
between containers in a pod. Thus, avoid setting `shareProcessNamespace: true`
in the pod's spec, especially if the pod carries systemd inside (as otherwise
systemd won't be pid 1 in the pod and will fail).

That's all! the next sections touch on other topics related to Sysbox pods.

## Sysbox Container Images

The pod in the prior example uses the `ghcr.io/nestybox/ubuntu-bionic-systemd-docker`,
but you can use any container image you want.

*   Sysbox places no requirements on the container image.

Nestybox has several images which you can find here:

https://hub.docker.com/u/nestybox

Those same images are in the Nestybox GitHub registry (`ghcr.io/nestybox/<image-name>`).

Some of those images carry systemd only, others carry systemd + Docker, other
carry systemd + K8s (yes, you can run K8s inside rootless pods deployed by
Sysbox).

## Pod Isolation / Security

Pods deployed with Sysbox are rootless (i.e., the root user in the pod maps to
an unprivileged user on the host).

This provides strong isolation between the pod and the host (pod processes
have no privileges on the host).

CRI-O, which logically sits below K8s but above Sysbox, is the entity that
creates the Linux user-namespace for the pods.

Each pod gets as dedicated user-namespace with exclusive user-ID and group-ID
mappings. This provides strong pod-to-pod isolation (in addition to strong
pod-to-host isolation).

## Volume Mounts

If you wish to mount host volumes into a K8s pod deployed with Sysbox, the K8s
node's kernel must carry the `shiftfs` kernel module (see [above](#b-install-shiftfs)).

This is because such pods are rootless (as described in the prior section),
meaning that the root user inside the pod maps to a non-root user on the host
(e.g., pod user ID 0 maps to host user ID 296608). Thus, host directories or
files which are typically owned by users IDs in the range 0->65535 will show up
as `nobody:nogroup` inside the pod.

The `shiftfs` module solves this problem, as it allows Sysbox to "shift" user
and group IDs, such that files owned by users 0->65536 on the host also show up
as owned by users 0->65536 inside the pod.

Once shiftfs is installed, Sysbox will detect this and use it when necessary.
As a user you don't need to know anything about shiftfs; you just setup the pod
with volumes as usual.

For example, the following spec creates a Sysbox pod with ubuntu-bionic + systemd +
docker and mounts host directory `/root/somedir` into the pod's `/mnt/host-dir`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ubu-bio-systemd-docker
  annotations:
    io.kubernetes.cri-o.userns-mode: "auto:size=65536"
spec:
  runtimeClassName: sysbox-runc
  containers:
  - name: ubu-bio-systemd-docker
    image: ghcr.io/nestybox/ubuntu-bionic-systemd-docker
    command: ["/sbin/init"]
    volumeMounts:
      - mountPath: /mnt/host-dir
        name: host-vol
  restartPolicy: Never
  nodeSelector:
    runtime: sysbox
  volumes:
  - name: host-vol
    hostPath:
      path: /root/somedir
      type: Directory
```

When this pod is deployed, Sysbox will automatically enable shiftfs on the pod's
`/mnt/host-dir`.

With shiftfs you can even share the same host directory across pods, even if
the pods each get exclusive Linux user-namespace user-ID and group-ID mappings.
Each pod will see the files with proper ownership inside the pod (e.g., owned
by users 0->65536) inside the pod.

## Upgrading Sysbox

To upgrade Sysbox follow these steps on each node where Sysbox is installed:

1.  Drain all sysbox pods from the node.

*   You may need to cordon off the node to prevent K8s from deploying new Sysbox-based pods in it.

2.  Remove Sysbox from the node:

```console
sudo dpkg --purge sysbox
```

3.  Install the desired version of Sysbox:

```console
sudo dpkg -i <sysbox-pkg>
```

where `<sysbox-pkg>` is the new version of Sysbox (e.g., downloaded from GitHub).

NOTE: you don't need to restart CRI-O or Kubelet when upgrading Sysbox.

4.  If you cordoned the node, then remove the cordon to allow K8s to schedule
    Sysbox pods on it.

## Uninstalling Sysbox

To upgrade Sysbox follow these steps on each node where Sysbox is installed:

1.  Delete all sysbox pods on the node.

*   You may need to cordon off the node to prevent K8s from deploying new Sysbox-based pods in it.

2.  Remove Sysbox from the node:

```console
sudo dpkg --purge sysbox
```

3.  Optionally, remove the Sysbox configuration from CRI-O's config file (`/etc/crio/crio.conf`):

Remove these lines:

```toml
# Sysbox runtime
[crio.runtime.runtimes.sysbox-runc]
runtime_path = "/usr/local/sbin/sysbox-runc"
runtime_type = "oci"
allowed_annotations = ["io.kubernetes.cri-o.userns-mode"]
```

4.  Changes to the CRI-O config file won't take effect unless CRI-O is restarted. You can choose
    to restart now or later.

NOTE: when restarting CRI-O, all K8s control-plane pods on the node will be restarted,
meaning that the node will become temporarily unavailable.

```console
systemctl restart crio
```
