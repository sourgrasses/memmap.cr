require "./mman"

SC_PAGESIZE = 30

module Memmap
  extend self

  @[Flags]
  enum Flag
    Shared  = LibC::MAP_SHARED
    Private = LibC::MAP_PRIVATE
    Fixed   = LibC::MAP_FIXED
    Anon    = LibC::MAP_ANONYMOUS
  end

  @[Flags]
  enum Prot
    Read    = LibC::PROT_READ
    Write   = LibC::PROT_WRITE
    None    = LibC::PROT_NONE
  end

  # A memory mapped buffer backed by a specified file.
  class MapFile
    PAGE_SIZE = LibC.sysconf(SC_PAGESIZE)
    DEFAULT_PERM = File::Permissions.new(0o644)
    @flag : Flag
    @prot : Prot
    @len : LibC::SizeT
    @map : UInt8*

    getter len
    getter map

    def initialize(@filepath : String, mode = "r", @offset : LibC::SizeT = 0)
      stat = uninitialized LibC::Stat
      if LibC.stat(@filepath.check_no_null_byte, pointerof(stat)) == 0
        @len = Crystal::System::FileInfo.new(stat).size
      else
        raise Errno.new("Error `stat`ing specified path")
      end

      alignment = @offset % PAGE_SIZE
      aligned_offset = @offset - alignment
      aligned_len = @len + alignment

      @flag, @prot = parse_mode(mode)

      @map = allocate(aligned_len, aligned_offset)
    end

    def finalize
      len = get_aligned_len()
      if LibC.munmap(@map, len) == -1
        raise Errno.new("Error unmapping file")
      end
    end

    protected def allocate(aligned_len : LibC::SizeT, aligned_offset : LibC::SizeT) : UInt8*
      fd =
        if @flag == Flag::Shared && File.writable?(@filepath)
          File.open(@filepath, mode = "rw", perm = DEFAULT_PERM).fd
        elsif File.readable?(@filepath)
          File.open(@filepath, mode = "r", perm = DEFAULT_PERM).fd
        else
          raise Errno.new("Unable to open file '#{@filepath}'")
        end

      ptr = LibC.mmap(nil, aligned_len, @prot, @flag, fd, aligned_offset)

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

      flag = Flag::Private
      prot = Prot::None

      case mode[0]
      when 'r'
        prot = Prot::Read
        if mode.size == 2 && mode[1] == 'w'
          flag = Flag::Shared
          prot |= Prot::Write
        else
          flag = Flag::Private
        end
      when 'w'
        prot = Prot::Write
      end

      {flag, prot}
    end

    # Flush changes made in the map back into the filesystem.
    # Synchronous/blocking version.
    def flush
      LibC.msync(@map, @len, LibC::MS_SYNC)
    end

    # Unimplemented right now
    def flush_async
    end

    def make_read_only
      len = get_aligned_len()
      LibC.mprotect(@map, len, Prot::Read)
    end

    def make_writable
      len = get_aligned_len()
      LibC.mprotect(@map, len, Prot::Write | Prot::Read)
    end

    protected def get_aligned_len
      alignment = instance_sizeof(typeof(@map)) % PAGE_SIZE
      (@len + alignment).as(LibC::SizeT)
    end
  end
end
