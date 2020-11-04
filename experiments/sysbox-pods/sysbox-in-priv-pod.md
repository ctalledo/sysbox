# Experiment: Sysbox in a Privileged Pod


* Kyle at coder.com indicates that deploying a privileged pod and running sysbox
  inside of it fails in a similar way to sysbox issue #67 (EPERM mounting
  sysfs).

* Kyle indicates things work fine when deploying sysbox inside a docker
  privileged container.

  - Makes sense since we do this all the time in sysbox's test framework.


## Repro Setup

* Stop crio

* Start Docker

* Start K8s

```
sudo swapoff -a
sudo kubeadm init --kubernetes-version=v1.19.3 --pod-network-cidr=10.244.0.0/16

kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
kubectl taint node k8s-node node-role.kubernetes.io/master:NoSchedule-
```

* Create a pod with sysbox inside

  - I used the `sysbox-priv-pod.yaml`

* I then copied the sysbox binaries into the pod.

  - Ideally the binaries would be preloaded and started automatically.

* Inside the pod, do the following:

  - Edit the /etc/docker/daemon.json file to add sysbox as a runtime

  - Start dockerd

  - Start sysbox

* Hit the error reported by Kyle:

```
root@pod-with-sysbox:~# docker run --runtime=sysbox-runc -it --rm alpine
docker: Error response from daemon: OCI runtime create failed: container_linux.go:364: starting container process caused "process_linux.go:533: container init caused \"rootfs_linux.go:62: setting up rootfs mounts caused \\\"rootfs_linux.go:932: mounting \\\\\\\"sysfs\\\\\\\" to rootfs \\\\\\\"/var/lib/docker/overlay2/693413bbca0bb32f9c9b941304cc0c86c59ed65d1a6072c6be912316cbcd5818/merged\\\\\\\" at \\\\\\\"sys\\\\\\\" caused \\\\\\\"operation not permitted\\\\\\\"\\\"\"": unknown.
ERRO[0000] error waiting for container: context canceled
```

* At host level, pstree looks like this:

```
             |                     |-containerd-shim(27719,27719)---pause(27736,27736,ipc,mnt,net,pid,uts)
             |                     `-containerd-shim(27823,27823)-+-bash(27932,27932,ipc,mnt,net,pid,uts)---dockerd(28431,28431)---containerd(28440,28440)
             |                                                    `-tail(27841,27841,ipc,mnt,net,pid,uts)-+-sysbox-fs(30214,30168)
             |                                                                                            `-sysbox-mgr(30176,30168)
```


## Problem hypothesis

* I noticed sysfs is mounted read-only inside the privileged pod.

  - REASON: the pod's pause container mounts sysfs read-only by default. sysfs
    is tighly coupled with the netns. Since the work container shares the
    network ns with the pause container, this automatically forces the read-only
    attribute on the work container's sysfs mount.

* To fix this, I simply remounted the /sys as read-write inside the privileged container:

  ```
  $ mount -o remount,rw /sys /sys
  ```

* And this unblocked things!

* I tried running a docker-in-docker container inside the privileged pod; things worked well.

* I then tried running a k8s-in-docker container inside the privileged pod; the
  container deployed, but after k8s initialized, it lost network connectivity.


## For reference: Sysbox inside a privileged Docker container

* pstree looks like this:


```
             |-containerd(541339,541339)---containerd-shim(566516,566516)---bash(566534,566534,ipc,mnt,net,pid,uts)-+-docker(571193,571193)
             |                                                                                                      |-dockerd(566713,566534)---containerd(566731,566731)---containerd-shim(571228,571228)---sh(571276,571276,cgroup,ipc,mnt,net,pid,user,uts)
             |                                                                                                      |-sysbox-fs(571103,566534)
             |                                                                                                      `-sysbox-mgr(571084,566534)
```
