# The dependencies are those of mayhem.el's Package-Requires header.
# Only that line goes on to the next stage, so they are fetched again
# when it changes, not on every edit of mayhem.el.
FROM ubuntu:26.04 AS header
COPY mayhem.el /src/
RUN printf ';;; mayhem.el --- Dependencies  -*- lexical-binding: t -*-\n;; Version: 0\n%s\n;;; mayhem.el ends here\n' \
      "$(grep '^;; Package-Requires:' /src/mayhem.el)" > /mayhem.el

# GUI Emacs under a virtual X display, to save pages as PNG.
FROM ubuntu:26.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      emacs-lucid xvfb xauth fonts-jetbrains-mono fonts-noto-color-emoji \
      curl git ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    curl -fsSL https://raw.githubusercontent.com/emacs-eldev/eldev/master/webinstall/eldev | sh

ENV PATH="/root/.local/bin:$PATH"

# The dependencies, in a layer of their own, so a run fetches nothing.
WORKDIR /deps
COPY Eldev .
COPY --from=header /mayhem.el .
RUN eldev prepare
ENV MAYHEM_DEPS=/deps
