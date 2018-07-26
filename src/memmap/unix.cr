require "./mman"

module Memmap
  extend self

  enum Flag
    Shared  = LibC::MAP_SHARED
    Private = LibC::MAP_PRIVATE
    Fixed   = LibC::MAP_FIXED
    Anon    = LibC::MAP_ANONYMOUS
  end

  enum Prot
    Read        = LibC::PROT_READ
    Write       = LibC::PROT_WRITE
    ReadWrite   = LibC::PROT_READ | LibC::PROT_WRITE
    None        = LibC::PROT_NONE
  end

  # A memory mapped buffer backed by a specified file.
  #
  # The safest way to access the data mapped is through the `value` getter, which returns a `Slice(UInt8)`.
  # Any access through the raw pointer interface can cause segmentation faults or undefined behavior unless you're really careful, 
  # while accessing the buffer through a `Slice` allows you to reap the potential benefits of using `mmap` without shooting
  # yourself in the foot because of its bound checks.
  class MapFile
    {% if flag?(:x86_64) || flag?(:aarch64) %}
      PAGE_SIZE = LibC.sysconf(LibC::SC_PAGESIZE).to_u64
    {% elsif flag?(:i686) || flag?(:arm) || flag?(:win32) %}
      PAGE_SIZE = LibC.sysconf(LibC::SC_PAGESIZE).to_u32
    {% end%}

    DEFAULT_PERM = File::Permissions.new(0o644)
    @flag : Flag
    @prot : Prot
    @len : LibC::SizeT
    @map : UInt8*
    @value : Bytes

    getter value

    # Create an instance of `MapFile`.
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

      @map = alloc(aligned_len, aligned_offset)
      @value = Slice.new(@map, @len)
    end

    # :nodoc:
    def finalize
      close()
    end

    protected def alloc(aligned_len : LibC::SizeT, aligned_offset : LibC::SizeT) : UInt8*
      fd =
        if @flag == Flag::Shared && File.writable?(@filepath)
          File.open(@filepath, mode = "r+", perm = DEFAULT_PERM).fd
        elsif File.readable?(@filepath)
          File.open(@filepath, mode = "r", perm = DEFAULT_PERM).fd
        else
          raise Errno.new("Unable to open file '#{@filepath}'")
        end

      ptr = LibC.mmap(Pointer(Void).null, aligned_len, @prot.value, @flag.value, fd, aligned_offset)

      if ptr == LibC::MAP_FAILED
        raise Errno.new("Unable to create map")
      end

      # Cast the `void*` returned by `mmap()` to a `char*`, `UInt8*` in Crystal
      Pointer(UInt8).new(ptr.address)
    end

    # :nodoc:
    def append
      # TODO: mremap and some other fiddly stuff?
      {% if flag?(:linux) %}
      {% elsif flag?(:darwin)  || flag?(:freebsd) || flag(:openbsd) %}
      {% end %}
    end

    # Returns the buffer as a raw `Pointer(UInt8)`. This is unsafe, obviously.
    def as_ptr
      @map
    end

    # Force the map to close before the GC runs `finalize`
    def close
      len = get_aligned_len()
      if LibC.munmap(@map, len) == -1
        raise Errno.new("Error unmapping file")
      end
    end

    # Flush changes made in the map back into the filesystem. Synchronous/blocking version.
    def flush
      LibC.msync(@map, @len, LibC::MS_SYNC)
    end

    # :nodoc:
    def flush_async
    end

    # Call `mprotect` to change the 'prot' flags to be read-only
    def make_read_only
      len = get_aligned_len()
      LibC.mprotect(@map, len, Prot::Read)
    end

    # Call `mprotect` to change the 'prot' flags to allow reading and writing
    def make_writable
      len = get_aligned_len()
      LibC.mprotect(@map, len, Prot::ReadWrite)
    end

    def to_s
      @value.to_s()
    end

    # Append a `Slice(UInt8)`/`Bytes` to a mapped file by writing the already-mapped buffer concatenated
    # with the new bytes to a newly allocated mapped buffer backed by a new file.
    # This relies on `ftruncate` and some pointer arithmetic to work correctly, so tread carefully.
    # If you point it in the wrong direction it will eat your data.
    def write(filepath : String, appendix : Bytes) : Symbol
      len = get_aligned_len() + appendix.size
      # Clean the path out and write a garbage byte in there
      File.write(filepath, "\0")
      fd = File.open(filepath, mode = "r+", perm = DEFAULT_PERM).fd

      if LibC.ftruncate(fd, len) == -1
        return :err
      end

      ptr = LibC.mmap(Pointer(Void).null, len, Prot::ReadWrite, Flag::Shared, fd, @offset)
      ptr = Pointer(UInt8).new(ptr.address)

      @map.copy_to(ptr, get_aligned_len())
      appendix.copy_to(ptr + get_aligned_len(), appendix.size)
      LibC.msync(ptr, len, LibC::MS_SYNC)

      if LibC.munmap(ptr, len) == -1
        return :err
      end

      :ok
    end

    protected def parse_mode(mode : String)
      if mode.size == 0 || mode.size > 2
        raise "Invalid access mode"
      end

      flag = Flag::Private
      prot = Prot::None

      case mode[0]
      when 'r'
        if mode.size == 2 && mode[1] == '+'
          flag = Flag::Shared
          prot = Prot::ReadWrite
        else
          flag = Flag::Private
          prot = Prot::Read
        end
      when 'w'
        prot = Prot::Write
      end

      {flag, prot}
    end

    protected def get_aligned_len
      alignment = instance_sizeof(typeof(@map)) % PAGE_SIZE
      (@len + alignment).as(LibC::SizeT)
    end
  end
end
