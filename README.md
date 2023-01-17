# Docker Scratch Image with Definitions and Non Root User

Docker image from scratch with some basic definitions:
 - a non root user to run your services
 - a non root user to build your services
 - some variables to be used
 - a nice command line prompt

Image size: ca. 2.06kB (may change)

## Compile Time Arguments

- `lang` to set language, defaults to `en_US.UTF-8`

## Environment Arguments

The environment variables are intended to be used in derieved images. They are not intended to be changed. Just use them instread of hard coding in your images.

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
