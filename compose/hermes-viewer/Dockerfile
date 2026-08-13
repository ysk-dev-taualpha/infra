FROM node:22-bookworm-slim AS builder
WORKDIR /src

COPY package.json package-lock.json ./
RUN npm ci

COPY . ./
ARG EXPO_PUBLIC_GALLERY_URL=/gallery
ENV EXPO_PUBLIC_GALLERY_URL=${EXPO_PUBLIC_GALLERY_URL}
RUN npx expo export --platform web

FROM nginx:1.28-alpine
COPY .infra_web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /src/dist/ /usr/share/nginx/html/
EXPOSE 80
