FROM node:20-alpine

RUN mkdir -p /test
WORKDIR /test

COPY package.json yarn.lock /test/
RUN npm install --no-audit --no-fund
COPY test /test/test

EXPOSE 8080
