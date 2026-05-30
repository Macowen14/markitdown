# syntax=docker/dockerfile:1.7
#
# MarkItDown Workbench container.
#
# Alpine is intentionally not used here. MarkItDown depends on Magika/ONNX and
# several document-processing libraries that publish glibc/manylinux wheels.
# A Debian slim image is usually smaller and more reliable than compiling those
# dependencies against Alpine's musl libc.

ARG PYTHON_VERSION=3.13
FROM python:${PYTHON_VERSION}-slim-bookworm AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    EXIFTOOL_PATH=/usr/bin/exiftool \
    MARKITDOWN_HOST=0.0.0.0 \
    MARKITDOWN_PORT=8765

WORKDIR /app

# Optional OS runtime tools:
# - libimage-exiftool-perl provides /usr/bin/exiftool for image/audio metadata.
# - ffmpeg enables broader audio handling through pydub/SpeechRecognition.
#
# To reduce image size, build with:
#   --build-arg INSTALL_MEDIA_TOOLS=false
#
# To pin Debian package versions, override APT_MEDIA_PACKAGES with exact
# package=version values available in the selected Debian repository.
ARG INSTALL_MEDIA_TOOLS=true
ARG APT_MEDIA_PACKAGES="ffmpeg libimage-exiftool-perl"
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    apt-get update; \
    if [ "$INSTALL_MEDIA_TOOLS" = "true" ]; then \
        apt-get install -y --no-install-recommends $APT_MEDIA_PACKAGES; \
    fi; \
    apt-get purge -y --auto-remove; \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/requirements.txt
COPY packages/markitdown /app/packages/markitdown
COPY examples /app/examples
COPY README.md LICENSE /app/

# Install the local package first, then the UI/runtime requirements.
# Full support is the default. For smaller images, use a narrower extras list:
#   --build-arg MARKITDOWN_EXTRAS=pdf,docx,pptx,xlsx
# Or install only core dependencies:
#   --build-arg MARKITDOWN_EXTRAS=
ARG MARKITDOWN_EXTRAS=all
RUN set -eux; \
    python -m pip install --upgrade pip; \
    if [ -n "$MARKITDOWN_EXTRAS" ]; then \
        python -m pip install "/app/packages/markitdown[$MARKITDOWN_EXTRAS]"; \
    else \
        python -m pip install /app/packages/markitdown; \
    fi; \
    python -m pip install -r /app/requirements.txt; \
    python -m py_compile /app/examples/quick_ui.py

RUN useradd --create-home --shell /usr/sbin/nologin appuser
USER appuser

EXPOSE 8765

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request, os; urllib.request.urlopen(f'http://127.0.0.1:{os.getenv(\"MARKITDOWN_PORT\", \"8765\")}/', timeout=3).read()" || exit 1

CMD ["sh", "-c", "python /app/examples/quick_ui.py --host ${MARKITDOWN_HOST} --port ${MARKITDOWN_PORT}"]
