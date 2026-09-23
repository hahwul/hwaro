### Fixed
- CLI writers now refuse symlinks that escape their project roots. Import skips sources linked outside its input tree; export skips links outside the project, while deploy follows links within the project or resolved source root and skips targets outside both. Conversion preserves in-project symlink behavior and skips targets outside the project.
