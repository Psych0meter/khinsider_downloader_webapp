FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY app.py .
COPY templates/ ./templates/

# Create a volume for downloads
RUN mkdir /downloads
VOLUME /downloads

# Standard Flask port
EXPOSE 5000

CMD ["python", "app.py"]