import numpy
from fractions import Fraction

def pi4_sample(sample_count: int) -> Fraction:
    """pi4_sample runs sample_count experiments, and returns the
    fraction of time it was inside the circle. We merely use numpy
    to show off the "uv" field of the runtime_env.
    """
    in_count = 0
    for i in range(sample_count):
        x = numpy.random.rand(1)
        y = numpy.random.rand(1)
        if x * x + y * y <= 1:
            in_count += 1
    return Fraction(in_count, sample_count)
