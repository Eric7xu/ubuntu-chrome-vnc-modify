FROM ubuntu:24.04

ARG TARGETARCH
ARG CHROME_ARCH=auto

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    VNC_PORT=5901 \
    NOVNC_PORT=6901 \
    CDP_PORT=9222 \
    CHROME_PROFILE=/home/browser/chrome-profile \
    RESOLUTION=1920x1080x24

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    ca-certificates curl wget \
    xvfb x11vnc x11-utils openbox \
    novnc websockify dbus-x11 dbus socat \
    fonts-liberation fonts-noto-cjk xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# The official Google Chrome Linux package used here is amd64-only.
RUN set -eux; \
    arch="${CHROME_ARCH}"; \
    if [ "${arch}" = auto ]; then arch="${TARGETARCH}"; fi; \
    case "${arch}" in \
      amd64) url="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" ;; \
      *) echo "This image requires amd64; unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    wget -q -O /tmp/chrome.deb "${url}"; \
    apt-get update -qq; \
    apt-get install -y -qq /tmp/chrome.deb; \
    rm -f /tmp/chrome.deb; \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash browser \
    && mkdir -p "${CHROME_PROFILE}" /home/browser/.config/openbox \
    && chown -R browser:browser /home/browser

RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

EXPOSE 9223 6901 5901
ENTRYPOINT ["/entrypoint.sh"]
