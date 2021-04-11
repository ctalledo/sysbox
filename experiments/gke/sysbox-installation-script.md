# K8s Sysbox Installation Script

## Goals

* Make it easy for users to install Sysbox on a host.

* Script may run directly on host

* Script may run inside a daemon-set pod


## Script requirements

* Configurable to select one of these actions:

  * Install sysbox

  * Upgrade existing sysbox installation

  * Remove sysbox


## Sysbox Installation Script

### Installation

* Check if host meets sysbox's requirements (kernel version, etc.)

  - If not, log message and take no action

* Check if sysbox is already installed

  - If it is, no action.

* Install Sysbox

  - Sysbox version should be configurable

  - Add option to download it from web or to install from host dir.

    - The latter will allow us to bundle this script with the sysbox binaries in
      a container that can then be deployed via a K8s daemon set in air-gapped
      environments.

* Configure CRI to use know about sysbox

  - CRI-O: add sysbox-runtime, configure storage opt, restart CRI-O.

### Upgrade

* Check if host meets sysbox's requirements (kernel version, etc.)

  - If not, log message and take no action

* Check if sysbox is already installed

  - If installed, uninstall it

* Install Sysbox (same as installation procedure).

### Removal

* Check if sysbox is already installed

  - If installed, uninstall it


## CRI-O Installation Script

* We should have a separate script for CRI-O installation, upgrade, and removal.

### Installation

* Check if host meets CRI-O's requirements

  - If not, log message and take no action

* Check if CRI-O is already installed

  - If it is, no action.

* Install CRI-O

  - Must match K8s version

  - Add option to download it from web or to install from host dir.

    - The latter will allow us to bundle this script with the CRI-O binaries in
      a container that can then be deployed via a K8s daemon set in air-gapped
      environments.

* Configure Kubelet to use CRI-O

  - Do the config

  - Add config option to restart Kubelet (enabled by default)

### Upgrade

* Check if host meets CRI-O's requirements

  - If not, log message and take no action

* Check if CRI-O is already installed

  - If installed, uninstall it

* Install CRI-O (same as installation procedure).

### Removal

* Check if CRI-O is already installed

  - If installed, uninstall it
