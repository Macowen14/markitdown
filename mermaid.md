# MarkItDown Workbench Architecture

This file uses Mermaid diagrams to show how this Microsoft MarkItDown-based project is organized and how data moves through the converter, UI, plugins, and optional cloud integrations.

## Repository Map

```mermaid
flowchart TB
    Root["markitdown/"]
    MainPkg["packages/markitdown<br/>Core library and CLI"]
    MCPPkg["packages/markitdown-mcp<br/>MCP server wrapper"]
    OCRPkg["packages/markitdown-ocr<br/>Optional LLM vision OCR plugin"]
    SamplePlugin["packages/markitdown-sample-plugin<br/>Example plugin"]
    Examples["examples/<br/>FastAPI Quick UI"]
    Launcher["start.sh<br/>Launcher, env, setup, tests"]
    Docs["README.md and mermaid.md<br/>Project docs"]

    Root --> MainPkg
    Root --> MCPPkg
    Root --> OCRPkg
    Root --> SamplePlugin
    Root --> Examples
    Root --> Launcher
    Root --> Docs

    MainPkg --> CLI["markitdown CLI"]
    MainPkg --> API["MarkItDown Python API"]
    MainPkg --> Converters["Built-in converters"]
    Examples --> UI["quick_ui.py"]
    Examples --> Templates["quick_ui_templates/"]
    Examples --> Static["quick_ui_static/"]
```

## Main Conversion Pipeline

```mermaid
flowchart LR
    Input["Input<br/>Path, URL, stream, response, data URI"] --> Entry["MarkItDown.convert()"]
    Entry --> Route{"Source type?"}

    Route -->|"Local path"| Local["convert_local()"]
    Route -->|"HTTP/HTTPS/file/data URI"| URI["convert_uri()"]
    Route -->|"requests.Response"| Response["convert_response()"]
    Route -->|"Binary stream"| Stream["convert_stream()"]

    Local --> Guess["Build StreamInfo guesses"]
    URI --> Guess
    Response --> Guess
    Stream --> Guess

    Guess --> Detect["Magika + mimetype + extension + charset"]
    Detect --> Registry["Sorted converter registry"]
    Registry --> Accept{"converter.accepts()?"}
    Accept -->|"No"| Next["Try next converter"]
    Next --> Accept
    Accept -->|"Yes"| Convert["converter.convert()"]
    Convert --> Normalize["Normalize Markdown whitespace"]
    Normalize --> Result["DocumentConverterResult.markdown"]
```

## Converter Selection

```mermaid
flowchart TB
    Registry["Converter registry"]
    Priority["Priority order<br/>lower number runs first"]
    Specific["Specific converters<br/>PDF, DOCX, XLSX, PPTX, EPUB, image, audio"]
    Cloud["Optional cloud converters<br/>Document Intelligence, Content Understanding"]
    Generic["Generic converters<br/>HTML, ZIP, plain text"]
    Result["First successful converter returns Markdown"]

    Registry --> Priority
    Priority --> Cloud
    Priority --> Specific
    Priority --> Generic
    Cloud --> Result
    Specific --> Result
    Generic --> Result
```

## FastAPI Quick UI Flow

```mermaid
sequenceDiagram
    participant User
    participant Browser
    participant FastAPI as quick_ui.py
    participant MarkItDown
    participant Disk as /tmp/markitdown_quick_ui

    User->>Browser: Open local UI
    Browser->>FastAPI: GET /
    FastAPI-->>Browser: Render index.html

    User->>Browser: Upload file, enter URL, or select sample
    Browser->>FastAPI: POST /convert
    FastAPI->>MarkItDown: convert(path or URL)
    MarkItDown-->>FastAPI: Markdown result
    FastAPI->>Disk: Save result_id.md
    FastAPI-->>Browser: Preview Markdown + download link

    User->>Browser: Click Download Markdown
    Browser->>FastAPI: GET /download/{result_id}
    FastAPI->>Disk: Read result_id.md
    FastAPI-->>Browser: markitdown-output.md
```

## Plugin Flow

```mermaid
flowchart LR
    User["User enables plugins<br/>UI checkbox or enable_plugins=True"] --> Load["MarkItDown.enable_plugins()"]
    Load --> EntryPoints["Python entry points<br/>group: markitdown.plugin"]
    EntryPoints --> Plugin["Plugin module"]
    Plugin --> Register["register_converters(markitdown, **kwargs)"]
    Register --> Custom["Custom converter registered"]
    Custom --> Registry["Converter registry"]
    Registry --> Convert["Normal conversion pipeline"]
```

## OCR Plugin Path

```mermaid
flowchart TB
    File["PDF, DOCX, PPTX, XLSX"] --> OCRConverter["OCR-enhanced converter<br/>priority before built-ins"]
    OCRConverter --> Images["Extract embedded images<br/>or render scanned pages"]
    Images --> LLM{"llm_client and llm_model configured?"}
    LLM -->|"Yes"| Vision["Vision model extracts text"]
    LLM -->|"No"| Fallback["Skip OCR and fall back"]
    Vision --> Merge["Insert OCR text into document flow"]
    Fallback --> Builtin["Built-in converter"]
    Merge --> Markdown["Markdown output"]
    Builtin --> Markdown
```

## Optional Cloud Conversion

```mermaid
flowchart LR
    Input["Document, image, audio, or video"] --> Config{"Cloud endpoint configured?"}
    Config -->|"Document Intelligence"| DocIntel["Azure Document Intelligence converter"]
    Config -->|"Content Understanding"| CU["Azure Content Understanding converter"]
    Config -->|"No"| Local["Local built-in converter"]

    DocIntel --> Markdown["Markdown"]
    CU --> Fields["YAML front matter<br/>structured fields"]
    Fields --> Markdown
    Local --> Markdown
```

## Launcher Flow

```mermaid
flowchart TB
    Start["./start.sh"] --> Command{"Command"}

    Command -->|"run"| LoadEnv["Load .env"]
    LoadEnv --> CdExamples["cd examples/"]
    CdExamples --> RunUI["python quick_ui.py"]

    Command -->|"env status"| EnvStatus["Show set/missing keys<br/>without values"]
    Command -->|"env set KEY"| EnvSet["Prompt or write value to .env"]
    Command -->|"env edit"| EnvEdit["Open .env in editor"]
    Command -->|"install"| Install["uv pip install package + UI deps"]
    Command -->|"test"| Tests["py_compile + focused pytest checks"]
    Command -->|"--help"| Help["Print command reference"]
```

## Security Boundaries

```mermaid
flowchart TB
    Input["User-controlled input"] --> Validate["Validate source before conversion"]
    Validate --> LocalOnly["Use convert_local() for local-only workflows"]
    Validate --> StreamOnly["Use convert_stream() for uploaded files"]
    Validate --> URLFetch["For URLs, restrict schemes and destinations"]
    URLFetch --> Avoid["Avoid exposing UI publicly"]
    LocalOnly --> Safe["Least-capability conversion path"]
    StreamOnly --> Safe
    Avoid --> Safe
```

## Typical Local Workflow

```mermaid
flowchart LR
    Setup["./start.sh install"] --> Env["./start.sh env status"]
    Env --> Keys["./start.sh env set KEY"]
    Keys --> Run["./start.sh run"]
    Run --> Browser["Open http://127.0.0.1:8765"]
    Browser --> Convert["Convert file, URL, or sample"]
    Convert --> Download["Download Markdown"]
```
