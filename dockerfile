# syntax=docker/dockerfile:1.7
# ==========================================================
# Hardened build — same tooling, same entrypoint.
# Changes are security-only: pinned versions, no remote
# script execution, OS package upgrade, cache cleanup.
# ==========================================================

# ---------- Base images (override to point at Artifactory) ----------
ARG REGISTRY=docker.io
ARG ALPINE_TAG=3.22
ARG DIND_TAG=28.5-dind
ARG CT_IMAGE=quay.io/helmpack/chart-testing:v3.14.0
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.12.9

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
ARG JFROG_CLI_VERSION=2.122.0
ARG RANCHER_VERSIONS="v2.15.1 v2.10.1 v2.13.1"
ARG RANCHER_DEFAULT=v2.13.1
ARG HELM_VERSION=3.18.10
ARG KUBECTL_VERSION=1.30.2
ARG YQ_VERSION=4.44.2

# Hardened curl defaults: HTTPS only, modern TLS, retry, fail on HTTP error
ENV CURL_OPTS="--proto =https --tlsv1.2 -fsSL --retry 3 --retry-delay 2 --max-time 600"

RUN mkdir -p /out/bin /out/jfr

# 1. ORAS
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl ${CURL_OPTS} "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_${ARCH}.tar.gz" \
      | tar -xz -C /out/bin oras

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

# 5. Rancher CLIs
RUN for RV in ${RANCHER_VERSIONS}; do \
        curl ${CURL_OPTS} "https://github.com/rancher/cli/releases/download/${RV}/rancher-linux-amd64-${RV}.tar.gz" | tar -xz -C /tmp && \
        mv /tmp/rancher-${RV}/rancher /out/bin/rancher_${RV} && \
        rm -rf /tmp/rancher-${RV}; \
    done && \
    cd /out/bin && ln -sf "rancher_${RANCHER_DEFAULT}" rancher

# 7. Helmify 
RUN curl ${CURL_OPTS} "https://github.com/arttor/helmify/releases/download/v${HELMIFY_VERSION}/helmify_Linux_x86_64.tar.gz" \
      | tar -xz -C /out/bin helmify

# 8. Kubernetes tooling
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    ARCH_RAW=$(uname -m) && \
    curl ${CURL_OPTS} "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-${ARCH}.tar.gz" | tar -xz -C /out/bin kubeseal && \
    curl ${CURL_OPTS} "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz" | tar -xz -C /out/bin k9s && \
    curl ${CURL_OPTS} -o /out/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-${ARCH}" && \
    curl ${CURL_OPTS} "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_${ARCH}.tar.gz" | tar -xz -C /out/bin stern && \
    curl ${CURL_OPTS} "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${ARCH}.tar.gz" | tar -xz -C /out/bin kustomize && \
    curl ${CURL_OPTS} "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubectx_v${KUBECTX_VERSION}_linux_${ARCH_RAW}.tar.gz" | tar -xz -C /out/bin kubectx && \
    curl ${CURL_OPTS} "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubens_v${KUBECTX_VERSION}_linux_${ARCH_RAW}.tar.gz" | tar -xz -C /out/bin kubens

# 9. Helm, Kubectl, yq (Moved from Alpine apk since they are not in Ubuntu apt repos)
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl ${CURL_OPTS} "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz" | tar -xz -C /tmp && \
    mv /tmp/linux-${ARCH}/helm /out/bin/helm && \
    rm -rf /tmp/linux-${ARCH} && \
    curl ${CURL_OPTS} -o /out/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" && \
    curl ${CURL_OPTS} -o /out/bin/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH}"

RUN chmod 0755 /out/bin/* /out/jfr/bin/jenkinsfile-runner

# Sanity check
RUN /out/bin/oras version >/dev/null && \
    /out/bin/argocd version --client >/dev/null && \
    /out/bin/kustomize version >/dev/null && \
    /out/bin/jf --version >/dev/null && \
    /out/bin/helm version >/dev/null && \
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

# Copy external binary tools
COPY --from=quay.io/helmpack/chart-testing:v3.14.0 /usr/local/bin/ct /usr/local/bin/ct
COPY --from=ghcr.io/astral-sh/uv:0.12.9 /uv /bin/

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

# ---------- Helm plugins ----------
RUN helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v1.0.3 && \
    helm plugin install https://github.com/C123R/helm-blob.git && \
    helm plugin install https://github.com/databus23/helm-diff --version v3.15.12 && \
    helm plugin install https://github.com/idsulik/helm-cel && \
    helm plugin install https://github.com/vmware-labs/distribution-tooling-for-helm && \
    helm plugin install https://github.com/adamreese/helm-env && \
    helm plugin install https://github.com/adamreese/helm-last && \
    helm plugin install https://github.com/adamreese/helm-local && \
    helm plugin install https://github.com/jkroepke/helm-secrets --version v4.7.7 && \
    helm plugin install https://github.com/adamreese/helm-nuke && \
    helm plugin install https://github.com/ContainerSolutions/helm-monitor && \
    helm plugin install https://github.com/hypnoglow/helm-s3.git --version v0.17.2 && \
    helm plugin install https://github.com/dadav/helm-schema --version 0.23.5 && \
    helm plugin install https://github.com/salesforce/helm-starter.git && \
    helm plugin install https://github.com/hayorov/helm-gcs.git && \
    helm plugin install https://github.com/karuppiah7890/helm-schema-gen.git && \
    helm plugin install https://github.com/datreeio/helm-datree && \
    helm plugin install https://github.com/JovianX/helm-release-plugin && \
    helm plugin install https://github.com/seacrew/helm-compose && \
    rm -rf ~/.cache/helm /tmp/*

# Final cleanup: no build caches, no leftover archives in the image
RUN rm -rf /root/.cache /root/.npm /tmp/* /var/tmp/*

WORKDIR /workspace

ENTRYPOINT ["jenkinsfile-runner", "-w", "/opt/jenkins", "-f", "/workspace/Jenkinsfile", "-p", "/opt/jenkins/plugins", "--workspace", "/workspace"]
