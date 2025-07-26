FROM telegraf:1.35.2-alpine

ARG ARCH

LABEL mantainer="func0der"
LABEL project="ISP-Checker"
LABEL component="telegraf"

COPY ./bin/entrypoint.sh /entrypoint.sh

RUN apk update && apk add --no-cache \
    mtr \
    speedtest-cli \
    jq && \
    rm -rf /var/cache/apk/* && \
    addgroup telegraf video

EXPOSE 8125/udp 8092/udp 8094

ENTRYPOINT ["/entrypoint.sh"]

CMD ["telegraf"]
