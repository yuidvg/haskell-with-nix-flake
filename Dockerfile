FROM nixos/nix:latest

# Enable nix flakes and nix-command experimental features
RUN mkdir -p /etc/nix && \
    echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
