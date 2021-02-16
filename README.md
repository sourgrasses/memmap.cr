# memmap.cr
[![Build Status](https://travis-ci.org/sourgrasses/memmap.cr.svg?branch=master)](https://travis-ci.org/sourgrasses/memmap.cr/)
[![Crystal Docs](https://img.shields.io/badge/Crystal-Docs-8A2BE2.svg)](https://sourgrasses.github.io/memmap/)

Little lib to make using [`mmap()`](http://man7.org/linux/man-pages/man2/mmap.2.html) and related system calls relatively easy and hopefully fairly idiomatic.

Currently you can use either the `<<` operator/`push` function to append `Bytes` to a mapped file, which calls `ftruncate` to expand te file size to fit the new data, advances the seek pointer to the old end of the file, writes whatever has been pushed, and calls `mremap` on Linux or simply `munmap` and then `mmap` elsewhere, or, if you prefer to copy the contents of the mapped file to a new mapped file with the new `Bytes` appended, you can call `MapFile.write` to `ftruncate` a file, create a new mapped buffer of the fixed size, and `memcpy` from the read buffer and the `Bytes` to be appended into the second buffer.

Calling the instance method `value` gets a `Bytes`/`Slice(UInt8)` that can be read from and manipulated in place safely.

Written with continual reference to the [memmap crate](https://github.com/danburkert/memmap-rs) for Rust.

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  memmap:
    github: sourgrasses/memmap.cr
```

## Usage

```crystal
require "memmap"

# Maps a file named "test.txt" and prints it to stdout
file = Memmap::MapFile.new("test.txt")
puts String.new(file.value)

# Maps a file and replaces every character with 'j'
file2 = Memmap::MapFile.new("test.txt", mode = "r+")
file2.value.map! { |v| 106.to_u8 }
file2.flush()

# Writes a string to a file, maps it, and then appends a string to it
File.write("test.txt", "here are a bunch of bytes yet again")
file = Memmap::MapFile.new("test.txt", mode = "r+")
appendix = " and more!".to_slice
file << appendix
```
## Contributing

1. Fork it (<https://github.com/sourgrasses/memmap.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [sourgrasses](https://github.com/sourgrasses) Jenn Wheeler - creator, maintainer
