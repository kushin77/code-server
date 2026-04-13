import base64, hashlib, secrets

def generate_code_verifier(length: int = 64) -> str:
    return secrets.token_urlsafe(length)[:128]

def compute_code_challenge(verifier: str) -> str:
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
