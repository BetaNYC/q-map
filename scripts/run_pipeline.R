# scripts/run_pipeline.R
#
# Entry point for the DAG. Exists so the pipeline can be run through
# `uvr run scripts/run_pipeline.R`, which takes a script path rather than an
# inline expression.
#
# Usage:
#   uvr run scripts/run_pipeline.R          # build what is out of date
#   R -q -e 'targets::tar_visnetwork()'     # inspect the graph

targets::tar_make()
