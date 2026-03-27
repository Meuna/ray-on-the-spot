# prefect-on-the-spot

This project provision a Prefect server and a Spot EC2 Scalling Group, using
[OpenTofu](https://opentofu.org/docs/intro/install/).

The Scalling Group has no scale-in/out strategy: the desired capacity will
stay at the value prompted during provisionning. Requested instances can stay
idle for as long as the lab is deployed and you will be charged for it.

> [!CAUTION]
> This is a lab deployment with very little concern for security: review
> what you are deploying.

## Usage

1. If you don't already have one, generate an SSH key pair. The default value of
`var.ssh_public_key_path` assume the key to be RSA with the default naming
`~/.ssh/id_rsa` but you can choose a different path and type.

```console
$ ssh-keygen -t rsa
```

2. Clone the repository

```console
$ git https://github.com/Meuna/prefect-on-the-spot.git
$ cd prefect-on-the-spot
```

3. Initialise tofu

```console
$ tofu init
```

4. (Recommanded) Change ingress CIDR in `var.allowed_client_cidr` to you IP only.

5. Deploy the stack. You will be prompted for the desired vCPU capacity

```console
$ tofu apply
```