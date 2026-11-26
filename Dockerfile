# Stage 1: Build Flutter Web application
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Firebase Web configuration must be supplied at build time because Flutter
# embeds dart-define values into the compiled JavaScript bundle.
ARG FIREBASE_API_KEY
ARG FIREBASE_AUTH_DOMAIN
ARG FIREBASE_PROJECT_ID=pathfinder-4de02
ARG FIREBASE_MESSAGING_SENDER_ID
ARG FIREBASE_APP_ID

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
      --dart-define="FIREBASE_APP_ID=${FIREBASE_APP_ID}"

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
