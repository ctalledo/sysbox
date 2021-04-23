#
# Docker image for deploying Sysbox on a K8s host.
#
# Note: centos carries a systemctl that can communicate with the host's systemd
# via dbus. This this not work when using a ubuntu + systemd image (systemctl
# could not connect to the host's dbus, even though it was mounted into the
# container).

FROM centos/systemd

ARG DEST=/opt/sysbox

RUN yum install -y curl wget

RUN curl -Lso /bin/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && \
    chmod +x /bin/kubectl

# Dasl (for yaml, toml, json parsing) (https://github.com/TomWright/dasel)
RUN curl -s https://api.github.com/repos/tomwright/dasel/releases/latest | \
    grep browser_download_url | \
    grep linux_amd64 | \
    cut -d '"' -f 4 | \
    wget -qi - && mv dasel_linux_amd64 dasel && chmod +x dasel && mv ./dasel /usr/local/bin/dasel

# Sysbox artifacts
COPY bin ${DEST}/bin
COPY systemd ${DEST}/systemd
COPY scripts ${DEST}/scripts
COPY config ${DEST}/config
