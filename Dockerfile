# Stage 1: Build Flutter Web application
# Install the pinned official SDK archive. The floating Cirrus Labs `stable`
# image can lag Flutter releases and may not satisfy the Dart constraint.
FROM debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.50.1
ARG FLUTTER_ARCHIVE_SHA256=4ad17fc8462fbcef2ba19ff4a78c0a16b7147fde1add8578e267ea62cdb92678

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git libglu1-mesa unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz \
    && echo "${FLUTTER_ARCHIVE_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && mkdir -p /opt/flutter \
    && tar -xf /tmp/flutter.tar.xz -C /opt/flutter --strip-components=1 \
    && rm /tmp/flutter.tar.xz

ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

WORKDIR /app

# Firebase Web configuration must be supplied at build time because Flutter
# embeds dart-define values into the compiled JavaScript bundle.
ARG FIREBASE_API_KEY
ARG FIREBASE_AUTH_DOMAIN
ARG FIREBASE_PROJECT_ID=pathfinder-4de02
ARG FIREBASE_MESSAGING_SENDER_ID
ARG FIREBASE_APP_ID
ARG FIREBASE_APPCHECK_SITE_KEY

# Download dependencies
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy all source files and build for release
COPY . .
RUN test -n "$FIREBASE_API_KEY" \
    && test -n "$FIREBASE_AUTH_DOMAIN" \
    && test -n "$FIREBASE_PROJECT_ID" \
    && test -n "$FIREBASE_MESSAGING_SENDER_ID" \
    && test -n "$FIREBASE_APP_ID" \
    || (echo "Firebase Web build arguments are required to enable sign-in" >&2; exit 1) \
    && flutter build web --release \
      --dart-define="FIREBASE_API_KEY=${FIREBASE_API_KEY}" \
      --dart-define="FIREBASE_AUTH_DOMAIN=${FIREBASE_AUTH_DOMAIN}" \
      --dart-define="FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID}" \
      --dart-define="FIREBASE_MESSAGING_SENDER_ID=${FIREBASE_MESSAGING_SENDER_ID}" \
      --dart-define="FIREBASE_APP_ID=${FIREBASE_APP_ID}" \
      --dart-define="FIREBASE_APPCHECK_SITE_KEY=${FIREBASE_APPCHECK_SITE_KEY}"

# Stage 2: Production Nginx image for Google Cloud Run
FROM nginx:alpine

# Remove default static files
RUN rm -rf /usr/share/nginx/html/*

# Copy compiled web output
COPY --from=build /app/build/web /usr/share/nginx/html

# Nginx alpine image automatically processes templates in /etc/nginx/templates/*.template
# with envsubst and outputs them to /etc/nginx/conf.d/*.conf
COPY nginx.conf /etc/nginx/templates/default.conf.template

# Cloud Run injects the PORT environment variable (default: 8080)
# Ensure Nginx envsubst only replaces PORT, preserving Nginx variables like $uri
ENV NGINX_ENVSUBST_FILTER="PORT"
ENV PORT=8080
EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
