# Changelog

- 2026-07-17 **1.1.1**
    - Documentation now states the image's role explicitly: runtime base for the final stage of multi-stage builds, in contrast to the build-only images that must never run in production
    - Image build no longer emits warnings (modernized instruction format)

- 2026-07-14 **1.1.0**
    - The shipped image is now automatically verified to contain no shell and no scripting language — an attacker who reaches code execution in the container finds no tool to pivot with
