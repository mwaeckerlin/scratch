# Changelog

- 2026-10-21 **1.1.10**
    - Before a build overwrites a tag, the image it replaces gets the tag with the day it was built, so an earlier version stays reachable for a revert also where it was published without a date

- 2026-10-21 **1.1.9**
    - The workflow, its documentation and its contract name no repository that builds on this one; every caller names its own rules

- 2026-10-21 **1.1.8**
    - The examples of the documentation and of the workflow contract name no image of another repository

- 2026-10-21 **1.1.7**
    - A rule of `branch-tags` may put a prefix before the version, so branch `2.x` publishes `app-2-v2.1.0`, the form of its git tags

- 2026-10-21 **1.1.6**
    - The input `ref` builds a git tag of a released version, a `tag` rule of `branch-tags` gives its suffix, and the weekly run rebuilds every such git tag, so a released version gets the security fixes of its base images

- 2026-09-26 **1.1.5**
    - The documentation of `free-disk` gives the measured disk space of the runners in place of an outdated size

- 2026-09-26 **1.1.4**
    - The shared workflow checks out the submodules too, so a test that builds an image from a submodule runs in the pipeline as it does locally

- 2026-09-26 **1.1.3**
    - The shared workflow starts in every repository again: a repository whose workflow token may only read ended every run at start, because the weekly job asked for rights of its own even where it never runs; the rights now come from the caller only

- 2026-09-26 **1.1.2**
    - The image is published for amd64 and arm64 under one tag, built and published automatically on every change and every week
    - Every image is published under its tag, the date of the build, and the version with and without the date, so every rebuild stays addressable; repositories with version branches build and publish every version, also in the weekly rebuild
    - One shared build, test and deploy workflow for every image of the family, documented in the README: an image reaches Docker Hub only when its build, its tests and its deploy succeeded on every architecture
    - The documentation names mwaeckerlin/ubuntu-scratch as the final stage for software built on Ubuntu

- 2026-07-17 **1.1.1**
    - Documentation now states the image's role explicitly: runtime base for the final stage of multi-stage builds, in contrast to the build-only images that must never run in production
    - Image build no longer emits warnings (modernized instruction format)

- 2026-07-14 **1.1.0**
    - The shipped image is now automatically verified to contain no shell and no scripting language — an attacker who reaches code execution in the container finds no tool to pivot with
