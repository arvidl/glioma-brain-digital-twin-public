FROM condaforge/mambaforge:latest AS base

WORKDIR /workspace

COPY environment/environment.yml .
RUN mamba env create -f environment.yml && mamba clean -afy

SHELL ["conda", "run", "-n", "finse26", "/bin/bash", "-c"]

COPY pyproject.toml .
COPY scripts/ scripts/
COPY notebooks/ notebooks/
COPY data/ data/
COPY docs/ docs/
COPY tests/ tests/

RUN pip install --no-deps -e .

EXPOSE 8888

CMD ["conda", "run", "--no-capture-output", "-n", "finse26", \
     "jupyter", "lab", "--ip=0.0.0.0", "--port=8888", \
     "--no-browser", "--allow-root", \
     "--notebook-dir=/workspace/notebooks"]
