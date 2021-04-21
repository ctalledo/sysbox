# Sysbox K8s Deploy

* We will follow the example of kata-deploy: https://github.com/kata-containers/packaging/tree/master/kata-deploy

* Need the following:

  - Sysbox RBAC daemonset (to give the sysbox install/uninstall daemonsets permissions to configure the nodes)

  - Sysbox install daemonset

  - Sysbox uninstall daemonset

* K8s admin sysbox install:

```
$ kubectl apply -f https://raw.githubusercontent.com/.../crio-rbac.yaml
$ kubectl apply -f https://raw.githubusercontent.com/.../crio-deploy.yaml

$ kubectl apply -f https://raw.githubusercontent.com/.../sysbox-rbac.yaml
$ kubectl apply -f https://raw.githubusercontent.com/.../sysbox-deploy.yaml
$ kubectl apply -f https://raw.githubusercontent.com/.../sysbox-runtimeclass.yaml
```

The installation daemonset will label the nodes with `sysbox-runtime=true`.


* K8s admin sysbox uninstall:

```
$ kubectl delete -f sysbox-deploy.yaml
$ kubectl apply -f sysbox-cleanup.yaml
$ kubectl delete -f sysbox-cleanup.yaml
$ kubectl delete -f sysbox-rbac.yaml
```

* To remove CRI-O:

```
$ kubectl delete -f crio-deploy.yaml
$ kubectl apply -f crio-cleanup.yaml
$ kubectl delete -f crio-cleanup.yaml
$ kubectl delete -f crio-rbac.yaml
```

## Artifacts

### Sysbox Deployment Container

- Install / cleanup script

- Sysbox binary

- Shiftfs binary

* Ideally we have one image that applies to all distros; the install script figures out
  which binary to use based on the host distro & kernel.

* Runs with host mounts of appropriate dirs so it can do its job.

  - Needs to talk to systemd on the host.

  - Needs to talk to k8s on the cluster.

### CRI-O Deployment Container   <<< Not sure if this will work ...

* Install script

* CRI-O binary

* Runs with host mounts of appropriate dirs so it can do its job.

  - Needs to talk to systemd on the host.

  - Needs to configure Kubelet and restart it

### K8s Manifests (yaml)

* RBAC manifest

* Sysbox Deploy manifest

* Sysbox Cleanup manifest

* CRI-O Deploy manifest

* CRI-O Cleanup manifest


## References for sysbox deploy

* Kubevirt installation (requires CRI-O too):

https://kubevirt.io/2019/KubeVirt_k8s_crio_from_scratch.html
https://kubevirt.io/2019/KubeVirt_k8s_crio_from_scratch_installing_kubernetes.html
