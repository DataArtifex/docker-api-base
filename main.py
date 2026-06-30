from fastapi import FastAPI

app = FastAPI(title="Data Artifex API Base")

@app.get("/")
def read_root():
    return {
        "status": "ok",
        "message": "Data Artifex API Base is running."
    }
