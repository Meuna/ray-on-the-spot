import ray
import numpy as np
from scipy import stats

# For this example, we need the driver to run numpy so it must be installed using
# the --runtime-env-json flag
#
#   export RAY_API_SERVER_ADDRESS=http://<head node IP>:8265
#   ray job submit --runtime-env-json '{"uv": ["numpy", "scipy"]}' --working-dir . -- python 02_driver_btc.py

# --- Initialize Ray
# The driver runs on the cluster's head node, the environment has been set up
# using the --runtime-env-json flag: we can simply call ray.init() without arguments
ray.init()

# --- Generate a large dataset (pretend it's expensive to compute/load)
N = 5_000_000
data = np.random.lognormal(mean=0.0, sigma=1.0, size=N)

# --- We store the data in the cluster's shared object store and get a reference
# Each worker will need the data: it will be lazily shipped to each of them as
# they access it, and only once per worker.
data_ref = ray.put(data)

@ray.remote
def bootstrap_chunk(data, n_bootstrap, seed):
    rng = np.random.default_rng(seed)

    results = np.empty(n_bootstrap)

    for i in range(n_bootstrap):
        # resample indices (no copying original array)
        idx = rng.integers(0, data.shape[0], size=data.shape[0])
        sample = data[idx]

        # SciPy computation (heavy enough to parallelize)
        # e.g. fit normal distribution
        mu, _ = stats.norm.fit(sample)

        results[i] = mu  # return mean estimate

    return results


# --- Launch workers
num_workers = 8
bootstrap_per_worker = 100

futures = [
    bootstrap_chunk.remote(data_ref, bootstrap_per_worker, seed=i)
    for i in range(num_workers)
]

# --- Gather results
results = np.concatenate(ray.get(futures))

print("Bootstrap mean:", results.mean())
print("95% CI:", np.percentile(results, [2.5, 97.5]))
