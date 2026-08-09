FROM node:24.18.0-alpine3.24 AS build
WORKDIR /src

COPY package.json package-lock.json ./
COPY apps/web/package.json apps/web/package.json
RUN npm ci

COPY apps/web ./apps/web
RUN npm run build --workspace @musica-aprender/web

FROM nginx:1.30.4-alpine3.24 AS runtime
COPY infrastructure/containers/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/apps/web/dist /usr/share/nginx/html

EXPOSE 8080
