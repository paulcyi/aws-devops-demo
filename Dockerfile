# Use a lightweight Python 3 base image
FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Install system dependencies (optional, for future-proofing)
RUN apt-get update && apt-get install -y \
  gcc \
  && rm -rf /var/lib/apt/lists/*

# Copy requirements first so Docker can cache this layer
COPY app/requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the app
COPY app/ /app/

# Expose the port for Flask
EXPOSE 5001

# Command to start the Flask app
CMD ["python", "main.py"]