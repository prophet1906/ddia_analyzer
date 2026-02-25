# Use Python 3.10 slim image as base
FROM python:3.10-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    POETRY_VERSION=1.8.2 \
    POETRY_HOME="/opt/poetry" \
    POETRY_VIRTUALENVS_CREATE=false \
    POETRY_NO_INTERACTION=1

# Add Poetry to PATH
ENV PATH="$POETRY_HOME/bin:$PATH"

# Install system dependencies required by pm4py and graphviz
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    build-essential \
    graphviz \
    libgraphviz-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Poetry
RUN curl -sSL https://install.python-poetry.org | python3 -

# Set working directory
WORKDIR /app

# Copy dependency files first for better caching
COPY pyproject.toml ./

# Install dependencies
RUN poetry install --no-root --no-dev

# Copy application code
COPY miner/ ./miner/

# Create output directories
RUN mkdir -p generated_pnml generated_ocpn generated_uncolored_pn data

# Set the entrypoint to run the ocel2.py script
ENTRYPOINT ["python", "-m", "miner.ocel2"]

# Default command (can be overridden)
CMD ["--help"]
