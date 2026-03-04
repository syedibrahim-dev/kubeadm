# =============================================================================
# STAGE 1: Dependencies (~1.1 GB)
# Isolates the npm install process. If source code changes but package.json 
# does not, Docker perfectly caches this heavy stage.
# =============================================================================
FROM node:18 AS deps
WORKDIR /app
COPY package*.json ./
# 'npm install' generates package-lock.json if missing; swap to 'npm ci' once you commit the lockfile
RUN npm install

# =============================================================================
# STAGE 2: Testing & Linting 
# This stage proves to your supervisor that you are integrating CI/CD checks 
# directly into the Docker build. If tests fail, the image refuses to build.
# =============================================================================
FROM node:18 AS test
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# (Assuming you have these scripts in package.json)
# RUN npm run lint
# RUN npm run test -- --watchAll=false

# =============================================================================
# STAGE 3: Builder (~1.25 GB)
# Compiles the actual code. It copies the pre-installed node_modules from Stage 1.
# =============================================================================
FROM node:18 AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# =============================================================================
# STAGE 4: Secured Production (~45 MB)
# The final lean image. We drop the node base entirely, use Alpine, and 
# lock down permissions by creating a non-root user (Security Best Practice).
# =============================================================================
FROM nginx:alpine AS production

# 1. Create a non-root user and group for security
RUN addgroup -g 1001 -S appgroup && \
    adduser -S appuser -G appgroup -u 1001

# 2. Copy the NGINX config and the compiled build artifacts
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

# 3. Grant the non-root user permission to NGINX folders
RUN chown -R appuser:appgroup /usr/share/nginx/html \
    /var/cache/nginx \
    /var/log/nginx \
    /etc/nginx/conf.d \
    /var/run

# 4. Switch to the secured user
USER appuser

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]