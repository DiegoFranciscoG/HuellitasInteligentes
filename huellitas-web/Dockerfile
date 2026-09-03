# ─────────────────────────────────────────────
# Frontend Angular — Multi-stage Dockerfile
# ─────────────────────────────────────────────
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --silent
COPY . .
# Construye con el environment de producción
RUN npx ng build --configuration production

FROM nginx:alpine
# Copia el build de Angular
COPY --from=build /app/dist/huellitas-web/browser /usr/share/nginx/html
# Configuración nginx para Angular SPA (todas las rutas → index.html)
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
