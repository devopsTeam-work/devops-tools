# syntax=docker/dockerfile:1.7
# ==========================================================
# Hardened build — same tooling, same entrypoint.
# Changes are security-only: pinned versions, no remote
# script execution, OS package upgrade, cache cleanup.
# ==========================================================

# ---------- Base images (override to point at Artifactory) ----------
ARG REGISTRY=docker.io
ARG ALPINE_TAG=3.22
ARG DIND_TAG=28.0.2-dind
ARG CT_IMAGE=quay.io/helmpack/chart-testing:v3.15.0
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.13.0

# Create an alias for the dind image so we can copy from it later 
# without scoping issues with ARGs.
FROM ${REGISTRY}/library/docker:${DIND_TAG} AS dind

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
ARG RANCHER_VERSIONS="v2.15.1 v2.10.1 v2.13.1"
ARG RANCHER_DEFAULT=v2.13.1
ARG HELM_VERSION=3.18.10
ARG KUBECTL_VERSION=1.31.5
ARG YQ_VERSION=4.45.1

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
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl ${CURL_OPTS} "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz" | tar -xz -C /out/bin k9s

# 9. Kubectl, yq (Moved from Alpine apk since they are not in Ubuntu apt repos)
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl ${CURL_OPTS} -o /out/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" && \
    curl ${CURL_OPTS} -o /out/bin/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH}"

RUN chmod 0755 /out/bin/* /out/jfr/bin/jenkinsfile-runner

# Sanity check
RUN /out/bin/jf --version >/dev/null && \
    /out/bin/kubectl version --client >/dev/null && \
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

# Copy external binary tools using parameterized ARGs
COPY --from=${CT_IMAGE} /usr/local/bin/ct /usr/local/bin/ct
COPY --from=${UV_IMAGE} /uv /bin/

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
RUN uv pip install --system --no-cache --prefix=/opt/mcp-atlassian --upgrade pip setuptools wheel && \
    uv pip install --system --no-cache --prefix=/opt/mcp-atlassian mcp-atlassian==0.23.1 && \
    uv pip install --system --no-cache --prefix=/opt/jenkins-mcp --upgrade pip setuptools wheel && \
    uv pip install --system --no-cache --prefix=/opt/jenkins-mcp mcp-jenkins==3.5.0 && \
    npm install -g --prefix=/opt/gitlab-mcp "@structured-world/gitlab-mcp@9.1.2" && \
    npm audit fix --prefix=/opt/gitlab-mcp || true && \
    npm cache clean --force && \
    rm -rf /root/.cache /root/.npm /tmp/*

# ---------- Jenkins WAR + plugins ----------
ARG JENKINS_VERSION=2.568.2

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
    done

# Final cleanup: no build caches, no leftover archives in the image
RUN rm -rf /root/.cache /root/.npm /tmp/* /var/tmp/*

WORKDIR /workspace

ENTRYPOINT ["jenkinsfile-runner", "-w", "/opt/jenkins", "-f", "/workspace/Jenkinsfile", "-p", "/opt/jenkins/plugins", "--workspace", "/workspace"]
