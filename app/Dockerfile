FROM python:3.11-slim
RUN pip install --no-cache-dir flask
WORKDIR /app
COPY main.py .
EXPOSE 5000
CMD ["python", "main.py"]
