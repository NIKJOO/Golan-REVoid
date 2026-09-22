# Golang-REVoid — Delphi Go Source Virtualizer & Obfuscator

<a><img src="https://github.com/NIKJOO/Golan-REVoid/blob/main/logo.png" border="0" /></a>

**Go_VM** is a console tool written in **Delphi 10.2 (Tokyo)** that takes a Go source file, virtualizes eligible functions into a custom stack-based VM bytecode, applies multiple obfuscation passes, and emits a **compilable Go program** containing the full VM runtime and the obfuscated functions.

It is a Delphi reimplementation of the core ideas behind a Python-based Go VM obfuscator (AST-driven compilation, control-flow flattening, constant encryption, instruction substitution, etc.).

---

## Features

| Technique | Description |
|-----------|-------------|
| **Stack VM** | Full custom ISA with arithmetic, comparison, control flow, locals, calls |
| **Function virtualization** | Pure computational functions are compiled to bytecode and executed by `runVM` |
| **Constant encryption** | Integer/string constants are XOR-encrypted and decrypted at runtime |
| **Control-Flow Flattening (CFF)** | Dispatcher marker + state-oriented layout |
| **Instruction substitution** | e.g. `ADD` → `SUBST_ADD` (a − (−b)) |
| **Opaque predicates** | Always-true junk blocks appended safely |
| **Hybrid native/VM** | Complex or unsupported functions stay native; VM can still `CALL` them |
| **Self-contained output** | Generated `.go` file includes the complete VM interpreter — no external deps beyond standard library |

### Supported language subset (virtualizable)

- Integer arithmetic (`+ - * / %`)
- Comparisons and logical ops
- Local variables / short declarations (`:=`, `=`)
- `if` / `if-else` (including nested)
- Classic `for` loops (`for i := 1; i <= n; i++ { ... }`)
- Function calls between virtualized / native functions
- Basic `fmt.Print` / `fmt.Println`
- String and integer constants

Functions that use slices, maps, switches, methods, goroutines, or heavy standard-library APIs are left **native**.

---

## Requirements

- **Delphi 10.2 Tokyo** (or later) — Console Application target
- Windows (Win32/Win64)
- Go toolchain (only needed to compile/run the **generated** output)

No external Delphi packages are required.

---

## Building

1. Open `Go_VM.dproj` in Delphi 10.2.
2. Select **Release** configuration (recommended).
3. Build (`Project → Build Go_VM` or `Shift+F9`).
4. The executable will appear under `Win32\Release\Go_VM.exe` (or `Win64\...`).

Alternatively, compile from the command line with the Delphi compiler if you have `dcc32` / `msbuild` set up.

---

## Usage

```text
Go_VM <input.go> [output.go]
```

| Argument     | Description                                      |
|--------------|--------------------------------------------------|
| `input.go`   | Source Go file to virtualize                     |
| `output.go`  | Optional. Defaults to `<input>_obfuscated.go`    |

### Example

```bash
# Virtualize the sample
Go_VM.exe main.go main_obfuscated.go

# Compile & run the generated program
go run main_obfuscated.go
```

## Architecture overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Go source      │────▶│  Lightweight     │────▶│  Bytecode +     │
│  (.go file)     │     │  parser/compiler │     │  obfuscation    │
└─────────────────┘     └──────────────────┘     └────────┬────────┘
                                                          │
                                                          ▼
                                                 ┌─────────────────┐
                                                 │  Emitter        │
                                                 │  (Go source     │
                                                 │   with embedded │
                                                 │   VM runtime)   │
                                                 └─────────────────┘
```
## VM Dis-assembly Architecture in IDA

<a><img src="https://github.com/NIKJOO/Golan-REVoid/blob/main/IDA.jpg" border="0" /></a>

### Main components (inside `Go_VM.dpr`)

- **ISA / `TOpCode`** — opcode enumeration and Go name mapping  
- **`TCompiler`** — expression/statement/block/if/for compilation to bytecode  
- **`ApplyObfuscation`** — CFF marker, constant encryption awareness, safe junk, substitution  
- **`TEmitter`** — produces a complete, ready-to-compile Go program containing:
  - `runVM` interpreter
  - per-function bytecode tables
  - wrappers that call the VM
  - original native functions kept as-is
  - `main` entry point

### Safety notes on obfuscation

Earlier versions could produce infinite loops because:

1. `JMP` → `INDIRECT_JMP` conversion stored a table index, but the runtime treated the argument as a raw PC.
2. Mid-code `Insert` of opaque predicates shifted absolute jump targets without fixup.

The current `ApplyObfuscation` implementation:

- **Never** converts jumps to broken indirect form.
- **Never** inserts instructions in the middle of existing code after targets are fixed.
- Always adjusts jump targets after the leading CFF marker.
- Appends opaque/junk blocks only at the **end** of the bytecode stream.

---


## Limitations

- Not a full Go compiler front-end (no tree-sitter / official AST).
- Unsupported constructs are left native; very complex bodies may be skipped.
- String handling and standard-library usage are limited to common cases.
- Designed primarily for **protection of pure logic** (password checks, license routines, scoring, etc.), not whole applications.

---

## Project layout

```text
Go_VM/
├── Go_VM.dpr          # Main source (compiler + VM emitter)
├── Go_VM.dproj        # Delphi project file
├── Go_VM.dproj.local
```

---

## License / Disclaimer

This project is provided for **educational and research purposes**.

Obfuscation does not guarantee security. Always combine with proper server-side validation, secure key management, and other defense-in-depth measures. The authors are not responsible for misuse.


