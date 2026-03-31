# ray-on-the-spot

This project provision a Ray server and a Spot EC2 Scalling Group, using
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
$ git https://github.com/Meuna/ray-on-the-spot.git
$ cd ray-on-the-spot
```

3. Initialise tofu

```console
$ tofu init
```

4. (Recommanded) Change ingress CIDR in `var.allowed_client_cidr` to you IP only.

5. Deploy the stack. You will be prompted for the desired vCPU capacity

```console
$ tofu apply
var.target_capacity
  Total number of vCPUs requested

  Enter a value: 16

...

Apply complete! Resources: 22 added, 0 changed, 0 destroyed.

Outputs:

ray_api_url = "http://<ip of the ray head node>:8265"
```

## Quickstart with ray

The modern and easiest way to run a Python tool is using [uv](https://docs.astral.sh/uv/).

Wait for the Ray head node to be online and then run the sample drivers:

```console
$ cd example
$ export RAY_API_SERVER_ADDRESS="http://<ip of the ray head node>:8265"
$ uv run --with ray[default] ray job submit --working-dir . -- python 01_driver_mc_pi.py
```

This command package the current `example` directory and send it to the head node.
The driver script is then run remotely. Using the `--no-wait` flag, the command
returns immediatly. You can monitor the job's progress using `ray job` subcommands
or the ray dashboard at `http://<ip of the ray head node>:8265`.

Alternatively, you can run the driver script on your local machine. Read the comments
carefully and adapt the `ray.init` part accordingly.. Then run the driver as a
standard python script.

```console
$ uv run --with ray[client] python 01_driver_mc_pi.py
```

This requires your machine to maintain a stable connection with the Ray cluster for
the duration of the job.

To run the second example, the head node need Python dependencies. You inject them
using the `--runtime-env-json` flag:

```console
$ uv run --with ray[default] ray job submit --runtime-env-json '{"uv": ["numpy", "scipy"]}' --working-dir . -- python 02_driver_btc.py
```
