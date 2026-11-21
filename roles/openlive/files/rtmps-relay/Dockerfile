FROM alpine:3.20
RUN apk add --no-cache ffmpeg iproute2
COPY relay.sh /relay.sh
RUN chmod +x /relay.sh
ENTRYPOINT ["/relay.sh"]
