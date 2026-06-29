FROM nimlang/nim:2.2.10

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates git \
  && rm -rf /var/lib/apt/lists/*

RUN nimble install -y prologue

COPY . /app

RUN nim c -d:release \
  -p:/app/src \
  -p:/app/packages/flowbrigade_prologue/src \
  -o:/usr/local/bin/flowbrigade-prologue-e2e \
  /app/packages/flowbrigade_prologue/e2e/app.nim

EXPOSE 8080

CMD ["/usr/local/bin/flowbrigade-prologue-e2e"]
