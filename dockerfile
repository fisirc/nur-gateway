FROM nixos/nix AS builder

RUN nix-channel --update
RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
RUN echo "sandbox = true" >> /etc/nix/nix.conf

WORKDIR /app

COPY . .

CMD [ "nix", "run" ]


