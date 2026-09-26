# Changelog

- 2026-09-26 **1.1.2**
    - The image is published for amd64 and arm64 under one tag, built and published automatically on every change and every week
    - Every image is published under its tag, the date of the build, and the version with and without the date, so every rebuild stays addressable; repositories with version branches, such as the Nextcloud images, build and publish every version, also in the weekly rebuild
    - One shared build, test and deploy workflow for every image of the family, documented in the README: an image reaches Docker Hub only when its build, its tests and its deploy succeeded on every architecture
    - The documentation names mwaeckerlin/ubuntu-scratch as the final stage for software built on Ubuntu

- 2026-07-17 **1.1.1**
    - Documentation now states the image's role explicitly: runtime base for the final stage of multi-stage builds, in contrast to the build-only images that must never run in production
    - Image build no longer emits warnings (modernized instruction format)

- 2026-07-14 **1.1.0**
    - The shipped image is now automatically verified to contain no shell and no scripting language — an attacker who reaches code execution in the container finds no tool to pivot with
