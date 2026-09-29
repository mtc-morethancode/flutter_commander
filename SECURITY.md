# Security Policy

The `flutter_commander` team takes the security of our state management and architectural framework seriously. This document outlines how we handle security vulnerabilities and how to report them responsibly.

---

## 🛡️ Supported Versions

We provide security updates and critical patches for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0.0 | :x:                |

---

## 🔒 Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

If you discover a security vulnerability, concurrency race-condition leak, or denial-of-service issue in `flutter_commander`, please report it via one of the following methods:

### Method 1: GitHub Private Vulnerability Reporting (Recommended)
1. Go to the [Security Advisories tab](https://github.com/mtc-morethancode/flutter_commander/security/advisories) of this repository.
2. Click **"Report a vulnerability"**.
3. Fill out the details including proof of concept, impact, and affected versions.

### Method 2: Direct Email
Send an email to **mtc.morethancode@gmail.com** with:
* Description of the vulnerability.
* Steps to reproduce or proof of concept code / test case.
* Potential impact.
* Suggested fix (if available).

---

## ⏱️ Response Timeline

* **Acknowledgment:** We will acknowledge receipt of your vulnerability report within **48 hours**.
* **Assessment:** We will confirm the issue, evaluate its severity, and determine an impact rating within **5 business days**.
* **Remediation:** We aim to release a patched version and coordinate disclosure within **30 days** of initial confirmation.

---

## 📜 Coordinated Disclosure

We believe in coordinated vulnerability disclosure. We ask that you give us adequate time to investigate and resolve the issue before publishing any details publicly. Once a fix is verified and released, full credit will be given to the reporter (unless you prefer to remain anonymous).
