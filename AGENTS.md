# AGENTS INSTRUCTIONS

This project builds a Docker image for the Data Artifex API base.
This image extends the `dartfx/docker-base:latest` image and adds the necessary components to host FastAPI applications running with uvicorn.

## Dockerfile Structure

The Dockerfile is divided into two stages:

1. **Builder Stage**: This stage extends `dartfx/docker-base:latest` and uses the `uv` tool to build and sync the FastAPI and uvicorn dependencies into the virtual environment `/opt/venv`.
2. **Final Runtime Stage**: This stage extends `dartfx/docker-base:latest`, copies the updated Python virtual environment from the builder stage, copies a default mock `main.py` API, and exposes port 8000 for FastAPI.

## Python Packages

The Python packages are defined in the `pyproject.toml` file. The `uv` tool is used to build and sync the Python virtual environment.

## Extending Projects

All projects extending this base image must use Hatch, `uv`, and a `pyproject.toml` configuration file to declare metadata and dependencies.

