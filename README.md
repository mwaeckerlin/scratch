# Docker Scratch Image with Definitions and Non Root User

Docker image from scratch with some basic definitions:
 - a non root user to run your services
 - a non root user to build your services
 - some variables to be used
 - a nice command line prompt

Image size: ca. 2.06kB (may change)

## Production Runtime Base

This image is the **runtime base** of the mwaeckerlin image family: use it as the **final stage** of every multi-stage build. It contains no shell, no package manager and no tools at all, and it already switches to the unprivileged `${RUN_USER}`, so every derived image starts non-root and headless by default.

Do the actual building in a build image such as [mwaeckerlin/very-base](https://github.com/mwaeckerlin/very-base), [mwaeckerlin/build](https://github.com/mwaeckerlin/build) or [mwaeckerlin/nodejs-build](https://github.com/mwaeckerlin/nodejs-build) — those are **build-only** images and must never run in production — then copy only the required runtime artifacts into the final stage based on this image.

For software built on Ubuntu, whose runtime artifacts need glibc, use [mwaeckerlin/ubuntu-scratch](https://github.com/mwaeckerlin/ubuntu-scratch) as the final stage instead: the same users with the same ids, the same variables, with the package commands of `apt`.

## Compile Time Arguments

- `lang` to set language, defaults to `en_US.UTF-8`

## Environment Arguments

The environment variables are intended to be used in derived images. They are not intended to be changed. Just use them instead of hard coding in your images.

### User Variables

Use these variables for user name, group and home:

- `RUN_USER`: set to `somebody`
- `RUN_GROUP`: set to `somebody`
- `RUN_HOME`: set to `/home/somebody`

If you need to share data on volumes between containers, and if you therefore must have a predefined group id, then use the following:

  - `SHARED_GROUP_NAME`: set to `shared-access`
  - `SHARED_GROUP_ID`: set to `500`

### Build Variables

Use these variables in `RUN` commands in your docker file. E.g. install package `gcc` (the GNU Compiler Collection) using: `RUN $PKG_INSTALL gcc`, or give the run user access to path `/target`: `RUN $ALLOW_USER /target`

  - `PKG_INSTALL`: set to `apk add --no-cache --clean-protected -u`
  - `PKG_REMOVE`: set to `apk del --no-cache --purge`
  - `PKG_SEARCH`: set to `apk search --no-cache`
  - `PKG_CLEANUP1`: set to `apk del --no-cache busybox alpine-baselayout`
  - `PKG_CLEANUP2`: set to `apk del --no-cache --purge apk-tools zlib alpine-keys`
  - `ALLOW_USER`: give access to a path to `$RUN_USER`, set to `chown -R ${RUN_USER}:${RUN_GROUP}`
  - `ALLOW_BUILD`: give access to a path to `$BUILD_USER`, set to `chown -R ${BUILD_USER}:${BUILD_GROUP}`

See [mwaeckerlin/nodejs-build](https://github.com/mwaeckerlin/nodejs-build) for an example of a build image.

Use these variables for user name, group and home at build time, use `$RUN_USER` at run time:

  - `BUILD_USER`: set to `coder`
  - `BUILD_GROUP`: set to `coder`
  - `BUILD_HOME`: set to `/home/coder`

Internally used system variables:

  - `LANG`: set to build argument `${lang}`, normally set to `en_US.UTF-8`
  - `PS1`: set to a nice console prompt

## Publishing on Docker Hub

Every image repository of the family builds and publishes its images with the reusable GitHub Actions workflow [`.github/workflows/docker-image.yml`](.github/workflows/docker-image.yml) of this repository. On every push to the default branch, on a weekly schedule and on a manual start it:

1. builds every service of `docker-compose.yml` that has both `build` and `image`, with `docker compose build`; a service whose build context lies in a git submodule is left to the submodule's own repository
2. does this on a native runner per architecture, `linux/amd64` on `ubuntu-24.04` and `linux/arm64` on `ubuntu-24.04-arm`, without emulation
3. runs `npm ci` where a `package-lock.json` exists, then `npm test`
4. runs `npm run deploy` with a compose override that gives each image an architecture tag, so it pushes `mwaeckerlin/rsync:latest-amd64` and `mwaeckerlin/rsync:latest-arm64`
5. in the final job `deploy`, joins the architecture tags into every tag of the image, from which docker pulls the variant that fits the host

### Tags

Every image is published under its tag, the date of the build (UTC) and, where `package.json` carries a version, the version with and without the date, so a rebuild of the same version stays addressable:

| Compose image | Published tags |
| --- | --- |
| `mwaeckerlin/rsync` | `latest`, `20260926`, `1.3.2`, `1.3.2-20260926` |
| `mwaeckerlin/rsync:inotify` | `inotify`, `inotify-20260926`, `inotify-1.3.2`, `inotify-1.3.2-20260926` |

A repository that builds several versions from branches — Nextcloud upgrades one major version at a time, so each major version has its own image — names its branches in `branch-tags`: the first rule whose `branch` (a Python regular expression, matched in full) fits the branch name appends its `suffix` to every tag. With the rules `[{"branch": "new-([0-9]+)", "suffix": "-\\1"}, {"branch": "new", "suffix": ""}]`, branch `new-33` publishes `nginx-33`, `nginx-33-20260926`, `nginx-33-1.1.2` and `nginx-33-1.1.2-20260926`. GitHub starts scheduled runs on the default branch only, so there the job `branches` starts the workflow `docker.yml` on every other branch a rule names; the weekly rebuild thereby reaches every version.

Every step must succeed: a failed build, test or push stops the run, and the plain tag keeps the last version that passed on every architecture. A repository that builds nothing of its own fails the run with an error.

Every image repository therefore carries the npm scripts `test` and `deploy`. `deploy` is `docker compose push`, or `docker compose push <service> …` with the own services where the compose file also starts foreign images; run on its own, it pushes the image of the machine it runs on.

### The caller

Each repository carries this file as `.github/workflows/docker.yml`:

```yaml
name: docker

on:
  push:
    branches: [master]
  schedule:
    - cron: "17 5 * * 1"
  workflow_dispatch:

concurrency: docker-${{ github.ref_name }}

jobs:
  docker:
    uses: mwaeckerlin/scratch/.github/workflows/docker-image.yml@master
    secrets: inherit
```

The weekly rebuild runs on Monday, one hour per level after the images a repository is built on: `mwaeckerlin/scratch` and `mwaeckerlin/ubuntu-base` at 03:17, `mwaeckerlin/very-base` at 04:17, the images built on `very-base` at 05:17, and so on. That way each rebuild finds the security fixes of its base.

A repository that deviates adds a `with:` block:

```yaml
    with:
      test: npm test
      architectures: '["amd64"]'
      free-disk: true
```

- `test`: command that tests the built images; the run stops before the push when it fails; default: `npm test`, empty for none
- `architectures`: JSON list of the architectures; default: `["amd64", "arm64"]`
- `branch-tags`: JSON list of `{"branch": <regex>, "suffix": <template>}` for repositories with version branches; default: `[]`. Such a caller also runs on those branches and grants the weekly job `actions: write`:

  ```yaml
  on:
    push:
      branches: [master, new, "new-*"]
    schedule:
      - cron: "17 6 * * 1"
    workflow_dispatch:

  concurrency: docker-${{ github.ref_name }}

  jobs:
    docker:
      uses: mwaeckerlin/scratch/.github/workflows/docker-image.yml@master
      permissions:
        actions: write
        contents: read
      with:
        branch-tags: '[{"branch": "new-([0-9]+)", "suffix": "-\\1"}, {"branch": "new", "suffix": ""}]'
      secrets: inherit
  ```

  The same file stands on every one of those branches, and the scheduled run of the default branch starts the others.
- `free-disk`: removes the preinstalled SDKs of the runner (.NET, Android, Haskell, the tool cache) and the preloaded Docker images before the build; measured on 2026-09-26, the runners have a 145GB root with 87GB (amd64) and 108GB (arm64) free, and the clean-up raises that to 114GB and 123GB; default: `false`

### Setup

Docker Hub and GitHub need one access token, stored in every image repository:

1. On Docker Hub, «Account settings» → «Personal access tokens» → «Generate new token», access permission «Read & Write».
2. Store it as the secret `DOCKERHUB_TOKEN` in every repository. With the GitHub CLI, the token is read once, without echo, and never appears on a command line:

   ```bash
   $ read -rs DOCKERHUB_TOKEN
   $ for repo in scratch very-base build; do printf %s "$DOCKERHUB_TOKEN" | gh secret set DOCKERHUB_TOKEN --repo mwaeckerlin/$repo; done
   ```

   In the web interface: repository → «Settings» → «Secrets and variables» → «Actions» → «New repository secret».
3. The Docker Hub user is the GitHub owner of the repository. Where it differs, set the repository variable `DOCKERHUB_USERNAME`.

The standard GitHub runners, including the arm64 ones, are free for public repositories.
