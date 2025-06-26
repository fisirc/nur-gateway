FROM ubuntu:25.10

WORKDIR /

COPY ./zig-out/bin/thwomp /gateway

RUN touch .env

RUN chmod +x /gateway

CMD [ "/gateway" ]
