FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils unzip procps xvfb x11vnc novnc websockify libsdl2-2.0-0 \
    libglib2.0-0 fonts-dejavu-core && rm -rf /var/lib/apt/lists/*
ARG V=v2026.07.1
RUN curl -fsSL https://github.com/koreader/koreader/releases/download/$V/koreader-linux-arm64-$V.tar.xz | tar xJ -C /opt
RUN mkdir -p /root/.config/koreader/plugins && curl -fsSL -o /tmp/a.zip https://github.com/omer-faruq/appstore.koplugin/releases/download/v1.14.0/appstore.koplugin.zip \
    && unzip -q /tmp/a.zip -d /root/.config/koreader/plugins && rm /tmp/a.zip
COPY start.sh /start.sh
CMD ["/start.sh"]
