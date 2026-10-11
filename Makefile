.PHONY: setup test lint format notebooks clean docker help

CONDA_ENV := finse26
PYTHON    := conda run -n $(CONDA_ENV) python
PYTEST    := conda run -n $(CONDA_ENV) pytest
BLACK     := conda run -n $(CONDA_ENV) black
RUFF      := conda run -n $(CONDA_ENV) ruff

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Create conda environment and install dependencies
	bash environment/setup_env.sh
	$(PYTHON) scripts/check_env.py

test: ## Run test suite with pytest
	$(PYTEST) tests/ -v --tb=short

lint: ## Run ruff linter on scripts and tests
	$(RUFF) check scripts/ tests/

format: ## Format code with black
	$(BLACK) scripts/ tests/

check: lint ## Run lint + format check
	$(BLACK) --check scripts/ tests/

notebooks: ## Validate notebook JSON structure
	$(PYTHON) -c "\
		import nbformat, glob; \
		[nbformat.read(open(p), as_version=4) for p in sorted(glob.glob('notebooks/NB*.ipynb'))]; \
		print('All notebooks valid.')"

clean: ## Remove generated files and caches
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name .ipynb_checkpoints -exec rm -rf {} + 2>/dev/null || true
	find . -name '*.pyc' -delete 2>/dev/null || true
	rm -rf .pytest_cache htmlcov .coverage build dist *.egg-info

docker: ## Build Docker image
	docker build -t finse26-glioma-twin .

docker-run: ## Run JupyterLab in Docker container
	docker run -p 8888:8888 -v $(PWD)/data:/workspace/data finse26-glioma-twin
