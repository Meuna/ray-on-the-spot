from fractions import Fraction

import ray
import time

# --- Describe the workers' runtime environment.
# See https://docs.ray.io/en/latest/ray-core/api/doc/ray.runtime_env.RuntimeEnv.html

# Note that if you describe the env like this, inside the driver script, it only
# applies to the workers. If the head node also needs the env, you must describe
# it using the --runtime-env-json of the `ray job submit` command line:
#
#   ray job submit --runtime-env-json '{"uv": ["emoji"], "env_vars": {"MY_ENV_VAR": "some_value"}}'
#
# You can avoid usually avoid driver level dependencies by delaying the imports in
# the remote tasks.

runtime_env = {
    "uv": ["numpy"],
    "env_vars": {"MY_ENV_VAR": "some_value"}
}

# --- Initialize Ray.
# See https://docs.ray.io/en/latest/ray-core/api/doc/ray.init.html

# Case 1: run the driver on the Ray cluster's head node using the submit command:
#
#   ray job submit --address=http://<head node IP>:8265 --working-dir . --no-wait -- python driver.py
#
# You can also specify the cluster address using the environment variable RAY_API_SERVER_ADDRESS
#
#   export RAY_API_SERVER_ADDRESS=http://<head node IP>:8265
#   ray job submit --working-dir . --no-wait -- python 01_driver_mc_pi.py
#   ray job status <job id>
#
# With the --working-dir flag, Ray handle the shipment of your code to the cluster.
# With the --no-wait flag, the command will return immediately after submitting the
# job. You can monitor the job's progress using `ray job` subcommands or the ray
# dashboard.

ray.init(runtime_env=runtime_env)

# Case 2: run the driver on your local machine, connecting to the cluster's head node.
#
#   python 01_driver_mc_pi.py
#
# This is the Ray Client approach.
# See https://docs.ray.io/en/latest/cluster/running-applications/job-submission/ray-client.html
# 
# It requires your local machine to maintain a connection to the cluster. Add a
# "working_dir" field to the runtime_env to have Ray handle the shipment of your
# code to the cluster.
# 
# Uncomment the following lines to use the Client approach:
# runtime_env["working_dir"] = "."
# ray.init("ray://<head_node_host>:10001", runtime_env=runtime_env)


# The ray.remote decorator turns a Python function into a remotely executable Ray task
@ray.remote
def pi4_sample_task(sample_count: int) -> Fraction:
    import my_package
    return my_package.pi4_sample(sample_count)

# --- First, we call .remote() once: a single worker will run a single task
SAMPLE_COUNT = 1_000_000

print(f'Running {SAMPLE_COUNT} samples on a single worker')
start = time.time()
future = pi4_sample_task.remote(SAMPLE_COUNT)
pi4 = ray.get(future)
stop = time.time()

print(f'Running {SAMPLE_COUNT} samples took {stop - start} seconds')
print(f'Pi approximation: {float(pi4*4)}')


# --- When we call .remote() multiple times, we batch the calls across multiple workers
# In this example, we use ray.get(), which blocks until all the tasks finish
SAMPLE_COUNT = 1_000 * 1_000_000
BATCH_SIZE = 1_000_000
BATCHES = int(SAMPLE_COUNT / BATCH_SIZE)

print(f'Running {SAMPLE_COUNT} samples in {BATCHES} batches across multiple workers')
start = time.time()
futures = [pi4_sample_task.remote(BATCH_SIZE) for _ in range(BATCHES)]
results = ray.get(futures)
pi4 = sum(results) / BATCHES
stop = time.time()

print(f'Running {SAMPLE_COUNT} samples took {stop - start} seconds')
print(f'Pi approximation: {float(pi4*4)}')


# --- In this last example, we use ray.wait() to process results as they come in
SAMPLE_COUNT = 1_000 * 1_000_000
BATCH_SIZE = 1_000_000
BATCHES = int(SAMPLE_COUNT / BATCH_SIZE)
TOTAL_NUMBER_OF_CPUS = int(ray.cluster_resources().get("CPU", 1))

print(f'Running {SAMPLE_COUNT} samples in {BATCHES} batches across multiple workers')
print(f'Processing results as they come in')
start = time.time()
futures = [pi4_sample_task.remote(BATCH_SIZE) for _ in range(BATCHES)]
unfinished = futures
cumulative_sum = 0
accumulated_count = 0
while unfinished:
    # Returns the first ObjectRef that is ready.
    finished, unfinished = ray.wait(unfinished, num_returns=min(TOTAL_NUMBER_OF_CPUS, len(unfinished)))
    results = ray.get(finished)
    # process result
    cumulative_sum += sum(results)
    accumulated_count += len(results)
    pi4 = cumulative_sum / accumulated_count / BATCH_SIZE
    print(f'Pi approximation: {float(pi4*4)}')

stop = time.time()
print(f'Running {SAMPLE_COUNT} samples took {stop - start} seconds')
print(f'Pi approximation: {float(pi4*4)}')