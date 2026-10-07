FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY src ./src
COPY infra ./infra

EXPOSE 4000

CMD ["npm", "start"]
