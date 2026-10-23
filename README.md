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

Every image repository of the family builds and publishes its images with the reusable GitHub Actions workflow [`.github/workflows/docker-image.yml`](.github/workflows/docker-image.yml) of this repository. On every push to the default branch, on a manual start, and in an hourly scheduled run when a source of the images changed (see [Source check](#source-check)), it:

1. builds every service of `docker-compose.yml` that has both `build` and `image`, with `docker compose build`; a service whose build context lies in a git submodule is left to the submodule's own repository
2. does this on a native runner per architecture, `linux/amd64` on `ubuntu-24.04` and `linux/arm64` on `ubuntu-24.04-arm`, without emulation
3. runs `npm ci` where a `package-lock.json` exists, then `npm test`
4. runs `npm run deploy` with a compose override that gives each image an architecture tag, so it pushes `mwaeckerlin/x:latest-amd64` and `mwaeckerlin/x:latest-arm64`
5. in the final job `deploy`, joins the architecture tags into every tag of the image, from which docker pulls the variant that fits the host

### Tags

Every image is published under its tag, the date of the build (UTC) and, where `package.json` carries a version, the version with and without the date, so a rebuild of the same version stays addressable:

| Compose image | Published tags |
| --- | --- |
| `mwaeckerlin/x` | `latest`, `20260926`, `1.3.2`, `1.3.2-20260926` |
| `mwaeckerlin/x:inotify` | `inotify`, `inotify-20260926`, `inotify-1.3.2`, `inotify-1.3.2-20260926` |

Before the new image takes a tag, the image that carried it gets the same tag with the day it was built, `20180304` for `latest` and `inotify-20180304` for `inotify`, unless such a tag already exists. An image published before the date tags existed stays reachable for a revert.

A repository that builds several versions from branches names its branches in `branch-tags`: the first rule whose `branch` (a Python regular expression, matched in full) fits the branch name appends its `suffix` to every tag. With the rules `[{"branch": "new-([0-9]+)", "suffix": "-\\1"}, {"branch": "new", "suffix": ""}]`, branch `new-33` publishes `nginx-33`, `nginx-33-20260926`, `nginx-33-1.1.2` and `nginx-33-1.1.2-20260926`. GitHub starts scheduled runs on the default branch only, so there the job `branches` starts the workflow `docker.yml` on every other branch a rule names; the hourly check thereby reaches every version.

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
    - cron: "17 * * * *"
  workflow_dispatch:

concurrency: docker-${{ github.ref_name }}

jobs:
  docker:
    uses: mwaeckerlin/scratch/.github/workflows/docker-image.yml@master
    permissions:
      actions: write
      contents: read
    secrets: inherit
```

`actions: write` lets the scheduled run enable the workflow `docker.yml` of the repository through the GitHub API (see [Keep-alive](#keep-alive)); without it the run leaves a warning and builds as before.

Every repository uses the same hourly schedule. The scheduled run builds only when a source changed, so no repository needs a clock time after the images it is built on: a child sees a new parent image within the hour after the parent's run published it, and a chain of seven levels is through in about seven to eight hours.

A repository that deviates adds a `with:` block:

```yaml
    with:
      test: npm test
      architectures: '["amd64"]'
      free-disk: true
```

- `test`: command that tests the built images; the run stops before the push when it fails; default: `npm test`, empty for none
- `architectures`: JSON list of the architectures; default: `["amd64", "arm64"]`
- `branch-tags`: JSON list of `{"branch": <regex>, "suffix": <template>}` for repositories with version branches; default: `[]`. Such a caller also runs on those branches and grants the job `branches` `actions: write`:

  ```yaml
  on:
    push:
      branches: [master, new, "new-*"]
    schedule:
      - cron: "17 * * * *"
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

  A rule may carry `"version": "v"`, which puts `v` before the version: branch `2.x` with `{"branch": "([0-9]+)\\.x", "suffix": "-\\1", "version": "v"}` publishes `app-2-v2.1.0`. A rule with `tag` in place of `branch` names git tags of released versions: with `{"tag": "([0-9]+-v[0-9.]+)", "suffix": "-\\1"}`, the input `ref: 2-v2.0.5` builds that git tag and publishes `app-2-v2.0.5` and `app-2-v2.0.5-20261021`, without the version of `package.json`, because the git tag is the version. The scheduled run starts `docker.yml` of the default branch with `ref` for every git tag such a rule names, so the caller passes its own dispatch input `ref` on. A git tag older than the `deploy` script is pushed with `docker compose push` of its services.
- `ref`: git tag to build in place of the branch that started the run; default: empty
- `free-disk`: removes the preinstalled SDKs of the runner (.NET, Android, Haskell, the tool cache) and the preloaded Docker images before the build; measured on 2026-09-26, the runners have a 145GB root with 87GB (amd64) and 108GB (arm64) free, and the clean-up raises that to 114GB and 123GB; default: `false`
- `rebuild-days`: a scheduled run builds an image whose sources are unchanged once it is this many days old; default: `7`

### Source check

A push, a manual start and a git tag release always build. A scheduled run, and a run the scheduled run starts on a version branch or for a git tag, first runs the job `check`, which compares the sources of the images with what the published images were built from, prints every difference, and starts the build only where one exists:

| Source | What the check compares |
| --- | --- |
| Parent image | the digest of every image a Dockerfile of the compose file names in `FROM` or `COPY --from`, with the defaults of a global `ARG` and the `args` of the compose file filled in; stage names, `scratch` and the images the compose file builds itself are no parents |
| Download | every literal address in `ADD` and in a `RUN` that calls `wget` or `curl`: an address below `/releases/latest`, the form of GitHub, by the release the redirect names; any other address by the `ETag` or `Last-Modified` of a HEAD request |
| Age | the published image is rebuilt once it is `rebuild-days` old |
| Published image | an image that is not published yet, or was published without a record of its sources, is built |

Packages that `apk`, `apt`, `npm`, `pip` or `composer` install are not compared one by one: the final images carry no package database, the `docker compose build` of the workflow writes no SBOM attestation, and the build stages that do carry the database are not reachable from the workflow. The build after `rebuild-days` covers them, and so it covers an address that a `RUN` assembles in shell code, which the check names in its output.

Each build records its sources as the image labels `org.mwaeckerlin.parents` and `org.mwaeckerlin.downloads`, JSON objects from parent to digest and from address to version, through a compose override the workflow writes for the build. The check reads them, and the build time, from the image configuration of the first platform of the published image. Annotations of the published index cannot carry them: `docker buildx imagetools create` joins images that `docker compose push` pushed in the Docker media types into a Docker manifest list, which has no annotations, and drops them without an error.

Every registry request of the check goes through `docker buildx imagetools inspect`, logged in with `DOCKERHUB_TOKEN`. Docker Hub counts a GET of a manifest as a pull and a HEAD as none ([Docker Hub pull usage and limits](https://docs.docker.com/docker-hub/usage/pulls/)). `imagetools inspect` resolves the tag with a HEAD and then fetches the manifest with a GET, so each parent image costs one pull, and each published image at most three: the manifest list, then the manifest and the configuration of one platform. A Docker Hub Personal account has 200 pulls per six hours, the paid accounts have no limit ([Docker Hub usage and limits](https://docs.docker.com/docker-hub/usage/)).

### Keep-alive

GitHub disables the scheduled workflows of a public repository after 60 days without activity in it ([Disabling and enabling a workflow](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/disabling-and-enabling-a-workflow)). A push counts as activity. Each scheduled run therefore enables its own calling workflow with `gh api -X PUT repos/<owner>/<repository>/actions/workflows/docker.yml/enable`, which needs the `actions: write` the caller grants. Whether this call resets the 60 days, GitHub does not document. A workflow that was disabled anyway is enabled again with `gh workflow enable docker.yml --repo <owner>/<repository>`.

### Setup

Docker Hub and GitHub need one access token, stored in every image repository:

1. On Docker Hub, «Account settings» → «Personal access tokens» → «Generate new token», access permission «Read & Write».
2. Store it as the secret `DOCKERHUB_TOKEN` in every repository. With the GitHub CLI, the token is read once, without echo, and never appears on a command line:

   ```bash
   read -rs DOCKERHUB_TOKEN
   for repo in scratch very-base build; do printf %s "$DOCKERHUB_TOKEN" | gh secret set DOCKERHUB_TOKEN --repo mwaeckerlin/$repo; done
   ```

   In the web interface: repository → «Settings» → «Secrets and variables» → «Actions» → «New repository secret».
3. The Docker Hub user is the GitHub owner of the repository. Where it differs, set the repository variable `DOCKERHUB_USERNAME`.

The standard GitHub runners, including the arm64 ones, are free for public repositories.
