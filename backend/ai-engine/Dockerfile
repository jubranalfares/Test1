FROM python:3.11-slim

# Install all system dependencies needed for faster-whisper + audio
RUN apt-get update && apt-get install -y \
    ffmpeg \
    libsndfile1 \
    libsndfile1-dev \
    wget \
    curl \
    build-essential \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Upgrade pip first to get latest wheel support
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Install numpy first (required by faster-whisper/ctranslate2)
RUN pip install --no-cache-dir numpy==1.26.4

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8001

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
