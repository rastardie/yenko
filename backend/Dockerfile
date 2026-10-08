FROM node:22.14.0-alpine3.21 AS runtime

WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && addgroup -S yenko && adduser -S yenko -G yenko
COPY --chown=yenko:yenko db ./db
COPY --chown=yenko:yenko src ./src
USER yenko
EXPOSE 8080
CMD ["node", "src/server.js"]
