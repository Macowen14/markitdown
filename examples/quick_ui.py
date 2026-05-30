#!/usr/bin/env python3
"""FastAPI web UI for local MarkItDown usage.

Run the app and open http://127.0.0.1:8765/.
"""

from __future__ import annotations

import argparse
import socket
import sys
import tempfile
import traceback
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated, Any

import uvicorn
from fastapi import FastAPI, File, Form, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from markitdown import MarkItDown


BASE_DIR = Path(__file__).resolve().parent
TEMPLATES_DIR = BASE_DIR / "quick_ui_templates"
STATIC_DIR = BASE_DIR / "quick_ui_static"
RESULTS_DIR = Path(tempfile.gettempdir()) / "markitdown_quick_ui"
RESULTS_DIR.mkdir(parents=True, exist_ok=True)


SAMPLE_DIR = BASE_DIR.parent / "packages" / "markitdown" / "tests" / "test_files"
SAMPLE_FILES = [
    "test.pdf",
    "test.docx",
    "test.xlsx",
    "test.pptx",
    "test_blog.html",
    "test.jpg",
    "test.mp3",
    "test.epub",
    "test_files.zip",
]


@dataclass
class ConversionResult:
    markdown: str
    title: str
    source_name: str
    result_id: str


app = FastAPI(title="MarkItDown Quick UI")
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
templates = Jinja2Templates(directory=TEMPLATES_DIR)


class UserFacingConversionError(Exception):
    """A conversion error that is safe and useful to show in the UI."""


def sample_options() -> list[str]:
    return [name for name in SAMPLE_FILES if (SAMPLE_DIR / name).exists()]


def create_converter(
    *,
    enable_plugins: bool,
    vision_key: str = "",
    vision_model: str = "",
    cloud_mode: str = "local",
    cloud_endpoint: str = "",
    cloud_key: str = "",
) -> MarkItDown:
    kwargs: dict[str, Any] = {"enable_plugins": enable_plugins}

    if vision_key:
        try:
            from openai import OpenAI
        except ImportError as exc:
            raise UserFacingConversionError(
                "A vision/API key was provided, but the optional OpenAI client is not installed in this deployment."
            ) from exc
        kwargs["llm_client"] = OpenAI(api_key=vision_key)
        kwargs["llm_model"] = vision_model or "gpt-4o-mini"

    cloud_mode = cloud_mode.strip().lower() or "local"
    if cloud_mode != "local":
        if not cloud_endpoint:
            raise UserFacingConversionError(
                "Azure conversion was selected, but no Azure endpoint was provided."
            )
        if not cloud_key:
            raise UserFacingConversionError(
                "Azure conversion was selected, but no Azure API key was provided. Use local conversion or provide a key for this request."
            )
        try:
            from azure.core.credentials import AzureKeyCredential
        except ImportError as exc:
            raise UserFacingConversionError(
                "Azure conversion was selected, but Azure dependencies are not installed in this deployment."
            ) from exc

        credential = AzureKeyCredential(cloud_key)
        if cloud_mode == "docintel":
            kwargs["docintel_endpoint"] = cloud_endpoint
            kwargs["docintel_credential"] = credential
        elif cloud_mode == "cu":
            kwargs["cu_endpoint"] = cloud_endpoint
            kwargs["cu_credential"] = credential
        else:
            raise UserFacingConversionError(f"Unknown conversion mode: {cloud_mode}")

    return MarkItDown(**kwargs)


def convert_path(
    path: Path,
    *,
    source_name: str,
    converter: MarkItDown,
) -> ConversionResult:
    result = converter.convert(path)
    return save_result(result.markdown, source_name=source_name)


def convert_url(url: str, *, converter: MarkItDown) -> ConversionResult:
    result = converter.convert(url)
    return save_result(result.markdown, source_name=url)


def save_result(markdown: str, *, source_name: str) -> ConversionResult:
    result_id = uuid.uuid4().hex
    title = Path(source_name).name or "converted"
    output_path = result_path(result_id)
    output_path.write_text(markdown, encoding="utf-8")
    return ConversionResult(
        markdown=markdown,
        title=title,
        source_name=source_name,
        result_id=result_id,
    )


def result_path(result_id: str) -> Path:
    safe_id = "".join(ch for ch in result_id if ch.isalnum())
    return RESULTS_DIR / f"{safe_id}.md"


def render(
    request: Request,
    *,
    result: ConversionResult | None = None,
    error: str = "",
    url: str = "",
    selected_sample: str = "",
    enable_plugins: bool = False,
    cloud_mode: str = "local",
    cloud_endpoint: str = "",
    vision_model: str = "gpt-4o-mini",
) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "index.html",
        context={
            "request": request,
            "result": result,
            "error": error,
            "url": url,
            "selected_sample": selected_sample,
            "enable_plugins": enable_plugins,
            "cloud_mode": cloud_mode,
            "cloud_endpoint": cloud_endpoint,
            "vision_model": vision_model,
            "samples": sample_options(),
        },
    )


@app.get("/", response_class=HTMLResponse)
async def index(request: Request) -> HTMLResponse:
    return render(request)


@app.post("/convert", response_class=HTMLResponse)
async def convert(
    request: Request,
    source_url: Annotated[str, Form()] = "",
    sample_file: Annotated[str, Form()] = "",
    enable_plugins: Annotated[bool, Form()] = False,
    vision_key: Annotated[str, Form()] = "",
    vision_model: Annotated[str, Form()] = "gpt-4o-mini",
    cloud_mode: Annotated[str, Form()] = "local",
    cloud_endpoint: Annotated[str, Form()] = "",
    cloud_key: Annotated[str, Form()] = "",
    upload: Annotated[UploadFile | None, File()] = None,
) -> HTMLResponse:
    source_url = source_url.strip()
    cloud_endpoint = cloud_endpoint.strip()
    vision_model = vision_model.strip() or "gpt-4o-mini"

    try:
        converter = create_converter(
            enable_plugins=enable_plugins,
            vision_key=vision_key.strip(),
            vision_model=vision_model,
            cloud_mode=cloud_mode,
            cloud_endpoint=cloud_endpoint,
            cloud_key=cloud_key.strip(),
        )

        if upload is not None and upload.filename:
            suffix = Path(upload.filename).suffix
            with tempfile.NamedTemporaryFile(suffix=suffix) as tmp:
                tmp.write(await upload.read())
                tmp.flush()
                result = convert_path(
                    Path(tmp.name),
                    source_name=upload.filename,
                    converter=converter,
                )
            return render(
                request,
                result=result,
                url=source_url,
                selected_sample=sample_file,
                enable_plugins=enable_plugins,
                cloud_mode=cloud_mode,
                cloud_endpoint=cloud_endpoint,
                vision_model=vision_model,
            )

        if source_url:
            result = convert_url(source_url, converter=converter)
            return render(
                request,
                result=result,
                url=source_url,
                selected_sample=sample_file,
                enable_plugins=enable_plugins,
                cloud_mode=cloud_mode,
                cloud_endpoint=cloud_endpoint,
                vision_model=vision_model,
            )

        if sample_file:
            sample_path = SAMPLE_DIR / sample_file
            if not sample_path.exists() or sample_path.name != sample_file:
                raise ValueError("Unknown sample file.")
            result = convert_path(
                sample_path,
                source_name=sample_file,
                converter=converter,
            )
            return render(
                request,
                result=result,
                url=source_url,
                selected_sample=sample_file,
                enable_plugins=enable_plugins,
                cloud_mode=cloud_mode,
                cloud_endpoint=cloud_endpoint,
                vision_model=vision_model,
            )

        raise ValueError("Choose an upload, URL, or sample file.")
    except BrokenPipeError:
        raise
    except UserFacingConversionError as exc:
        return render(
            request,
            error=str(exc),
            url=source_url,
            selected_sample=sample_file,
            enable_plugins=enable_plugins,
            cloud_mode=cloud_mode,
            cloud_endpoint=cloud_endpoint,
            vision_model=vision_model,
        )
    except Exception as exc:
        traceback.print_exc()
        return render(
            request,
            error=friendly_error_message(exc),
            url=source_url,
            selected_sample=sample_file,
            enable_plugins=enable_plugins,
            cloud_mode=cloud_mode,
            cloud_endpoint=cloud_endpoint,
            vision_model=vision_model,
        )


def friendly_error_message(exc: Exception) -> str:
    message = str(exc)
    lower_message = message.lower()

    if "defaultazurecredential" in lower_message or "azure" in lower_message:
        return (
            "Azure conversion could not authenticate. Use local conversion, or provide an Azure endpoint and API key for this request."
        )

    if "api key" in lower_message and "openai" in lower_message:
        return (
            "This conversion needs an OpenAI-compatible API key. Add it in Advanced options for this request, or convert without the feature that requires it."
        )

    if "no module named 'openai'" in lower_message:
        return "The OpenAI client is not installed in this deployment, so vision/OCR features are unavailable."

    return message or "Conversion failed. Check the selected file, URL, and optional settings."


@app.get("/download/{result_id}")
async def download(result_id: str) -> FileResponse:
    path = result_path(result_id)
    if not path.exists():
        return RedirectResponse("/", status_code=303)
    return FileResponse(
        path,
        media_type="text/markdown; charset=utf-8",
        filename="markitdown-output.md",
    )


@app.get("/favicon.ico")
async def favicon() -> FileResponse:
    return FileResponse(STATIC_DIR / "favicon.svg", media_type="image/svg+xml")


def port_is_available(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.2)
        return sock.connect_ex((host, port)) != 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the MarkItDown FastAPI UI")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument(
        "--reload",
        action="store_true",
        help="Enable uvicorn reload while editing the UI.",
    )
    args = parser.parse_args()

    if not port_is_available(args.host, args.port):
        print(
            f"Port {args.port} is already in use. Try --port {args.port + 1} "
            f"or stop the existing process with: fuser -k {args.port}/tcp",
            file=sys.stderr,
        )
        raise SystemExit(98)

    print(f"Serving MarkItDown Quick UI at http://{args.host}:{args.port}/")
    uvicorn.run(
        "quick_ui:app" if args.reload else app,
        host=args.host,
        port=args.port,
        reload=args.reload,
        app_dir=str(BASE_DIR),
        log_level="info",
    )


if __name__ == "__main__":
    main()
