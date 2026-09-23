### Fixed
- CLI writers now refuse symlinks that escape their project roots. Import skips sources linked outside its input tree; export and deploy follow in-project links and skip targets outside the project. Conversion preserves in-project symlink behavior and skips targets outside the project.
