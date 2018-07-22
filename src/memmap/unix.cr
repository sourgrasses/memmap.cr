require "./mman"

SC_PAGESIZE = 30

module Memmap::Mapped
  extend self

  enum Flags
    Shared  = LibC::MAP_SHARED
    Private = LibC::MAP_PRIVATE
    Fixed   = LibC::MAP_FIXED
  end

  enum Prot
    Read    = LibC::PROT_READ
    Write   = LibC::PROT_WRITE
    Exec    = LibC::PROT_EXEC
    None    = LibC::PROT_NONE
  end

  # A memory map backed by a specified file.
  class MappedFile
    PAGE_SIZE = LibC.sysconf(SC_PAGESIZE)

    def initialize(@filename : String, @flags : Flags, @prot : Prot)
    end

    def allocate
      fd =
        if @flags == Flags::Shared && File.writable?(@filename)
          File.open(@filename, mode="rw").fd
        elsif
          File.open(@filename, mode="r").fd
        else
          raise Errno.new("Unable to open file '#{@filename}'")
        end
    end

    def flush
    end

    def flush_async
    end

    def make_read_only
    end
  end

  class MappedOptions

  end
end
