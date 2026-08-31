# docker build -t zeevb053/k3d-dind:1.4 .
# docker run --privileged -d -it --name k3d zeevb053/k3d-dind:1.4
# docker exec -it k3d bash

# Step 1: Extract the official chart-testing binary
FROM quay.io/helmpack/chart-testing:v3.14.0 AS ct-source
FROM docker:28.5-dind

# Combine COPY commands
COPY --from=ct-source /usr/local/bin/ct /usr/local/bin/ct
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/

# Consolidate ENVs (Docker creates fewer layers this way)
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk \
    JENKINS_HOME=/opt/jenkins \
    PATH="/opt/jenkinsfile-runner/bin:/usr/lib/jvm/java-21-openjdk/bin:${PATH}"

# Install all APK packages in one layer
RUN apk add --no-cache \
    git git-lfs bash tcsh curl sudo python3 py3-pip iputils tcpdump \
    helm kubectl flatpak xvfb wget skopeo zip util-linux jq vim nano \
    yq podman podman-compose fuse-overlayfs openjdk21-jre unzip tar ttf-dejavu npm sshpass && \
    apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community go musl-dev

ARG JFR_VERSION=1.0-beta-32

# Combine all Binary Downloads, CLI installations, and NPM/Python packages into one layer
RUN curl -fsSL https://github.com/jenkins-zh/jenkins-cli/releases/latest/download/jcli-linux-amd64.tar.gz | tar -xz -C /usr/local/bin/ && \
    chmod +x /usr/local/bin/jcli && \
    # Jenkinsfile Runner
    curl -fsSL -o /tmp/jfr.zip https://github.com/jenkinsci/jenkinsfile-runner/releases/download/${JFR_VERSION}/jenkinsfile-runner-${JFR_VERSION}.zip && \
    unzip /tmp/jfr.zip -d /opt/jfr && \
    rm /tmp/jfr.zip && \
    chmod +x /opt/jfr/bin/jenkinsfile-runner && \
    # Python/NPM packages via UV/NPM
    uv pip install --system --no-cache --prefix=/opt/mcp-atlassian mcp-atlassian==0.23.1 && \
    uv pip install --system --no-cache-dir --prefix=/opt/jenkins-mcp mcp-jenkins==3.5.0 && \
    npm install -g --prefix=/opt/gitlab-mcp "@structured-world/gitlab-mcp@9.1.2" && \
    # Go tools
    go install oras.land/oras/cmd/oras@v1.3.0 && \
    # JFrog CLI
    curl -fL https://getcli.jfrog.io/v2-jf | sh && \
    mv jf /usr/local/bin/ && \
    chmod +x /usr/local/bin/jf && \
    # Rancher CLIs (Loop through all required versions to keep it DRY)
    for RV in v2.15.1 v2.10.1 v2.13.1; do \
        curl -fsSL "https://github.com/rancher/cli/releases/download/${RV}/rancher-linux-amd64-${RV}.tar.gz" | tar -xz -C /tmp && \
        mv /tmp/rancher-${RV}/rancher /usr/local/bin/rancher_${RV} && \
        chmod +x /usr/local/bin/rancher_${RV} && \
        rm -rf /tmp/rancher-${RV}; \
    done && \
    # Set default rancher CLI mapping
    ln -s /usr/local/bin/rancher_v2.13.1 /usr/local/bin/rancher && \
    # K3d & Helmify
    wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash && \
    curl -L https://github.com/arttor/helmify/releases/latest/download/helmify_Linux_x86_64.tar.gz | tar -xz -C /usr/local/bin && \
    chmod +x /usr/local/bin/helmify && \
    # Kubernetes Tooling
    KUBESEAL_VERSION="0.26.0" K9S_VERSION="0.32.5" ARGOCD_VERSION="2.13.1" STERN_VERSION="1.31.0" KUBECTX_VERSION="0.9.5" && \
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && ARCH_RAW=$(uname -m) && \
    curl -fL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-${ARCH}.tar.gz" | tar -xz -C /usr/local/bin/ kubeseal && \
    curl -fL "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz" | tar -xz -C /usr/local/bin/ k9s && \
    curl -fL "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-${ARCH}" -o /usr/local/bin/argocd && \
    curl -fL "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_${ARCH}.tar.gz" | tar -xz -C /usr/local/bin/ stern && \
    curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- /usr/local/bin && \
    curl -fL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubectx_v${KUBECTX_VERSION}_linux_${ARCH_RAW}.tar.gz" | tar -xz -C /usr/local/bin/ kubectx && \
    curl -fL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubens_v${KUBECTX_VERSION}_linux_${ARCH_RAW}.tar.gz" | tar -xz -C /usr/local/bin/ kubens && \
    chmod +x /usr/local/bin/kubeseal /usr/local/bin/k9s /usr/local/bin/argocd /usr/local/bin/stern /usr/local/bin/kustomize /usr/local/bin/kubectx /usr/local/bin/kubens

# Combine Jenkins dependencies and Helm plugins into one layer
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
    helm plugin install https://github.com/seacrew/helm-compose

# Flatpak config and final User setup
RUN flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo && \
    flatpak install -y flathub com.github.inercia.k3x && \
    adduser -D dockeruser && echo "dockeruser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

WORKDIR /workspace

ENTRYPOINT ["jenkinsfile-runner", "-w", "/opt/jenkins", "-f", "/workspace/Jenkinsfile", "-p", "/opt/jenkins/plugins", "--workspace", "/workspace"]
