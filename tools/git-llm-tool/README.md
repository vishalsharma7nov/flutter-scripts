# git-llm-tool → merged

This tool now lives inside **Flutter Scripts GUI**:

`tools/flutter_scripts_gui`

Open the app and use the **Git LLM** tab (next to Project / Scripts).

```bash
# From flutter-scripts repo
./open-flutter-scripts-gui.sh --project "$PWD"

# Or
cd tools/flutter_scripts_gui
./open-flutter-scripts-gui.sh   # if present
```

Optional local LLM:

```bash
brew install ollama && ollama serve
ollama pull qwen2.5-coder:7b
```

Standalone server files in this folder are obsolete; prefer `flutter_scripts_gui`.
