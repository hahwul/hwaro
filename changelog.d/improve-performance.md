### Changed
- Builds are substantially faster, with byte-identical HTML output: 5000-page listing-heavy corpus −37%, 5000-page blog corpus −14%, the docs site −29%. Small sites are unchanged.
- OG images and generated PNG variants now deflate through zlib instead of stb's bundled compressor. The images are pixel-identical and about 24% smaller, and encoding them is faster — cached OG images stay valid and are not regenerated.
