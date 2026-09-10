# syntax=docker/dockerfile:1.7
# ==========================================================
# Hardened build — same tooling, same entrypoint.
# Changes are security-only: pinned versions, no remote
# script execution, OS package upgrade, cache cleanup.
# ==========================================================

# ---------- Base images (override to point at Artifactory) ----------
ARG REGISTRY=docker.io
ARG ALPINE_TAG=3.22
# 28.0.1 shipped dockerd/runc built with Go 1.23.6 -> 15 open stdlib CVEs in Trivy.
# Needs a dind built with Go >= 1.24.9 (CVE-2025-58187 is the highest bar).
# Avoid 29.7.0 (known archive-extraction regression). Verify the tag exists in
# Artifactory and re-scan before locking. Conservative alt: ARG DIND_TAG=28.5.2-dind
ARG DIND_TAG=29.8.0-dind
ARG CT_IMAGE=quay.io/helmpack/chart-testing:v3.14.0
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.12.10

# Named stages for every external image, so all of them are overridable for
# the air-gapped build, e.g.:
#   --build-arg REGISTRY=artifactory.corp/docker-remote \
#   --build-arg CT_IMAGE=artifactory.corp/quay-remote/helmpack/chart-testing:v3.14.0 \
#   --build-arg UV_IMAGE=artifactory.corp/ghcr-remote/astral-sh/uv:0.12.10
# For full reproducibility pin by digest instead of tag: docker:29.8.0-dind@sha256:...
FROM ${REGISTRY}/library/docker:${DIND_TAG} AS dind
FROM ${CT_IMAGE} AS ct
FROM ${UV_IMAGE} AS uv


# ==========================================================
# Stage 1: Binaries Downloader & Builder
# ==========================================================
FROM ${REGISTRY}/library/alpine:${ALPINE_TAG} AS builder

# -e + pipefail: a failing curl in a "curl | tar" pipe now fails the build
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN apk upgrade --no-cache && \
    apk add --no-cache --upgrade curl wget tar unzip bash ca-certificates

WORKDIR /downloads

# ---------- Pinned tool versions (single place to bump) ----------
ARG JFR_VERSION=1.0-beta-32
ARG ORAS_VERSION=1.3.4
ARG KUBESEAL_VERSION=0.39.1
ARG K9S_VERSION=0.51.0
ARG ARGOCD_VERSION=2.13.9
ARG STERN_VERSION=1.34.0
ARG KUBECTX_VERSION=0.11.0
ARG KUSTOMIZE_VERSION=5.8.1
ARG JCLI_VERSION=0.0.47
ARG HELMIFY_VERSION=0.4.20
ARG JFROG_CLI_VERSION=2.123.0
ARG RANCHER_VERSION=2.11.9
ARG HELM_VERSION=3.21.4
ARG KUBECTL_VERSION=1.31.0
ARG YQ_VERSION=4.53.4

# Hardened curl defaults: HTTPS only, modern TLS, retry, fail on HTTP error
ENV CURL_OPTS="--proto =https --tlsv1.2 -fsSL --retry 3 --retry-delay 2 --max-time 600"

RUN mkdir -p /out/bin /out/jfr



# 2. Jenkins CLI (jcli)
RUN curl ${CURL_OPTS} "https://github.com/jenkins-zh/jenkins-cli/releases/download/v${JCLI_VERSION}/jcli-linux-amd64.tar.gz" \
      | tar -xz -C /out/bin

# 3. Jenkinsfile Runner
RUN curl ${CURL_OPTS} -o /tmp/jfr.zip "https://github.com/jenkinsci/jenkinsfile-runner/releases/download/${JFR_VERSION}/jenkinsfile-runner-${JFR_VERSION}.zip" && \
    unzip -q /tmp/jfr.zip -d /out/jfr && rm -f /tmp/jfr.zip

# 4. JFrog CLI 
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl ${CURL_OPTS} -o /out/bin/jf \
      "https://releases.jfrog.io/artifactory/jfrog-cli/v2-jf/${JFROG_CLI_VERSION}/jfrog-cli-linux-${ARCH}/jf"


# 8. Kubernetes tooling
#RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
#    ARCH_RAW=$(uname -m) && \
#    curl ${CURL_OPTS} "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-${ARCH}.tar.gz" | tar -xz -C /out/bin kubeseal && \
#    curl ${CURL_OPTS} "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz" | tar -xz -C /out/bin k9s && \
#    curl ${CURL_OPTS} -o /out/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-${ARCH}" && \
#    curl ${CURL_OPTS} "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_${ARCH}.tar.gz" | tar -xz -C /out/bin stern && \
#    curl ${CURL_OPTS} "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${ARCH}.tar.gz" | tar -xz -C /out/bin kustomize && \
#    curl ${CURL_OPTS} "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubectx_v${KUBECTX_VERSION}_linux_${ARCH_RAW}.tar.gz" | tar -xz -C /out/bin kubectx && \
#    curl ${CURL_OPTS} "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubens_v${KUBECTX_VERSION}_linux_${ARCH_RAW}.tar.gz" | tar -xz -C /out/bin kubens
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl ${CURL_OPTS} "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz" | tar -xz -C /out/bin k9s

# 7. Helm (HELM_VERSION was declared but helm was never installed -- and `ct` needs it.
#    Drop this block if leaving helm out was intentional.)
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl ${CURL_OPTS} "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz" \
      | tar -xz --strip-components=1 -C /out/bin "linux-${ARCH}/helm"

# 9. Kubectl, yq (Moved from Alpine apk since they are not in Ubuntu apt repos)
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl ${CURL_OPTS} -o /out/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" && \
    curl ${CURL_OPTS} -o /out/bin/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH}"

RUN chmod 0755 /out/bin/* /out/jfr/bin/jenkinsfile-runner

# Sanity check
RUN /out/bin/jf --version >/dev/null && \
    /out/bin/kubectl version --client >/dev/null && \
    /out/bin/helm version --short >/dev/null && \
    /out/bin/yq --version >/dev/null

# ==========================================================
# Stage 2: Final Production Image (Ubuntu based for manylinux)
# ==========================================================
FROM ${REGISTRY}/library/ubuntu:24.04

LABEL org.opencontainers.image.title="devops-jenkinsfile-runner" \
      org.opencontainers.image.description="Jenkinsfile Runner + K8s/Helm/GitOps toolchain" \
      org.opencontainers.image.base.name="ubuntu:24.04"

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# ----------------------------------------------------------
# PRESERVE DIND CAPABILITIES:
# Copy statically compiled Docker daemon, cli and scripts directly from official dind.
# ----------------------------------------------------------
COPY --from=dind /usr/local/bin/ /usr/local/bin/

# Copy external binary tools (from the ARG-driven stages -- the hardcoded
# quay.io/ghcr.io refs ignored ${CT_IMAGE}/${UV_IMAGE} and broke the air-gapped build)
COPY --from=ct /usr/local/bin/ct /usr/local/bin/ct
COPY --from=uv /uv /bin/

# Copy all pre-downloaded binaries from builder stage
COPY --from=builder /out/bin/ /usr/local/bin/
COPY --from=builder /out/jfr /opt/jfr

ENV JAVA_HOME=/usr \
    JENKINS_HOME=/opt/jenkins \
    PATH="/opt/jfr/bin:${PATH}" \
    CURL_OPTS="--proto =https --tlsv1.2 -fsSL --retry 3 --retry-delay 2 --max-time 600" \
    DEBIAN_FRONTEND=noninteractive \
    PIP_BREAK_SYSTEM_PACKAGES=1

# Install base OS packages via apt (Ubuntu). Includes DinD prerequisites.
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    git git-lfs bash tcsh curl sudo python3 python3-pip python3-venv iputils-ping tcpdump \
    wget skopeo zip util-linux jq vim nano podman podman-compose fuse-overlayfs openjdk-21-jre-headless \
    unzip tar fonts-dejavu-core npm sshpass openssh-client openssh-server \
    iptables openssl uidmap xfsprogs xz-utils pigz btrfs-progs e2fsprogs kmod ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Python and NPM packages
# Thanks to Ubuntu's glibc, pip will now identify the system correctly and pull manylinux wheels!
# uv resolves and installs on its own -- seeding pip/setuptools/wheel into these
# prefixes was dead weight. `npm audit fix` was rewriting the pinned dependency
# tree at build time and `|| true` swallowed every failure: both removed.
RUN uv pip install --system --no-cache --prefix=/opt/mcp-atlassian mcp-atlassian==0.23.1 && \
    uv pip install --system --no-cache --prefix=/opt/jenkins-mcp mcp-jenkins==3.5.0 && \
    npm install -g --prefix=/opt/gitlab-mcp "@structured-world/gitlab-mcp@9.1.2" && \
    npm cache clean --force && \
    rm -rf /root/.cache /root/.npm /tmp/*

# ---------- Jenkins WAR + plugins ----------
ARG JENKINS_VERSION=2.568.2

# TODO: replace every `:latest` with the exact version from /opt/jenkins/plugins.lock
# (written by the build below). `:latest` makes this image non-reproducible and
# is an unreviewed supply-chain entry point in an image labelled "Hardened".
ARG JENKINS_PLUGINS="\
    workflow-aggregator:latest \
    workflow-job:latest \
    workflow-cps:latest \
    workflow-basic-steps:latest \
    workflow-durable-task-step:latest \
    workflow-step-api:latest \
    workflow-support:latest \
    script-security:latest \
    git:latest \
    git-client:latest"

RUN mkdir -p ${JENKINS_HOME}/plugins && \
    curl ${CURL_OPTS} -o ${JENKINS_HOME}/jenkins.war \
      "https://get.jenkins.io/war-stable/${JENKINS_VERSION}/jenkins.war" && \
    for p in ${JENKINS_PLUGINS}; do \
        name="${p%%:*}"; ver="${p##*:}"; \
        if [ "$ver" = "latest" ]; then \
            url="https://updates.jenkins.io/latest/${name}.hpi"; \
        else \
            url="https://updates.jenkins.io/download/plugins/${name}/${ver}/${name}.hpi"; \
        fi; \
        curl ${CURL_OPTS} -o "${JENKINS_HOME}/plugins/${name}.hpi" "$url"; \
    done && \
    for f in ${JENKINS_HOME}/plugins/*.hpi; do \
        n=$(basename "$f" .hpi); \
        v=$(unzip -p "$f" META-INF/MANIFEST.MF | tr -d '\r' | awk -F': ' '/^Plugin-Version:/{print $2}'); \
        echo "${n}:${v}"; \
    done > ${JENKINS_HOME}/plugins.lock && \
    cat ${JENKINS_HOME}/plugins.lock


# Final cleanup: no build caches, no leftover archives in the image
RUN rm -rf /root/.cache /root/.npm /tmp/* /var/tmp/*

RUN curl -fsSL https://github.com/rancher/cli/releases/download/v${RANCHER_VERSION}/rancher-linux-amd64-v${RANCHER_VERSION}.tar.gz \
    -o /tmp/rancher-cli.tar.gz \
    && tar -xzf /tmp/rancher-cli.tar.gz -C /tmp \
    && mv /tmp/rancher-v${RANCHER_VERSION}/rancher /usr/local/bin/rancher \
    && chmod +x /usr/local/bin/rancher \
    && rm -rf /tmp/rancher*
RUN rancher --version
ENTRYPOINT ["jenkinsfile-runner", "-w", "/opt/jenkins", "-f", "/workspace/Jenkinsfile", "-p", "/opt/jenkins/plugins", "--workspace", "/workspace"]
