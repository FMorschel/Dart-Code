# dart_log_session

Enables every Dart-Code log file option in a workspace and gets it ready to
start a debug session.

The options are read from this checkout (`package.json` settings ending in
`LogFile`, plus `*LogFile` fields on `DartLaunchArgs`), so new upstream options
are picked up automatically.

```sh
cd tools/dart_log_session
dart run dart_log_session --list                       # show discovered options
dart run dart_log_session --workspace ~/my_app --open  # configure and open VS Code
```

It merges the paths into `.vscode/settings.json` and adds a `Logged session`
launch configuration to `.vscode/launch.json`. Comments in those files are
dropped on rewrite; the originals are kept as `*.bak`.

VS Code cannot be told to start a debug session from outside, so reload the
window and run the configuration yourself.
