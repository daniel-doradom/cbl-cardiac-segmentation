# Test layers

- The default `pytest` run is synthetic and contains no PHI.
- Tests marked `integration` may require an external backend, license, weights,
  and compute environment; none are enabled by default.
- Tests marked `real_case` may read approved local data and must write only to
  ignored case output. They are never committed or run by default.

Do not fake model output to label a backend path end-to-end tested. Synthetic
normalization tests verify the adapter boundary; actual inference is reported
separately.
