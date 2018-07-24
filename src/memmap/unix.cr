require "./mman"

SC_PAGESIZE = 30

module Memmap
  extend self

  enum Flag
    Shared  = LibC::MAP_SHARED
    Private = LibC::MAP_PRIVATE
    Fixed   = LibC::MAP_FIXED
    Anon    = LibC::MAP_ANONYMOUS
  end

  enum Prot
    Read    = LibC::PROT_READ
    Write   = LibC::PROT_WRITE
    Exec    = LibC::PROT_EXEC
    None    = LibC::PROT_NONE
  end

  # A memory mapped buffer backed by a specified file.
  class MappedFile
    PAGE_SIZE = LibC.sysconf(SC_PAGESIZE).as(LibC::SizeT)
    @map : UInt8*
    @len : LibC::SizeT

    def initialize(@filepath : String, mode = "r" @flags : Flag, @prot : Prot, offset : LibC::SizeT = 0)
      @len = File.info(@filepath).size
      alignment = offset % PAGE_SIZE
      aligned_offset = offset - alignment
      aligned_len = len + alignment

      (@flags, @prot) = parse_mode(mode)

      @map = allocate(aligned_len, aligned_offset)
    end

    def finalize
      # TODO: calculate len stuff
      len = 0.as(LibC::SizeT)
      if LibC.munmap(@map, len) == -1
        raise Errno.new("Error unmapping file")
      end
    end

    protected def allocate(aligned_len : SizeT, aligned_offset : SizeT) : UInt8*
      fd =
        if @flags == Flag::Shared && File.writable?(@filepath)
          File.open(@filepath, mode="rw").fd
        elsif
          File.open(@filepath, mode="r").fd
        else
          raise Errno.new("Unable to open file '#{@filepath}'")
        end

      ptr = LibC.mmap(nil, aligned_len, prot, flags, fd, aligned_offset)

      if ptr == LibC::MAP_FAILED
        raise Errno.new("Unable to create map")
      end

      # Cast the `void*` returned by `mmap()` to a `char*`, `UInt8*` in Crystal
      Pointer(UInt8).new(ptr.address)
    end

    protected def parse_mode(mode : String)
      if mode.size == 0
        raise "Invalid access mode"
      end

      prot = Array(Prot).new

      case mode[0]
      when 'r'
        prot.push(Prot::Read)
      when 'w'
        prot.push(Prot::Write)
      end

      case mode[1]
      when 'w'
        prot.push(Prot::Read)
      when 'a'
        flags = Flag::Anon
      end
    end

    # Flush changes made in the map back into the filesystem.
    # Synchronous/blocking version.
    def flush
      LibC.msync(@map, @len, LibC::MS_SYNC)
    end

    def flush_async
    end

    def make_read_only
      # TODO: calculate len stuff
      len = 0.as(LibC::SizeT)
      LibC.mprotect(@map, len, Prot::Read)
    end

    def make_writable
      # TODO: calculate len stuff
      len = 0.as(LibC::SizeT)
      LibC.mprotect(@map, len, Prot::Write | Prot::Read)
    end
  end
end
