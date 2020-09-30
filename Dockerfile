FROM scratch
MAINTAINER mwaeckerlin
ARG lang="en_US.UTF-8"

# change in childern:
ENV CONTAINERNAME     "scratch"

ENV RUN_USER          "somebody"
ENV RUN_GROUP         "somebody"
ENV RUN_HOME          "/home/somebody"

ENV LANG              "${lang}"
ENV SHARED_GROUP_NAME "shared-access"
ENV SHARED_GROUP_ID   "500"
ENV PS1               '\[\033[36;1m\]\u\[\033[97m\]@\[\033[32m\]${CONTAINERNAME}[\[\033[36m\]\h\[\033[97m\]]:\[\033[37m\]\w\[\033[0m\]\$ '

ENV PKG_INSTALL "apk add --no-cache --clean-protected -u"
ENV PKG_REMOVE  "apk del --no-cache --purge"
ENV PKG_SEARCH  "apk search --no-cache"
ENV ALLOW_USER  "chown -R ${RUN_USER}:${RUN_GROUP}"

# allow derieved images to overwrite the language
ONBUILD ARG lang
ONBUILD ENV LANG=${lang:-${LANG}}
