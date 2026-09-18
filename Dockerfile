FROM alpine:3.24

# ── System packages ──────────────────────────────────────────────
RUN apk add --no-cache \
    git \
    make \
    bash \
    shellcheck \
    ca-certificates \
    curl \
    jq \
    ripgrep \
    fd \
    gnupg \
    openssh-client \
    poppler-utils \
    procps \
    sudo \
    g++ \
    build-base \
    file \
    dash \
    elvish \
    fish \
    loksh \
    mksh \
    nushell \
    oksh \
    tcsh \
    yash \
    zsh \
    unzip \
    github-cli \
    glab \
    shadow \
    nodejs \
    npm \
    docker-cli \
    docker-cli-compose \
    gosu \
    python3 \
    python3-dev \
    py3-pip \
    socat \
    aws-cli \
    docker-cli-buildx

# ── Extra user-specified packages (no Dockerfile edit needed) ────────
ARG EXTRA_PACKAGES=""
RUN if [ -n "$EXTRA_PACKAGES" ]; then apk add --no-cache $EXTRA_PACKAGES; fi

# ── uv / uvx (Python package runner) ────────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# ── Go + gopls ────────────────────────────────────────────────────
ARG GO_VERSION=go1.26.0
COPY scripts/go-install.sh /tmp/go-install.sh
RUN chmod +x /tmp/go-install.sh && /tmp/go-install.sh "${GO_VERSION}" \
    && rm /tmp/go-install.sh \
    && export PATH="/usr/local/go/bin:${PATH}" \
    && go install golang.org/x/tools/gopls@latest \
    && cp /root/go/bin/gopls /usr/local/bin/gopls \
    && rm -rf /root/go /root/.cache/go-build
ENV PATH="/usr/local/go/bin:${PATH}"

# ── Extra user-specified Go packages (no Dockerfile edit needed) ──
ARG EXTRA_GO_PACKAGES=""
RUN if [ -n "$EXTRA_GO_PACKAGES" ]; then \
      set -e; \
      for pkg in $EXTRA_GO_PACKAGES; do \
        env GOBIN=/usr/local/bin go install "$pkg"; \
      done; \
      rm -rf /root/go /root/.cache/go-build; \
    fi

# ── Terraform + Terragrunt ────────────────────────────────────────
RUN ARCH=$(uname -m) \
    && case "$ARCH" in x86_64) ARCH=amd64 ;; aarch64) ARCH=arm64 ;; esac \
    && curl -fsSL "https://releases.hashicorp.com/terraform/1.11.2/terraform_1.11.2_linux_${ARCH}.zip" -o /tmp/terraform.zip \
    && unzip -o /tmp/terraform.zip -d /usr/local/bin/ \
    && rm /tmp/terraform.zip \
    && curl -fsSL "https://github.com/gruntwork-io/terragrunt/releases/download/v0.77.10/terragrunt_linux_${ARCH}" -o /usr/local/bin/terragrunt \
    && chmod +x /usr/local/bin/terragrunt

# ── Host-mirrored user ──────────────────────────────────────────
ARG HOST_UID=1000
ARG HOST_USER=user
ARG HOST_HOME=/home/${HOST_USER}
ARG CONTAINER_SHELL=/bin/bash
RUN mkdir -p "$(dirname ${HOST_HOME})" \
    && adduser -D -u ${HOST_UID} \
    -h ${HOST_HOME} \
    -s ${CONTAINER_SHELL} \
    ${HOST_USER} \
    && echo "${HOST_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
ENV HOST_UID="${HOST_UID}" HOST_USER="${HOST_USER}" HOST_HOME="${HOST_HOME}"

# ── mise (polyglot tool version manager, MIT) ─────────────────────
# Per-project toolchains via .mise.toml. Shims come before the pinned
# terraform/terragrunt block on PATH, but mise's default system fallback
# means a shim only shadows the system binary inside a project that pins it.
RUN ARCH=$(uname -m) \
    && case "$ARCH" in x86_64) MISE_ARCH=x64 ;; aarch64) MISE_ARCH=arm64 ;; *) echo "unsupported arch: $ARCH" >&2; exit 1 ;; esac \
    && MISE_RELEASE=v2026.9.11 \
    && asset="mise-${MISE_RELEASE}-linux-${MISE_ARCH}-musl" \
    && curl -fsSL "https://github.com/jdx/mise/releases/download/${MISE_RELEASE}/${asset}" -o /tmp/mise-bin \
    && curl -fsSL "https://github.com/jdx/mise/releases/download/${MISE_RELEASE}/SHASUMS256.txt" -o /tmp/mise-SHASUMS256.txt \
    && expected="$(awk -v a="./${asset}" '$2==a {print $1}' /tmp/mise-SHASUMS256.txt)" \
    && test -n "$expected" \
    && echo "${expected}  /tmp/mise-bin" | sha256sum -c - \
    && chmod +x /tmp/mise-bin \
    && mv /tmp/mise-bin /usr/local/bin/mise \
    && rm /tmp/mise-SHASUMS256.txt

ENV MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CACHE_DIR=/var/cache/mise \
    MISE_TRUSTED_CONFIG_PATHS="${HOST_HOME}"
ENV PATH="${MISE_DATA_DIR}/shims:${PATH}"

# Pre-install the toolchain terraform-aws-workloads pins today so first use is
# offline; the project's .mise.toml selects versions, so no global config here.
RUN mkdir -p "${MISE_DATA_DIR}" "${MISE_CACHE_DIR}" \
    && mise install opentofu@1.12.6 terragrunt@1.1.4 tflint@0.62.1 trivy@0.70.0 sops@3.13.1 jq@1.8.1 \
    && mise reshim \
    && chown -R "${HOST_UID}" "${MISE_DATA_DIR}" "${MISE_CACHE_DIR}"

# ── Useful language tooling (LSP servers) ──────────────────────────
RUN npm install -g typescript typescript-language-server pyright

# ── Extra user-specified npm packages (no Dockerfile edit needed) ──
ARG EXTRA_NPM_PACKAGES=""
RUN if [ -n "$EXTRA_NPM_PACKAGES" ]; then npm install -g $EXTRA_NPM_PACKAGES; fi

ENV NODE_PATH=/usr/local/lib/node_modules
ENV PATH="${HOST_HOME}/.local/bin:/usr/local/custom-bin:${PATH}"
ENV NPM_CONFIG_UPDATE_NOTIFIER=false

# CLI installs are ordered from least- to most-frequently pinned for caching.

# ── opencode-ai (MIT) ───────────────────────────────────────────
ARG HARNESS_REFRESH=""
ARG OPENCODE_VERSION=""
RUN if [ -n "$OPENCODE_VERSION" ]; then \
      npm install -g "opencode-ai@${OPENCODE_VERSION}"; \
    else \
      npm install -g opencode-ai; \
    fi \
    && opencode --version
ENV OPENCODE_DISABLE_AUTOUPDATE=1

# ── Mistral Vibe ────────────────────────────────────────────────
ARG VIBE_VERSION=""
ENV UV_TOOL_DIR=/opt/uv-tools
ENV UV_TOOL_BIN_DIR=/usr/local/bin
RUN if [ -n "$VIBE_VERSION" ]; then \
      uv tool install "mistral-vibe==${VIBE_VERSION}"; \
    else \
      uv tool install mistral-vibe; \
    fi \
    && chmod -R a+rX /opt/uv-tools \
    && gosu "${HOST_USER}" vibe --version

# ── pi ──────────────────────────────────────────────────────────
ARG PI_VERSION=""
RUN if [ -n "$PI_VERSION" ]; then \
      npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}"; \
    else \
      npm install -g --ignore-scripts @earendil-works/pi-coding-agent; \
    fi

# ── Codex CLI (npm package) ──────────────────────────────────────
ARG CODEX_VERSION=""
RUN if [ -n "$CODEX_VERSION" ]; then \
      npm install -g "@openai/codex@${CODEX_VERSION}"; \
    else \
      npm install -g @openai/codex; \
    fi \
    && vendored_rg=$(find /usr/local/lib/node_modules -type f -path '*/codex-path/rg' -print -quit) \
    && test -n "$vendored_rg" \
    && ln -sf /usr/bin/rg "$vendored_rg" \
    && "$vendored_rg" --version

# ── Claude Code (native installer) ─────────────────────────────
ARG CC_VERSION=""
USER ${HOST_USER}
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && if [ -n "$CC_VERSION" ]; then \
         "${HOME}/.local/bin/claude" update --target "$CC_VERSION"; \
       fi
USER root
ENV DISABLE_AUTOUPDATER=1

ARG VERSION=""
LABEL org.opencontainers.image.version="$VERSION"

# ── Environment markers ───────────────────────────────────────────
RUN touch /this-is-claude-docker-env \
          /this-is-codex-docker-env \
          /this-is-pi-docker-env \
          /this-is-vibe-docker-env \
          /this-is-opencode-docker-env \
          /this-is-harness-docker-env

# ── Security wrappers (replace real binaries) ─────────────────────
RUN mkdir -p /usr/libexec/git-real    && mv /usr/bin/git    /usr/libexec/git-real/git \
 && mkdir -p /usr/libexec/docker-real && mv /usr/bin/docker /usr/libexec/docker-real/docker
COPY scripts/git-wrapper.sh    /usr/bin/git
COPY scripts/docker-wrapper.sh /usr/bin/docker
COPY scripts/harness-session.sh /usr/local/bin/harness-session
COPY scripts/entrypoint.sh     /usr/local/bin/entrypoint.sh
COPY docker/gitignore-global   /etc/gitignore_global
COPY docker/gitconfig-system   /etc/gitconfig
COPY scripts/profile-path.sh   /etc/profile.d/harness-path.sh
RUN chmod +x /usr/bin/git /usr/bin/docker /usr/local/bin/entrypoint.sh \
      /usr/local/bin/harness-session /etc/profile.d/harness-path.sh \
    && ln -sf harness-session /usr/local/bin/claude-session \
    && ln -sf harness-session /usr/local/bin/codex-session \
    && ln -sf harness-session /usr/local/bin/pi-session \
    && ln -sf harness-session /usr/local/bin/vibe-session \
    && ln -sf harness-session /usr/local/bin/opencode-session \
    && ln -sf /usr/local/bin/harness-notifier /usr/local/bin/claude-notifier \
    && ln -sf /usr/local/bin/harness-notifier /usr/local/bin/codex-notifier \
    && ln -sf /usr/local/bin/harness-notifier /usr/local/bin/pi-notifier \
    && ln -sf /usr/local/bin/harness-notifier /usr/local/bin/vibe-notifier \
    && ln -sf /usr/local/bin/harness-notifier /usr/local/bin/opencode-notifier

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
