# Sysbox Deployment in Kubernetes

## Goals

* Make it easy for people to install Sysbox on a K8s node.

  - Automate process as much as possible.

  - Reduce friction to increase adoption.


## Dev plan

* We will follow the example of [kata-deploy](https://github.com/kata-containers/packaging/tree/master/kata-deploy).

* Need the following:

  - Sysbox RBAC daemonset (to give the sysbox install/uninstall daemonsets permissions to configure the nodes)

  - Sysbox install daemonset

  - Sysbox cleanup daemonset


## Sysbox Deployment Procedure

* Host requirements:

  - Install shiftfs (if necessary)

    - See dkms site

  - Install CRI-O and configure it

    - cgroupfs

    - user "containers" in /etc/subuid and /etc/subgid

  - Configure K8s to use CRI-O.

    - Newly added nodes: `kubeadm --join --crio-socket ...`

    - TODO: write procedure for existing nodes

  - Label K8s nodes on which you want Sysbox installed with "sysbox-deploy". The
    sysbox-deploy daemonset installs sysbox only on nodes that have this label.

  - Ensure this a worker node; do *not* run the sysbox-deploy daemonset on
    control plane nodes as the installation requires resetting the CRI-O
    runtime.  Thus, if executed on a control-plane node, it will reset the K8s
    control plane.

* K8s admin sysbox install:

```
$ kubectl apply -f https://raw.githubusercontent.com/.../sysbox-rbac.yaml
$ kubectl apply -f https://raw.githubusercontent.com/.../sysbox-deploy.yaml
```

  - NOTE: make sure to apply the `sysbox-rbac.yaml` before the
    `sysbox-deploy.yaml`, as otherwise K8s won't schedule the daemonset.

  - NOTE: The installation daemonset will add a label to the node:
    `sysbox-runtime=running`. This label means sysbox is running on the node.

* Verify sysbox is installed correctly:

```
$ kubectl -n kube-system logs <sysbox-deploy-pod>

Installing Sysbox on host
Detected host distro: ubuntu_20.04
Configuring host sysctls
kernel.unprivileged_userns_clone = 1
fs.inotify.max_queued_events = 1048576
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1048576
kernel.keys.maxkeys = 20000
kernel.keys.maxbytes = 400000
Probing kernel modules

Configfs kernel module is not loaded. Configfs may be required by certain applications running inside a Sysbox container.

Starting Sysbox
Adding Sysbox to CRI-O config
Adding K8s label "sysbox-runtime=running" to node
node/k8s-node3 labeled
Sysbox installation completed.
Signaling CRI-O to reload it's config.
```

* Add a K8s runtime class resource:

```
$ kubectl apply -f https://raw.githubusercontent.com/.../sysbox-runtimeclass.yaml
```

* Deploy pods.

  - TODO: show example pod spec.



## Sysbox Removal Procedure

* Sysbox removal from a host is done by reverting the installtion steps.

* Stop all pods on the node; if necessary cordon off the node.

* Delete the k8s runtime class resource.

```
$ kubectl delete runtimeclass sysbox-runc
runtimeclass.node.k8s.io "sysbox-runc" deleted
```

* Delete the sysbox-deploy daemonset and apply the sysbox-cleanup daemonset:

```
$ kubectl delete -f sysbox-deploy.yaml
$ kubectl apply -f sysbox-cleanup.yaml
$ kubectl delete -f sysbox-cleanup.yaml
```

* Remove the sysbox RBAC daemonset.

```
$ kubectl delete -f sysbox-rbac.yaml
```


## Sysbox Deploy Artifacts

### Sysbox Deployment Container (nestybox/sysbox-deploy and nestybox/sysbox-ee-deploy)

- Install / cleanup script

- Sysbox binary (for all distros)

  - Ths install script figures out which binary to use based on the host distro
    & kernel.

- Shiftfs binaries [PENDING]

- systemctl

- kubectl

* Runs with host mounts of appropriate dirs so it can do its job.

  - Needs to talk to systemd on the host.

  - Needs to talk to k8s on the cluster.

* Needs to configure sysctls in host


### Sysbox Deploy K8s Manifests (yaml)

* RBAC manifest

* Sysbox Deploy manifest

* Sysbox Cleanup manifest


## CRI-O Deployment Daemonset [PENDING]

* It would be great to have a CRIO-deploy daemonset too, similar to sysbox-deploy.

  - With an install script and CRI-O binaries, for each type of host.

* Runs with host mounts of appropriate dirs so it can do its job.

  - Needs to talk to systemd on the host.

  - Needs to configure Kubelet and restart it

* CRI-O Deploy manifest

* CRI-O Cleanup manifest


## TODO

* Check that the basic sysbox-deploy container can be deployed on the k8s host [DONE]

* Add CRI-O version check to sysbox deploy daemonset script [SKIP]

  - I tried this but the daemonset was unable to call "crio --version" on the host because
    of a shared library problem

    `/mnt/host/usr/bin/crio: error while loading shared libraries: libseccomp.so.2: cannot open shared object file: No such file or directory`

* Figure out why sys container has unexpected subuid/gid range [DONE]

  - Was due to overlap in subuid ranges in /etc/subuid.

* Finalize improvements in daemonset [DONE]

* Create runtime class with selector for sysbox nodes [DONE]

* Cleanup internal notes [DONE]

* Rename sysbox-deploy -> sysbox-deploy-k8s [DONE]

* Cleanup repo history [DONE]

* Write instructions for users to try daemonset [DONE]

* Verify steps manually [DONE]

* Make the sysbox-pods preview repo public. [DONE]

* Move sysbox-deploy scripts to the sysbox-pkgr repo   <<< HERE

  - Won't be fully automated build because we need the binaries for each distro.

* Add support for CRI-O 1.21+

* Write scripts to install shiftfs, install & config CRIO, configure kubelet.

  - Make these available

  - Ideally we have a single "prepare node" script that does all of the above.

* Check if Docker installation is required on the host [DONE - not required]

* Try sysbox daemonset on:

  - Self host K8s cluster [DONE]

  - GKE [DONE - worked but with errors ... needs further debug ]

* Fix daemonset so it only installs on nodes with "name=sysbox-deploy-k8s" label.

  - On GKE it installed on all nodes for some reason ... even thought the labels were fine.

* Improve daemonset to include shiftfs binaries. [SKIP]

* Create daemonset for crio runtime installation [SKIP]

* Write up a docker-based sysbox installer

  - To install sysbox via a docker container (similar to sysbox-deploy but for non k8s hosts)




## References for sysbox deploy

* Kubevirt installation (requires CRI-O too):

https://kubevirt.io/2019/KubeVirt_k8s_crio_from_scratch.html
https://kubevirt.io/2019/KubeVirt_k8s_crio_from_scratch_installing_kubernetes.html

* Kata-deploy

https://github.com/kata-containers/packaging/tree/master/kata-deploy)

* CRI-O installation

https://cri-o.io/
