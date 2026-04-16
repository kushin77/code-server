# Container Image Security Policy — Issue #357
# Validates image provenance + vulnerability status (NIST 800-190)

package images.security

deny[msg] {
    # Enforce approved base images
    image := input.image
    approved_bases := [
        "ubuntu:22.04",
        "debian:bookworm",
        "alpine:3.18",
        "postgres:15",
        "redis:7",
        "codercom/code-server:4.115.0",
        "grafana/grafana:10.2.3",
        "prom/prometheus:v2.48.0",
        "prom/alertmanager:v0.26.0",
        "jaegertracing/all-in-one:1.50",
        "haproxy:2.8-alpine",
        "caddy:2.7",
        "quay.io/oauth2-proxy/oauth2-proxy:v7.5.1"
    ]
    not image_in_list(image, approved_bases)
    msg := sprintf("Image %s: not in approved base image list", [image])
}

deny[msg] {
    # Check image signature present
    signature := input.signature
    not signature
    msg := "Container: Image signature missing - sign with cosign"
}

deny[msg] {
    # Check SBOM present
    sbom := input.sbom
    not sbom
    msg := "Container: SBOM (Software Bill of Materials) missing - generate with syft"
}

deny[msg] {
    # Check vulnerability scan clean (Trivy)
    scan := input.vulnerability_scan
    scan.critical_count > 0
    msg := sprintf("Image: %d critical vulnerabilities detected - remediate before deployment", [scan.critical_count])
}

deny[msg] {
    scan := input.vulnerability_scan
    scan.high_count > 5
    msg := sprintf("Image: %d high-severity vulnerabilities detected - remediate or document waivers", [scan.high_count])
}

# Helper functions
image_in_list(image, list) {
    list[_] == image
}
