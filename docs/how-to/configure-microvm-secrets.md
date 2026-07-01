---
title: "How to Configure MicroVM Secrets"
description: "Push 1Password secrets into a MicroVM guest on a type-server host"
type: how-to
audience: both
last-reviewed: 2026-06-30
---

# How to Configure MicroVM Secrets

Both the server and its MicroVM guests run separate opnix instances that pull secrets from 1Password. Each instance needs its own token file.

## Configure the Host Token

1. Place the 1Password service account token on the host:

    ```bash
    echo "your-token" | sudo tee /etc/opnix-token
    sudo chmod 600 /etc/opnix-token
    ```

## Configure Each VM Guest

2. SSH into the guest and place a copy of the token:

    ```bash
    ssh root@192.168.83.15
    echo "your-token" | sudo tee /etc/opnix-token
    sudo chmod 600 /etc/opnix-token
    sudo systemctl restart opnix-secrets
    ```

3. Repeat for every guest VM. Verify with:

    ```bash
    ls -la /etc/opnix-token
    # Expected: -rw------- 1 root root ...
    ```

## Required 1Password Items

### Matrix Synapse — Vault: `Homelab`

