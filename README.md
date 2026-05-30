# MarkItDown Workbench

MarkItDown Workbench is a local document-to-Markdown tool built on top of Microsoft's MIT-licensed MarkItDown project. It keeps the original converter library, adds a FastAPI browser UI, and gives you a quick way to test uploads, URLs, and bundled sample files.

The goal is simple: drop in a PDF, Office document, HTML page, image, audio file, ZIP, EPUB, JSON, CSV, XML, or plain text file and get clean Markdown back for LLM workflows, notes, indexing, or analysis.

## What Is Included

- The upstream `markitdown` Python package under `packages/markitdown`.
- Built-in converters for PDF, DOCX, XLSX, PPTX, HTML, images, audio, ZIP, EPUB, CSV, JSON, XML, RSS, YouTube transcripts, and more.
- Optional plugin support through the MarkItDown plugin entry point system.
- A local FastAPI UI at `examples/quick_ui.py`.
- Separate UI templates and static assets in:
  - `examples/quick_ui_templates/`
  - `examples/quick_ui_static/`
- A Markdown download endpoint for converted output.
- Environment-key visibility for optional LLM, OCR, Azure, and metadata features.

## Setup

This project should run in a virtual environment. Do not install into the system Python on Debian, Parrot, Kali, Ubuntu, or other PEP 668-managed systems.

Recommended setup:

```bash
cd /home/macowenk/Desktop/tools/markitdown
./start.sh install
```

The launcher creates `.venv` automatically. If `uv` is available it uses `uv venv` and `uv pip`; otherwise it falls back to `python3 -m venv` and `pip`.

If port `8765` is already in use:

```bash
fuser -k 8765/tcp
```

Or run the UI on another port:

```bash
uv run examples/quick_ui.py --port 8766
```

## Run The UI

Recommended launcher:

```bash
./start.sh run
```

See all launcher commands:

```bash
./start.sh --help
```

Check or update optional environment variables:

```bash
./start.sh env status
./start.sh env set OPENAI_API_KEY
./start.sh env edit
```

Direct command:

```bash
uv run examples/quick_ui.py
```

Open:

```text
http://127.0.0.1:8765/
```

The UI lets you:

- Upload a local file.
- Convert a remote URL.
- Pick a bundled test sample.
- Let MarkItDown automatically choose the converter.
- Enable installed plugins.
- Preview Markdown in the browser.
- Download the converted `.md` file.

Architecture diagrams are in `mermaid.md`.

## Docker

Build the local UI image:

```bash
docker build -t markitdown-workbench:local .
```

Run it:

```bash
docker run --rm -p 8765:8765 --env-file .env markitdown-workbench:local
```

Or use Compose:

```bash
cp .env.example .env
docker compose up --build
```

Open:

```text
http://127.0.0.1:8765/
```

Smaller image options:

```bash
# Keep common document support but skip broad [all] extras.
docker build \
  --build-arg MARKITDOWN_EXTRAS=pdf,docx,pptx,xlsx \
  -t markitdown-workbench:docs .

# Skip ffmpeg/exiftool OS packages.
docker build \
  --build-arg INSTALL_MEDIA_TOOLS=false \
  -t markitdown-workbench:small .

# Core package only, smallest but fewer formats.
docker build \
  --build-arg MARKITDOWN_EXTRAS= \
  --build-arg INSTALL_MEDIA_TOOLS=false \
  -t markitdown-workbench:core .
```

The Dockerfile uses `python:3.13-slim-bookworm`, not Alpine. Alpine is small, but MarkItDown's Magika/ONNX and several document dependencies rely on glibc/manylinux wheels. Alpine often forces source builds or fails on musl-based images, which can make the build slower, larger, or less reliable.

To pin Debian package versions, pass exact versions available from the selected Debian repository:

```bash
docker build \
  --build-arg 'APT_MEDIA_PACKAGES=ffmpeg=7:5.1.6-0+deb12u1 libimage-exiftool-perl=12.57+dfsg-1' \
  -t markitdown-workbench:pinned .
```

Only pin versions that exist in the base image repository at build time.

### Online Deployment

Do not bake secrets into the image. Keep `OPENAI_API_KEY`, Azure credentials, and plugin flags as runtime environment variables.

Typical flow:

```bash
docker build -t your-registry/markitdown-workbench:latest .
docker push your-registry/markitdown-workbench:latest
```

Then configure environment variables in the hosting provider dashboard or secret manager:

```text
OPENAI_API_KEY
EXIFTOOL_PATH
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_CLIENT_SECRET
MARKITDOWN_ENABLE_PLUGINS
MARKITDOWN_HOST=0.0.0.0
MARKITDOWN_PORT=8765
```

For public deployments, add authentication in front of the app before exposing it. MarkItDown can read uploaded files, fetch URLs, and process data with the permissions of the container, so do not expose an unauthenticated instance to the internet.

## Command Line Usage

Convert a local file:

```bash
uv run markitdown path/to/document.pdf -o document.md
```

Print output to the terminal:

```bash
uv run markitdown path/to/document.docx
```

Use stdin:

```bash
cat path/to/document.pdf | uv run markitdown -x pdf > document.md
```

List installed plugins:

```bash
uv run markitdown --list-plugins
```

## Python API

```python
from markitdown import MarkItDown

converter = MarkItDown()
result = converter.convert("document.pdf")
print(result.markdown)
```

For server-side or untrusted input, prefer the narrowest method that fits:

```python
converter.convert_local("document.pdf")
converter.convert_stream(file_obj)
converter.convert_response(response)
```

Avoid passing untrusted user input directly to the broad `convert()` method unless you have validated file paths, URL schemes, and network destinations.

## Optional Environment Keys

The basic local converters do not need API keys.

Optional features may use:

| Variable | Used For |
| --- | --- |
| `OPENAI_API_KEY` | LLM image descriptions and OCR-style plugin workflows. |
| `EXIFTOOL_PATH` | Image/audio metadata extraction with a specific `exiftool` binary. |
| `AZURE_CLIENT_ID` | Azure service principal authentication. |
| `AZURE_TENANT_ID` | Azure service principal tenant. |
| `AZURE_CLIENT_SECRET` | Azure service principal secret. |
| `MARKITDOWN_ENABLE_PLUGINS` | Enables plugins in MCP/server workflows when set to `true`, `1`, or `yes`. |

Set keys in your shell before running the UI:

```bash
export OPENAI_API_KEY="..."
export EXIFTOOL_PATH="/usr/bin/exiftool"
uv run examples/quick_ui.py
```

The UI only shows whether keys are set. It does not print secret values.

## Package Map

```text
packages/markitdown              Main converter library and CLI
packages/markitdown-mcp          MCP server wrapper
packages/markitdown-ocr          Optional OCR plugin using LLM vision
packages/markitdown-sample-plugin Example converter plugin
examples/quick_ui.py             FastAPI browser UI
```

## Development Checks

```bash
uv run python -m py_compile examples/quick_ui.py
uv run python -m pytest packages/markitdown/tests/test_module_misc.py::test_plain_text_falls_back_from_incorrect_ascii_hint
uv run python -m pytest packages/markitdown/tests/test_module_vectors.py::test_convert_local
```

## License And Attribution

This work is based on Microsoft MarkItDown, which is licensed under the MIT License. The original license and third-party notices remain in this repository:

- `LICENSE`
- `packages/markitdown/ThirdPartyNotices.md`

MIT licensing allows you to modify, rename, distribute, and build on the project, but you should keep the original copyright and license notices.
