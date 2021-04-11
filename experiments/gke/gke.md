# Notes on GKE + Sysbox

## Cluster Provisioning

* It's pretty easy to privision a GKE cluster via the web-based interface.

* It took ~3 minutes to provision the 3-node basic cluster.

* The GKE cluster has K8s 1.19 by default (as of 04/2021).

```
ctalledo@cloudshell:~ (predictive-fx-309900)$ kubectl version
Client Version: version.Info{Major:"1", Minor:"20", GitVersion:"v1.20.5", GitCommit:"6b1d87acf3c8253c123756b9e61dac642678305f", GitTreeState:"clean", BuildDate:"2021-03-18T01:10:43Z", GoVersion:"go1.15.8", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"19+", GitVersion:"v1.19.8-gke.1600", GitCommit:"4f6f69fd81ca8cb6962a2f7e1ed9c7880834cf71", GitTreeState:"clean", BuildDate:"2021-03-08T19:22:13Z", GoVersion:"go1.15.8b5", Compiler:"gc", Platform:"linux/amd64"}
```

* However, there is a "rapid channel" option that carries K8s 1.20.4.

* The cluster can be upgraded, both the control plane and worker nodes.

  - Upgrade of the control plane took 2-3 minutes.

  - Upgrade of the worker nodes took 6 minutes (2 minutes per node).


## Cluster Access

* Can be done via:

  - Web-based interface

  - Web-based shell

  - Remote kubectl

* For remote access, I installed the `gcloud` tool, as described here: https://cloud.google.com/sdk/docs/install

* Once installed, access the GKE cluster via:

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


## K8s Cluster Nodes

* Nodes are allocated from "node pools".

* Each node pool contains 1 or more nodes of the same type.

### Node Types

* GKE nodes come in several flavors:

  - Container Optimized OS (with Docker or containerd)

  - Ubuntu with Docker

  - Ubuntu with containerd

  - Windows

* I used the container optimized OS first:

```
ctalledo@cloudshell:~ (predictive-fx-309900)$ kubectl get nodes -o wide
NAME                                                STATUS   ROLES    AGE   VERSION            INTERNAL-IP   EXTERNAL-IP      OS-IMAGE                             KERNEL-VERSION   CONTAINER-RUNTIME
gke-my-first-cluster-1-default-pool-381d0f5c-gb4q   Ready    <none>   13m   v1.19.8-gke.1600   10.128.0.2    35.192.79.45     Container-Optimized OS from Google   5.4.89+          docker://19.3.14
gke-my-first-cluster-1-default-pool-381d0f5c-gnl7   Ready    <none>   13m   v1.19.8-gke.1600   10.128.0.4    34.70.253.114    Container-Optimized OS from Google   5.4.89+          docker://19.3.14
gke-my-first-cluster-1-default-pool-381d0f5c-h25j   Ready    <none>   13m   v1.19.8-gke.1600   10.128.0.3    34.123.196.187   Container-Optimized OS from Google   5.4.89+          docker://19.3.14
```

* These carry a GKE specific distro with a 5.4 kernel, so it's likely Sysbox won't work well in them (Sysbox needs ubuntu 5.0+ or 5.5+ otherwise):

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

* Luckily, the "ubuntu with containerd" node carries ubuntu bionic with a 5.4 kernel, so it does work.

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

* These carry Ubuntu Bionic 18.04 with a 5.4 kernel, so they work fine with Sysbox.

### Node access

* By default, each node has an internal and external IP address.

* To ssh into it, I added my dev machine's public ssh key to the
  node's `.ssh/authorized-keys` file.

  - NOTE: I noticed this file is periodically removed from the node by GKE.

  - TODO: figure out how to make this access permanent.

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


## Manually Config of a GKE node with Sysbox

### 1st Attempt: Failed

* I initially chose the "ubuntu + docker" node image, and proceeded to install sysbox in it.

* Problem #1: jq not installed in host; fixed with `apt-get update && apt-get install jq`

* Problem #2: Docker is running containers/pods on the node, so the sysbox installer failed:

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

### 2nd Attempt: Success

* Create a node with k8s + containerd only (no docker)

  - The node comes with crictl installed.

* Installed CRI-O manually (see https://cri-o.io/)

* Installed Sysbox manually via the package installer.

  - This required some fixes in the package installer to decouple of it from the presence of Docker.

* Verified crictl + CRI-O + Sysbox works (optional step I did to check all is well):

  - Had to configure crictl to use CRI-O instead of containerd (`/etc/crictl.yaml`)

  - Had to configure CRI-O:

      - Add Sysbox runtime

      - Use cgroupfs driver

      - Use overlayfs storage driver (without `nodev` option and with `metacopy=on` option)

  - Had to manually install a CNI for CRIO (as done in Sysbox's test-container dockerfile) and restart CRI-O.

    - This required installing Golang on the node, as the CNI was built from scratch.

  - This worked, which means Sysbox-pods fundamentally work on the GKE node (great!).

* Configured the Kubelet to use CRI-O:

  - Modified the kubelet's runtime from containerd -> CRI-O via the `/etc/default/kubelet file` (see [kubelet config](#kubelet-config))

  - Restarted the kubelet service via systemd.

* This worked well:

  - The GKE node remained up

  - GKE relaunched all the control-plane pods with CRI-O once it detected the kubelet restart.

* NOTE: This needs to be done with a daemon-set, as the manual config is not persistent:

  - Per https://cloud.google.com/kubernetes-engine/docs/concepts/node-images):

  "Modifications on the boot disk of a node VM do not persist across node
  re-creations. Nodes are re-created during manual upgrade, auto-upgrade,
  auto-repair, and auto-scaling. In addition, nodes are re-created when you
  enable a feature that requires node re-creation, such as GKE sandbox,
  intranode visibility, and shielded nodes.

  To preserve modifications across node re-creation, use a DaemonSet."

### Deploying Pods with Sysbox

* Add the Sysbox runtime class to K8s.

* Add a label to the K8s node(s) with Sysbox; this way we can direct K8s to deploy the desired pods on those nodes.

```
kubectl label nodes <node-name> runtime=sysbox
```

  See: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/

* Then update the desired pod specs to add the nodeSelector.

```
spec:
 runtimeClassName: sysbox-runc
  containers:
  - name: alpine-docker
    image: ghcr.io/nestybox/alpine-docker
    command: ["tail"]
    args: ["-f", "/dev/null"]
  restartPolicy: Never
 nodeSelector:
    runtime: sysbox
```

* Then simply `kubectl apply` the pod spec and voila, sysbox (rootless) pods on GKE!

```
kubectl apply -f alpine-docker-pod.yaml
```

* I tested the following pods:

  - rootless pods with systemd, docker, and even k8s work!


## Kubelet Config Details

* Done via a systemd service file for kubelet:

```
            ├─kubelet.service
             │ └─2905 /home/kubernetes/bin/kubelet --v=2 --cloud-provider=gce --experimental-check-node-capabilities-before-mount=true --experimental-mounter-path=/home/kubernetes/containerized_mounter/mounter --cert-dir=/var/lib/kubelet/pki/ --cni-bin-dir=/home/kubernetes/bin --kubeconfig=/var/lib/kubelet/kubeconfig
             --image-pull-progress-deadline=5m --max-pods=110 --non-masquerade-cidr=0.0.0.0/0 --network-plugin=kubenet
             --volume-plugin-dir=/home/kubernetes/flexvolume --node-status-max-images=25

             --container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock   <<< NOTE

             --runtime-cgroups=/system.slice/containerd.service --registry-qps=10 --registry-burst=20 --config /home/kubernetes/kubelet-config.yaml --pod-sysctls=net.core.somaxconn=1024, ...
```

* Note: the k8s systemd unit files are here: `/etc/systemd/system`

  - E.g., `/etc/systemd/system/kubelet.service`


* The kubelet service uses the `$KUBELET_OPS` env var to get it's config.

* The `KUBELET_OPTS` env var comes from `/etc/default/kubelet`:

```
$ cat /etc/default/kubelet

KUBELET_OPTS="--v=2 --cloud-provider=gce --experimental-check-node-capabilities-before-mount=true --experimental-mounter-path=/home/kubernetes/containerized_mounter/mounter
--cert-dir=/var/lib/kubelet/pki/ --cni-bin-dir=/home/kubernetes/bin --kubeconfig=/var/lib/kubelet/kubeconfig --image-pull-progress-deadline=5m --max-pods=110
--non-masquerade-cidr=0.0.0.0/0 --network-plugin=kubenet --volume-plugin-dir=/home/kubernetes/flexvolume --node-status-max-images=25
--container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock --runtime-cgroups=/system.slice/containerd.service
--registry-qps=10 --registry-burst=20 --config /home/kubernetes/kubelet-config.yaml --pod-sysctls='net.core.somaxconn=1024,net.ipv4.conf.all.accept_redirects=0,net.ipv4.conf.all.forwarding=1,net.ipv4.conf.all.route_localnet=1,net.ipv4.conf.default.forwarding=1,net.ipv4.ip_forward=1,net.ipv4.tcp_fin_timeout=60,net.ipv4.tcp_keepalive_intvl=60,net.ipv4.tcp_keepalive_probes=5,net.ipv4.tcp_keepalive_time=300,net.ipv4.tcp_rmem=4096 87380 6291456,net.ipv4.tcp_syn_retries=6,net.ipv4.tcp_tw_reuse=0,net.ipv4.tcp_wmem=4096 16384 4194304,net.ipv4.udp_rmem_min=4096,net.ipv4.udp_wmem_min=4096,net.ipv6.conf.default.accept_ra=0,net.netfilter.nf_conntrack_generic_timeout=600,net.netfilter.nf_conntrack_tcp_be_liberal=1,net.netfilter.nf_conntrack_tcp_timeout_close_wait=3600,net.netfilter.nf_conntrack_tcp_timeout_established=86400'"

KUBE_COVERAGE_FILE="/var/log/kubelet.cov"
```

* I changed it to CRI-O with this `sed`:

```
sudo sed -i 's@--container-runtime-endpoint=unix:///run/containerd/containerd.sock@--container-runtime-endpoint=unix:///run/crio/crio.sock@g' /etc/default/kubelet
sudo sed -i 's@--runtime-cgroups=/system.slice/containerd.service@--runtime-cgroups=/system.slice/crio.service@g' /etc/default/kubelet
```

* Then restarted kubelet: `sudo systemctl restart kubelet`

* After restart, `journalctl -xeu kubelet` shows some errors:

```
Apr 09 22:04:15 gke-my-first-cluster-1-pool-1-fdd5037a-4jp3 kubelet[700121]: E0409 22:04:15.646242  700121 cri_stats_provider.go:376] Failed to get the info of the filesystem with mountpoint "/var/lib/containers/storage/overlay-images": unable to find data in memory cache.
Apr 09 22:04:15 gke-my-first-cluster-1-pool-1-fdd5037a-4jp3 kubelet[700121]: E0409 22:04:15.646556  700121 kubelet.go:1298] Image garbage collection failed once. Stats initialization may not have completed yet: invalid capacity 0 on image filesystem
...
Apr 09 22:04:15 gke-my-first-cluster-1-pool-1-fdd5037a-4jp3 kubelet[700121]: E0409 22:04:15.807149  700121 kubelet.go:1859] skipping pod synchronization - [container runtime status check may not have completed yet, PLEG is not healthy: pleg has yet to be successful]
Apr 09 22:04:15 gke-my-first-cluster-1-pool-1-fdd5037a-4jp3 kubelet[700121]: E0409 22:04:15.907380  700121 kubelet.go:1859] skipping pod synchronization - container runtime status check may not have completed yet
...
Apr 09 22:04:16 gke-my-first-cluster-1-pool-1-fdd5037a-4jp3 kubelet[700121]: E0409 22:04:16.140583  700121 kubelet.go:1668] Failed creating a mirror pod for "kube-proxy-gke-my-first-cluster-1-pool-1-fdd5037a-4jp3_kube-system(e1c28e4de3e00ff2b69cf4cae0c60786)": pods "kube-proxy-gke-my-first-cluster-1-pool-1-fdd5037a-4
```

* But things look good:

```
ctalledo@gke-my-first-cluster-1-pool-1-fdd5037a-4jp3:/etc/default$ sudo crictl ps
CONTAINER           IMAGE                                                                                                                       CREATED             STATE               NAME                   ATTEMPT             POD ID
01c2340a67b76       gke.gcr.io/gcp-compute-persistent-disk-csi-driver@sha256:e9e3a3af496e330d473b7c5c42958de4ebc1c17fbbb311360b7ecdf7b28e1c93   7 minutes ago       Running             gce-pd-driver          0                   59b474116c2ae
059b6746a08bd       gke.gcr.io/kube-proxy-amd64@sha256:9780756c79898c2d28b9fe1bda004e33a525969a1abc78da88ed4311d01f38ed                         7 minutes ago       Running             kube-proxy             0                   51681316eea5b
31bf8a5121b14       gke.gcr.io/proxy-agent-amd64@sha256:ce92d6924c818a0d53273f941d603aa550718364233bdf7b12d2736352b3fde9                        7 minutes ago       Running             konnectivity-agent     0                   984e5033d247f
323ac372b2bd9       gke.gcr.io/csi-node-driver-registrar@sha256:877ecfbb4119d63e83a45659044d128326f814ae1091b5630e236930a50b741d                7 minutes ago       Running             csi-driver-registrar   0                   59b474116c2ae
```

* Kubectl confirms the node is healthy:

```
ctalledo@cloudshell:~ (predictive-fx-309900)$ kubectl get nodes
NAME                                                STATUS   ROLES    AGE     VERSION
gke-my-first-cluster-1-default-pool-381d0f5c-6184   Ready    <none>   3d18h   v1.20.4-gke.2200
gke-my-first-cluster-1-default-pool-381d0f5c-823q   Ready    <none>   3d18h   v1.20.4-gke.2200
gke-my-first-cluster-1-default-pool-381d0f5c-fmz7   Ready    <none>   3d18h   v1.20.4-gke.2200
gke-my-first-cluster-1-pool-1-fdd5037a-4jp3         Ready    <none>   2d16h   v1.20.4-gke.2200
```

### Dynamic kubelet config

* k8s formally supports reconfiguring the kubelet dynamically, though I did not
  use it. I am noting this down for reference only.

* Info on this here:

  https://kubernetes.io/docs/tasks/administer-cluster/reconfigure-kubelet/

*  The following kubelet configuration parameters can be changed dynamically:

   https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/

   NOTE: I don't see the `--container-runtime-endpoint` in there :(

* For each node that you're reconfiguring, you must set the kubelet
  --dynamic-config-dir flag to a writable directory.

* The new configuration completely overrides configuration provided by --config,
  and is overridden by command-line flags.  <<< THE LATTER MAY BE A PROBLEM FOR
  CONFIGURING KUBELET WITH CRI-O, BECAUSE THE CMD LINE IS POINTING KUBELET TO
  CONTAINERD


## Node Health Monitoring

* Check status from kubectl:

```
kubectl get node <node> -o json | jq ".status"
```

* Each k8s node has a kubelet-monitor service:

```
             ├─kube-container-runtime-monitor.service
             │ ├─  3009 bash /home/kubernetes/bin/health-monitor.sh container-runtime
```

* There is also a comprehensive "node problem detector":

```
     ├─node-problem-detector.service
             │ └─2939 /home/kubernetes/bin/node-problem-detector --v=2 --logtostderr --config.system-log-monitor=/home/kubernetes/node-problem-detector/config/kernel-monitor.json,/home/kubernetes/node-problem-detector/config/docker-monitor.json,/home/kubernetes/node-problem-detector/config/systemd-monitor.json --conf
```


## Installing Shiftfs (required if doing volume mounts into the Sysbox pods)

* Dependencies:

`make, dkms`

* Procedure to build and install the shiftfs module:

```
git clone -b k5.4 https://github.com/toby63/shiftfs-dkms.git shiftfs-k54
cd shiftfs-k54
./update1
sudo make -f Makefile.dkms
echo shiftfs | sudo tee /etc/modules-load.d/shiftfs.conf
sudo modprobe shiftfs
```


## Issues

### Issue #1: Deploying a sysbox pod fails [FIXED - sysbox-pods branch]

```
Apr 09 22:47:04 gke-my-first-cluster-1-pool-1-fdd5037a-4jp3 kubelet[700121]: I0409 22:47:04.807429  700121 kuberuntime_sandbox.go:64] Running pod alpine-docker_default(f6070b2f-88e0-47e6-a91c-a618ce787dd9) with RuntimeHandler "sysbox-runc"
Apr 09 22:47:06 gke-my-first-cluster-1-pool-1-fdd5037a-4jp3 kubelet[700121]: E0409 22:47:06.164212  700121 remote_runtime.go:116] RunPodSandbox from runtime service failed: rpc error: code = Unknown desc = container create failed: time="2021-04-09T22:47:06Z"
   level=error msg="container_linux.go:394: starting container process caused: process_linux.go:592: container init caused: write sysctl key net.netfilter.nf_conntrack_generic_timeout: open /proc/sys/net/netfilter/nf_conntrack_generic_timeout: no such file or directory"
```

* The reason is that k8s is setting up the pod such that it writes to `/proc/sys/net/netfilter/nf_conntrack_generic_timeout`,
  but this resource is not available inside a sysbox-pod (not exposed inside the user-ns).

* FIX: add handler to sysbox-fs.

### Issue #2: [FIXED - sysbox-pods branch]

```
Apr 09 23:16:56 gke-my-first-cluster-1-pool-1-fdd5037a-4jp3 kubelet[700121]: I0409 23:16:56.806702  700121 kuberuntime_sandbox.go:64] Running pod alpine-docker_default(9d2b470c-ef6b-48b2-b3b9-8ba53a9829ad) with RuntimeHandler "sysbox-runc"
Apr 09 23:16:57 gke-my-first-cluster-1-pool-1-fdd5037a-4jp3 kubelet[700121]: E0409 23:16:57.930769  700121 remote_runtime.go:116] RunPodSandbox from runtime service failed: rpc error: code = Unknown desc = container create failed: time="2021-04-09T23:16:57Z" level=error msg="container_linux.go:394: starting container process caused: process_linux.go:592: container init caused: write sysctl key net.core.somaxconn: open /proc/sys/net/core/somaxconn: no such file or directory"
```

* Same as issue #1 but on `/proc/sys/net/core/somaxconn`.

* In fact, here are all the sysctls that k8s wants to configure by default:

```
net.core.somaxconn=1024,                       <<< NEEDS EMULATION [FIXED - sysbox-pods branch]
net.ipv4.conf.all.accept_redirects=0,
net.ipv4.conf.all.forwarding=1,
net.ipv4.conf.all.route_localnet=1,
net.ipv4.conf.default.forwarding=1,
net.ipv4.ip_forward=1,
net.ipv4.tcp_fin_timeout=60,
net.ipv4.tcp_keepalive_intvl=60,
net.ipv4.tcp_keepalive_probes=5,
net.ipv4.tcp_keepalive_time=300,
net.ipv4.tcp_rmem=4096 87380 6291456,
net.ipv4.tcp_syn_retries=6,
net.ipv4.tcp_tw_reuse=0,
net.ipv4.tcp_wmem=4096 16384 4194304,
net.ipv4.udp_rmem_min=4096,
net.ipv4.udp_wmem_min=4096,
net.ipv6.conf.default.accept_ra=0,
net.netfilter.nf_conntrack_generic_timeout=600,
net.netfilter.nf_conntrack_tcp_be_liberal=1,                   <<< NEEDS EMULATION [FIXED - sysbox-pods branch]
net.netfilter.nf_conntrack_tcp_timeout_close_wait=3600,
net.netfilter.nf_conntrack_tcp_timeout_established=86400'
```

### Issue #3

* sysbox-mgr log shows this error on a gke node:

```
time="2021-04-10 00:48:50" level=warning msg="failed to get image id for container 7f0c683552bf4cdbc57f50ceec1c38b98fc29e06fb45c9f1ed6bd6b518f8642a: failed to retrieve Docker info: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?"
```

* There is no docker daemon running on the node, so this is expected.

* Looks related to inner docker image sharing.


## GKE + Sysbox Setup Summary

* Use K8s nodes based on the "Ubuntu with containerd" option

  - These carry Ubuntu Bionic with a 5.4 kernel, thus meeting Sysbox's requirements.

* Install CRI-O

* Install Sysbox

* Configure Kubelet to use CRI-O

* Add the K8s runtime class for sysbox

* Label the node(s) with Sysbox

* Deploy the pod


## TODO

* Review and cleanup the notes [DONE]

* Complete GKE + Sysbox summary section [DONE]

* Write down Sysbox on GKE installation guide [IN-PROG]

  - Needs spell-check and remark TOC.

* Write down Sysbox on K8s installation guide

  - Same as for GKE but for a non-managed K8s cluster.


* Modify the sysbox installer to install correctly even if docker containers are running.

  - This way sysbox can install on the "ubuntu with docker" nodes, where it's
    certain that docker containers will be running as K8s uses Docker to create
    pods for control-plane components.

* Modify the sysbox installer to not ask any questions.

  - This will allow us to automate the process (e.g., have a daemonSet to the installation).

* Have the sysbox installer check that the config it's doing for docker does not collide with the docker systemd service command line.

  - Otherwise we hit an error such as: `Apr 07 00:23:07 gke-my-first-cluster-1-pool-1-90e66ff8-dmmk dockerd[135412]: unable to configure the Docker daemon with file /etc/docker/daemon.json: the following directives are specified both as a flag and in the configuration file: bip: (from flag: 169.254.123.1/24, from file: 172.20.0.1/16)`

* Fix this sysbox-mgr issue: sysbox-mgr log shows this error on a gke node:

```
time="2021-04-10 00:48:50" level=warning msg="failed to get image id for container 7f0c683552bf4cdbc57f50ceec1c38b98fc29e06fb45c9f1ed6bd6b518f8642a: failed to retrieve Docker info: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?"
```

* Come up with fix for volume mount ownership problem

  - Maybe load shiftfs into kernel (for ubuntu)  <<< only good solution now

  - Or use id mapped mounts (kernel 5.12+)  <<< future solution

  - Or have option for sysbox to chown  <<< not viable (can't share files with host)

  - Or ask users to enable "other" permissions (too lax)  <<< not secure.


* Create a daemon-set to automate the config

  - First write a script that does this on a bare-metal host

  - Then containerize that script

    - Include deps to build and install shiftfs (if running on ubuntu)

  - Then create the daemon set spec (with th require host dir mounts)




## References

* Installing CRI-O and configuring K8s to use it: https://medium.com/cloudlego/using-cri-o-as-container-runtime-for-kubernetes-b8ddf8326d38
