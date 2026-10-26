FROM ubuntu:26.04

# python3 runs melpazoid's checks, see tools/melpazoid.py.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      emacs-nox curl git ca-certificates python3 && \
    rm -rf /var/lib/apt/lists/*

# Eldev fetches itself on its first run, so that is done here, not on
# every `docker run'.  Not in root's home: the checks run as the host's
# user, see the Makefile.  A run's writes stay in its container.
ENV ELDEV_DIR=/opt/eldev
RUN curl -fsSL https://raw.githubusercontent.com/emacs-eldev/eldev/master/webinstall/eldev | sh && \
    mv /root/.local/bin/eldev /usr/local/bin/ && \
    eldev --version && \
    chmod -R a+rwX /opt/eldev
