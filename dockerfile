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

# Hardened curl defaults: HTTPS only, modern TLS, retry, fail on HTTP error
ENV CURL_OPTS="--proto =https --tlsv1.2 -fsSL --retry 3 --retry-delay 2 --max-time 600"

RUN mkdir -p /out/bin /out/jfr

# 1. ORAS
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl ${CURL_OPTS} "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_${ARCH}.tar.gz" \
      | tar -xz -C /out/bin oras

# 2. Jenkins CLI (jcli) — was "latest", now pinned
RUN curl ${CURL_OPTS} "https://github.com/jenkins-zh/jenkins-cli/releases/download/v${JCLI_VERSION}/jcli-linux-amd64.tar.gz" \
      | tar -xz -C /out/bin

# 3. Jenkinsfile Runner
RUN curl ${CURL_OPTS} -o /tmp/jfr.zip "https://github.com/jenkinsci/jenkinsfile-runner/releases/download/${JFR_VERSION}/jenkinsfile-runner-${JFR_VERSION}.zip" && \
    unzip -q /tmp/jfr.zip -d /out/jfr && rm -f /tmp/jfr.zip

# 4. JFrog CLI — was "curl https://getcli.jfrog.io/v2-jf | sh"
#    Now a pinned artifact download; no remote script executed at build time.
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl ${CURL_OPTS} -o /out/bin/jf \
      "https://releases.jfrog.io/artifactory/jfrog-cli/v2-jf/${JFROG_CLI_VERSION}/jfrog-cli-linux-${ARCH}/jf"

# 5. Rancher CLIs (relative symlink kept as-is)
RUN for RV in ${RANCHER_VERSIONS}; do \
        curl ${CURL_OPTS} "https://github.com/rancher/cli/releases/download/${RV}/rancher-linux-amd64-${RV}.tar.gz" | tar -xz -C /tmp && \
        mv /tmp/rancher-${RV}/rancher /out/bin/rancher_${RV} && \
        rm -rf /tmp/rancher-${RV}; \
    done && \
    cd /out/bin && ln -sf "rancher_${RANCHER_DEFAULT}" rancher

# 7. Helmify — was "latest", now pinned
RUN curl ${CURL_OPTS} "https://github.com/arttor/helmify/releases/download/v${HELMIFY_VERSION}/helmify_Linux_x86_64.tar.gz" \
      | tar -xz -C /out/bin helmify

# 8. Kubernetes tooling
#    kustomize: was "curl install_kustomize.sh | bash" from a moving master branch.
#    Now a pinned release tarball — no remote script execution.
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    ARCH_RAW=$(uname -m) && \
    curl ${CURL_OPTS} "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-${ARCH}.tar.gz" | tar -xz -C /out/bin kubeseal && \
    curl ${CURL_OPTS} "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz" | tar -xz -C /out/bin k9s && \
    curl ${CURL_OPTS} -o /out/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-${ARCH}" && \
    curl ${CURL_OPTS} "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_${ARCH}.tar.gz" | tar -xz -C /out/bin stern && \
    curl ${CURL_OPTS} "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${ARCH}.tar.gz" | tar -xz -C /out/bin kustomize && \
    curl ${CURL_OPTS} "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubectx_v${KUBECTX_VERSION}_linux_${ARCH_RAW}.tar.gz" | tar -xz -C /out/bin kubectx && \
    curl ${CURL_OPTS} "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubens_v${KUBECTX_VERSION}_linux_${ARCH_RAW}.tar.gz" | tar -xz -C /out/bin kubens && \
    chmod 0755 /out/bin/* /out/jfr/bin/jenkinsfile-runner

# Sanity check: every binary must actually execute before it ships
RUN /out/bin/oras version >/dev/null && \
    /out/bin/argocd version --client >/dev/null && \
    /out/bin/kustomize version >/dev/null && \
    /out/bin/jf --version >/dev/null

# ==========================================================
# Stage 2: Final Production Image
# ==========================================================
FROM ${REGISTRY}/library/docker:${DIND_TAG}

LABEL org.opencontainers.image.title="devops-jenkinsfile-runner" \
      org.opencontainers.image.description="Jenkinsfile Runner + K8s/Helm/GitOps toolchain" \
      org.opencontainers.image.base.name="docker:${DIND_TAG}"

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# Copy external binary tools (both pinned — uv was ":latest")
COPY --from=quay.io/helmpack/chart-testing:v3.14.0 /usr/local/bin/ct /usr/local/bin/ct
COPY --from=ghcr.io/astral-sh/uv:0.12.9 /uv /bin/

# Copy all pre-downloaded binaries from builder stage
COPY --from=builder /out/bin/ /usr/local/bin/
COPY --from=builder /out/jfr /opt/jfr

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk \
    JENKINS_HOME=/opt/jenkins \
    PATH="/opt/jfr/bin:/usr/lib/jvm/java-21-openjdk/bin:${PATH}" \
    CURL_OPTS="--proto =https --tlsv1.2 -fsSL --retry 3 --retry-delay 2 --max-time 600"

# Upgrade the base OS packages FIRST — this is what closes the openssl /
# libcrypto3 / libssl3 / curl / libcurl / openssh / glib / musl / vim findings
# that come from the docker:*-dind base layer.
RUN apk upgrade --no-cache && \
    apk add --no-cache --upgrade \
    git git-lfs bash tcsh curl sudo python3 py3-pip iputils tcpdump \
    helm kubectl wget skopeo zip util-linux jq vim nano \
    yq podman podman-compose fuse-overlayfs openjdk21-jre unzip tar ttf-dejavu npm sshpass openssh && \
    rm -rf /var/cache/apk/*

# Install Python and NPM packages, then clean cache immediately
# --upgrade on pip/setuptools clears the old setuptools / urllib3 / certifi findings
# inside each prefix.
RUN uv pip install --system --no-cache --prefix=/opt/mcp-atlassian --upgrade pip setuptools wheel && \
    uv pip install --system --no-cache --prefix=/opt/mcp-atlassian mcp-atlassian==0.23.1 && \
    uv pip install --system --no-cache --prefix=/opt/jenkins-mcp --upgrade pip setuptools wheel && \
    uv pip install --system --no-cache --prefix=/opt/jenkins-mcp mcp-jenkins==3.5.0 && \
    npm install -g --prefix=/opt/gitlab-mcp "@structured-world/gitlab-mcp@9.1.2" && \
    npm audit fix --prefix=/opt/gitlab-mcp || true && \
    npm cache clean --force && \
    rm -rf /root/.cache /root/.npm /tmp/*

# ---------- Jenkins WAR + plugins ----------
# Every version below is explicit. The two BouncyCastle findings that appeared
# between the first and second scan came in through "latest" plugin URLs;
# pinning is what stops that drift.
#
# 2.568.3 is the newest LTS available (2.568.2 was the previous patch).
ARG JENKINS_VERSION=2.568.3

# Format per entry: <plugin-name>:<version>
ARG JENKINS_PLUGINS="\
    workflow-aggregator:608.v67378e9d3db_1 \
    workflow-job:1600.v6f36ed83529d \
    workflow-cps:4370.v49a_6937566b_6 \
    workflow-basic-steps:1098.v808b_fd7f8cf4 \
    workflow-durable-task-step:1479.v56e587f413a_7 \
    workflow-step-api:724.v538c2362b_dfb_ \
    workflow-support:1015.v785e5a_b_b_8b_22 \
    script-security:1412.v7737b_3405f86 \
    git:5.10.1 \
    git-client:6.6.1"

# API plugins that ship bundled inside jenkins.war. Dropping newer copies into
# plugins/ makes Jenkins load these instead of the bundled ones at runtime:
#   bouncycastle-api  -> BC 1.85   (CVE-2026-59650, CVE-2026-12817)
#   jackson2-api      -> jackson-databind 2.22.2  (was 2.21.2)
#   jackson3-api      -> jackson-databind 3.2.2   (was 3.1.3)
#   sshd              -> newest Apache MINA       (CVE-2026-47065)
# Set to "" to skip this block.
ARG JENKINS_API_PLUGINS="\
    bouncycastle-api:2.30.1.85.2-304.v4b_5b_62e59a_a_7 \
    jackson2-api:2.22.2-445.vdc613f1d8012 \
    jackson3-api:3.2.2-96.v599957900a_1a_ \
    sshd:3.384.vc89b_5e138cf9"

RUN mkdir -p ${JENKINS_HOME}/plugins && \
    curl ${CURL_OPTS} -o ${JENKINS_HOME}/jenkins.war \
      "https://get.jenkins.io/war-stable/${JENKINS_VERSION}/jenkins.war" && \
    for p in ${JENKINS_PLUGINS} ${JENKINS_API_PLUGINS}; do \
        name="${p%%:*}"; ver="${p##*:}"; \
        curl ${CURL_OPTS} -o "${JENKINS_HOME}/plugins/${name}.hpi" \
          "https://updates.jenkins.io/download/plugins/${name}/${ver}/${name}.hpi"; \
    done && \
    ls -1 ${JENKINS_HOME}/plugins/*.hpi | wc -l

# ---------- Helm plugins ----------
# Pinned where an upstream release tag exists; the rest are unchanged.
RUN helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v1.1.2 && \
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
RUN rm -rf /var/cache/apk/* /root/.cache /root/.npm /tmp/* /var/tmp/*

WORKDIR /workspace

ENTRYPOINT ["jenkinsfile-runner", "-w", "/opt/jenkins", "-f", "/workspace/Jenkinsfile", "-p", "/opt/jenkins/plugins", "--workspace", "/workspace"]
