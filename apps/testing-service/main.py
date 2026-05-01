from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="testing-service", version="1.0.0")


class TestRequest(BaseModel):
    suite: str = "smoke"


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "testing-service"}


@app.post("/run")
def run_tests(request: TestRequest) -> dict[str, str]:
    # Placeholder runner endpoint until full test orchestration is wired.
    return {"status": "accepted", "suite": request.suite}


if __name__ == "__main__":
    import config as _cfg
    import uvicorn
    uvicorn.run(app, host=_cfg.HOST, port=_cfg.PORT)
