# ==========================================
# Stage 1: Binaries Downloader & Builder
# ==========================================
FROM alpine:3.20 AS builder

RUN apk add --no-cache curl wget tar unzip bash ca-certificates

WORKDIR /downloads

ARG JFR_VERSION=1.0-beta-32
ARG ORAS_VERSION=1.3.0
ARG KUBESEAL_VERSION=0.26.0
ARG K9S_VERSION=0.32.5
ARG ARGOCD_VERSION=2.13.1
ARG STERN_VERSION=1.31.0
ARG KUBECTX_VERSION=0.9.5

RUN mkdir -p /out/bin /out/jfr

# 1. ORAS
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl -fsSL "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_${ARCH}.tar.gz" | tar -xz -C /out/bin oras

# 2. Jenkins CLI (jcli)
RUN curl -fsSL https://github.com/jenkins-zh/jenkins-cli/releases/latest/download/jcli-linux-amd64.tar.gz | tar -xz -C /out/bin

# 3. Jenkinsfile Runner
RUN curl -fsSL -o /tmp/jfr.zip "https://github.com/jenkinsci/jenkinsfile-runner/releases/download/${JFR_VERSION}/jenkinsfile-runner-${JFR_VERSION}.zip" && \
    unzip /tmp/jfr.zip -d /out/jfr && rm /tmp/jfr.zip

# 4. JFrog CLI
RUN curl -fL https://getcli.jfrog.io/v2-jf | sh && mv jf /out/bin/

# 5. Rancher CLIs (Relative symlink fix)
RUN for RV in v2.15.1 v2.10.1 v2.13.1; do \
        curl -fsSL "https://github.com/rancher/cli/releases/download/${RV}/rancher-linux-amd64-${RV}.tar.gz" | tar -xz -C /tmp && \
        mv /tmp/rancher-${RV}/rancher /out/bin/rancher_${RV} && \
        rm -rf /tmp/rancher-${RV}; \
    done && \
    cd /out/bin && ln -s rancher_v2.13.1 rancher

# 6. K3d
RUN wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | USE_SUDO=false K3D_INSTALL_DIR=/out/bin bash

# 7. Helmify
RUN curl -L https://github.com/arttor/helmify/releases/latest/download/helmify_Linux_x86_64.tar.gz | tar -xz -C /out/bin helmify

# 8. Kubernetes tooling
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    ARCH_RAW=$(uname -m) && \
    curl -fL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-${ARCH}.tar.gz" | tar -xz -C /out/bin kubeseal && \
    curl -fL "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz" | tar -xz -C /out/bin k9s && \
    curl -fL "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-${ARCH}" -o /out/bin/argocd && \
    curl -fL "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_${ARCH}.tar.gz" | tar -xz -C /out/bin stern && \
    curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- /out/bin && \
    curl -fL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubectx_v${KUBECTX_VERSION}_linux_${ARCH_RAW}.tar.gz" | tar -xz -C /out/bin kubectx && \
    curl -fL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubens_v${KUBECTX_VERSION}_linux_${ARCH_RAW}.tar.gz" | tar -xz -C /out/bin kubens && \
    chmod +x /out/bin/* /out/jfr/bin/jenkinsfile-runner
# ==========================================
# Stage 2: Final Production Image
# ==========================================
FROM docker:28.5-dind

# Copy external binary tools
COPY --from=quay.io/helmpack/chart-testing:v3.14.0 /usr/local/bin/ct /usr/local/bin/ct
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/

# Copy all pre-downloaded binaries from builder stage
COPY --from=builder /out/bin/ /usr/local/bin/
COPY --from=builder /out/jfr /opt/jfr

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk \
    JENKINS_HOME=/opt/jenkins \
    PATH="/opt/jfr/bin:/usr/lib/jvm/java-21-openjdk/bin:${PATH}"

# Install Runtime APK packages (NO go, NO musl-dev compiler dependencies!)
RUN apk add --no-cache \
    git git-lfs bash tcsh curl sudo python3 py3-pip iputils tcpdump \
    helm kubectl flatpak xvfb wget skopeo zip util-linux jq vim nano \
    yq podman podman-compose fuse-overlayfs openjdk21-jre unzip tar ttf-dejavu npm sshpass openssh

# Install Python and NPM packages, then clean cache immediately
RUN uv pip install --system --no-cache --prefix=/opt/mcp-atlassian mcp-atlassian==0.23.1 && \
    uv pip install --system --no-cache --prefix=/opt/jenkins-mcp mcp-jenkins==3.5.0 && \
    npm install -g --prefix=/opt/gitlab-mcp "@structured-world/gitlab-mcp@9.1.2" && \
    npm cache clean --force && \
    rm -rf /root/.cache /tmp/*

# Download Jenkins WAR, Plugins & Helm Plugins
RUN mkdir -p ${JENKINS_HOME}/plugins && \
    curl -fsSL -o ${JENKINS_HOME}/jenkins.war https://get.jenkins.io/war-stable/latest/jenkins.war && \
    cd ${JENKINS_HOME}/plugins && \
    curl -fsSL -O https://updates.jenkins.io/latest/workflow-aggregator.hpi \
         -O https://updates.jenkins.io/latest/workflow-job.hpi \
         -O https://updates.jenkins.io/latest/workflow-cps.hpi \
         -O https://updates.jenkins.io/latest/workflow-basic-steps.hpi \
         -O https://updates.jenkins.io/latest/workflow-durable-task-step.hpi \
         -O https://updates.jenkins.io/latest/workflow-step-api.hpi \
         -O https://updates.jenkins.io/latest/workflow-support.hpi \
         -O https://updates.jenkins.io/latest/script-security.hpi \
         -O https://updates.jenkins.io/latest/git.hpi \
         -O https://updates.jenkins.io/latest/git-client.hpi && \
    helm plugin install https://github.com/helm-unittest/helm-unittest.git && \
    helm plugin install https://github.com/C123R/helm-blob.git && \
    helm plugin install https://github.com/databus23/helm-diff && \
    helm plugin install https://github.com/idsulik/helm-cel && \
    helm plugin install https://github.com/vmware-labs/distribution-tooling-for-helm && \
    helm plugin install https://github.com/adamreese/helm-env && \
    helm plugin install https://github.com/adamreese/helm-last && \
    helm plugin install https://github.com/adamreese/helm-local && \
    helm plugin install https://github.com/jkroepke/helm-secrets --version v4.7.6 && \
    helm plugin install https://github.com/adamreese/helm-nuke && \
    helm plugin install https://github.com/ContainerSolutions/helm-monitor && \
    helm plugin install https://github.com/hypnoglow/helm-s3.git && \
    helm plugin install https://github.com/dadav/helm-schema && \
    helm plugin install https://github.com/salesforce/helm-starter.git && \
    helm plugin install https://github.com/hayorov/helm-gcs.git && \
    helm plugin install https://github.com/karuppiah7890/helm-schema-gen.git && \
    helm plugin install https://github.com/datreeio/helm-datree && \
    helm plugin install https://github.com/JovianX/helm-release-plugin && \
    helm plugin install https://github.com/seacrew/helm-compose && \
    rm -rf ~/.cache/helm /tmp/*

# Flatpak config, User setup & Final System Cleanup
RUN flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo && \
    flatpak install -y flathub com.github.inercia.k3x && \
    adduser -D dockeruser && echo "dockeruser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/* /root/.cache

WORKDIR /workspace

ENTRYPOINT ["jenkinsfile-runner", "-w", "/opt/jenkins", "-f", "/workspace/Jenkinsfile", "-p", "/opt/jenkins/plugins", "--workspace", "/workspace"]
