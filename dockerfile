# docker build -t zeevb053/k3d-dind:1.4 .
# docker run --privileged -d -it --name k3d zeevb053/k3d-dind:1.4
# docker exec -it k3d bash
# Step 1: Extract the official chart-testing binary
FROM quay.io/helmpack/chart-testing:v3.14.0 AS ct-source

FROM docker:28.5-dind

COPY --from=ct-source /usr/local/bin/ct /usr/local/bin/ct
# Install base tools
RUN apk add --no-cache \
    git \
    bash \
    tcsh \
    curl \
    sudo \
    python3 \
    py3-pip \
    iputils \
    tcpdump \
    helm \
    kubectl \
    flatpak \
    xvfb \
    wget \
    skopeo \
    zip \
    util-linux \
    jq \
    vim \
    nano \
    yq 

RUN apk add --no-cache \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
    go musl-dev

RUN go install oras.land/oras/cmd/oras@v1.3.0

RUN helm plugin install https://github.com/helm-unittest/helm-unittest.git && \
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
# Install kubeseal and kubeseal-convert manually from GitHub releases
# Install kubeseal and kubeseal-convert manually from GitHub releases
# Install kubeseal and kubeseal-convert manually from GitHub releases
# Install Kubernetes tooling: kubeseal, k9s, argocd, stern, kustomize, kubectx/kubens
# Install Kubernetes tooling: kubeseal, k9s, argocd, stern, kustomize, kubectx/kubens
RUN KUBESEAL_VERSION="0.26.0" && \
    K9S_VERSION="0.32.5" && \
    ARGOCD_VERSION="2.13.1" && \
    STERN_VERSION="1.31.0" && \
    KUBECTX_VERSION="0.9.5" && \
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    ARCH_RAW=$(uname -m) && \
    \
    # 1. kubeseal (Bitnami Sealed Secrets)
    curl -fL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-${ARCH}.tar.gz" -o /tmp/kubeseal.tar.gz && \
    tar -xzf /tmp/kubeseal.tar.gz -C /usr/local/bin/ kubeseal && \
    \
    # 2. k9s (TUI for Kubernetes)
    curl -fL "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz" -o /tmp/k9s.tar.gz && \
    tar -xzf /tmp/k9s.tar.gz -C /usr/local/bin/ k9s && \
    \
    # 3. argocd CLI
    curl -fL "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-${ARCH}" -o /usr/local/bin/argocd && \
    \
    # 4. stern (multi-pod log tailing)
    curl -fL "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_${ARCH}.tar.gz" -o /tmp/stern.tar.gz && \
    tar -xzf /tmp/stern.tar.gz -C /usr/local/bin/ stern && \
    \
    # 5. kustomize
    curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- /usr/local/bin && \
    \
    # 6. kubectx + kubens (uses x86_64/arm64, not amd64/arm64)
    curl -fL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubectx_v${KUBECTX_VERSION}_linux_${ARCH_RAW}.tar.gz" -o /tmp/kubectx.tar.gz && \
    tar -xzf /tmp/kubectx.tar.gz -C /usr/local/bin/ kubectx && \
    curl -fL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubens_v${KUBECTX_VERSION}_linux_${ARCH_RAW}.tar.gz" -o /tmp/kubens.tar.gz && \
    tar -xzf /tmp/kubens.tar.gz -C /usr/local/bin/ kubens && \
    \
    # 7. Permissions + cleanup
    chmod +x /usr/local/bin/kubeseal \
    /usr/local/bin/k9s \
    /usr/local/bin/argocd \
    /usr/local/bin/stern \
    /usr/local/bin/kustomize \
    /usr/local/bin/kubectx \
    /usr/local/bin/kubens && \
    rm -f /tmp/kubeseal.tar.gz \
    /tmp/k9s.tar.gz \
    /tmp/stern.tar.gz \
    /tmp/kubectx.tar.gz \
    /tmp/kubens.tar.gz


# Install k3d
RUN wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash 
    # && \
    # cat /usr/local/bin/k3d | base64 > /usr/local/bin/k3d-base && rm /usr/local/bin/k3d

# ---- Install Helmify ----
RUN curl -L https://github.com/arttor/helmify/releases/latest/download/helmify_Linux_x86_64.tar.gz \
    | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/helmify 
    # && \
    # cat /usr/local/bin/helmify | base64 > /usr/local/bin/helmify-base && rm /usr/local/bin/helmify

# ---- Install jfrog cli ----
RUN curl -fL https://install-cli.jfrog.io | sh 

# ---- Install rancher cli ----
RUN curl -L https://github.com/rancher/cli/releases/download/v2.13.1/rancher-linux-amd64-v2.13.1.tar.gz \
    | tar -xz -C /tmp && \
    mv /tmp/rancher-v2.13.1/rancher /usr/local/bin/rancher && \
    chmod +x /usr/local/bin/rancher && \
    rm -rf /tmp/rancher-*

# ---- Install Kustomize ----
# RUN curl -s "https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest" \
#     | grep browser_download_url \
#     | grep linux_amd64.tar.gz \
#     | cut -d '"' -f 4 \
#     | xargs curl -L -o /tmp/kustomize.tar.gz \
#     && tar -xzf /tmp/kustomize.tar.gz -C /usr/local/bin \
#     && chmod +x /usr/local/bin/kustomize \
#     && rm -f /tmp/kustomize.tar.gz

# Configure Flatpak and install K3x
RUN flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo && \
    flatpak install -y flathub com.github.inercia.k3x

# Create non-root user for Flatpak
RUN adduser -D dockeruser && echo "dockeruser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# RUN dockerd & \
# sleep 5 && \
# echo ---- pull k3d images ---- && \
# mkdir /temp  && \
# skopeo copy docker://ghcr.io/k3d-io/k3d-proxy:5.8.3 docker-archive:/temp/k3d-proxy-5.8.3.tar:ghcr.io/k3d-io/k3d-proxy:5.8.3  && \
# skopeo copy docker://ghcr.io/k3d-io/k3d-tools:5.8.3 docker-archive:/temp/k3d-tools-5.8.3.tar:ghcr.io/k3d-io/k3d-tools:5.8.3  && \
# skopeo copy docker://rancher/k3s:v1.31.5-k3s1 docker-archive:/temp/k3s-v1.31.5-k3s1.tar:rancher/k3s:v1.31.5-k3s1  && \
# skopeo copy docker://registry:3.0.0 docker-archive:/temp/registry-3.0.0.tar:registry:3.0.0   && \
# echo  
# && \
# cat /temp/k3d-proxy-5.8.3.tar | base64 > /temp/k3d-proxy-5.8.3--base  && \
# cat /temp/k3d-tools-5.8.3.tar | base64 > /temp/k3d-tools-5.8.3--base   && \
# cat /temp/k3s-v1.31.5-k3s1.tar | base64 > /temp/k3s-v1.31.5-k3s1--base   && \
# cat /temp/registry-3.0.0.tar | base64 > /temp/registry-3.0.0--base  && \
# rm -f /temp/k3d-proxy-5.8.3.tar /temp/k3d-tools-5.8.3.tar /temp/k3s-v1.31.5-k3s1.tar /temp/registry-3.0.0.tar

# docker pull ghcr.io/k3d-io/k3d-proxy:5.8.3 && \
# docker pull ghcr.io/k3d-io/k3d-tools:5.8.3 && \
# docker pull rancher/k3s:v1.31.5-k3s1 && \
# docker pull registry:3.0.0 
# && \
# cd /root && \
# echo ---- Create temp cluster ---- && \
# k3d cluster create mycluster & && \
# mkdir -p ~/.kube && \
# k3d kubeconfig get mycluster > ~/.kube/config && \
# kubectl get nodes && \
# echo '✅ K3d cluster ready. Helmify, Kustomize, Helm, and Kubectl are installed.' && \
# echo 'Use: xvfb-run -a flatpak run com.github.inercia.k3x to open K3x GUI.'

# USER dockeruser
# WORKDIR /home/dockeruser
ENTRYPOINT ["dockerd-entrypoint.sh"]